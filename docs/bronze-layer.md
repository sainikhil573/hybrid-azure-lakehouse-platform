# Bronze Layer — Metadata-Driven Landing-to-Delta Processing

## 1. Overview

The Bronze layer is the first Delta Lake processing layer in the **Hybrid On-Premises to Azure Lakehouse Data Platform**.

Its purpose is to read previously ingested data from Azure Data Lake Storage Gen2 (ADLS Gen2) Landing, preserve source records with minimal transformation, attach ingestion lineage metadata, and store the resulting datasets in Delta Lake format.

The solution uses Azure Data Factory (ADF) for orchestration and Azure Databricks with PySpark for data processing.

**Implementation status:** Completed and validated for all nine currently registered source objects.

**Current load strategy:** Full refresh using Delta overwrite.

## 2. Architecture

```text
ON-PREMISES / LOCAL SOURCE SYSTEMS

SQL Server        MySQL          SFTP
    |               |              |
    +---------------+--------------+
                    |
          Self-Hosted IR + ADF
                    |
                    v
              ADLS Gen2
          Landing (Parquet)
                    |
                    |
         ADF Bronze Pipeline
         pl_landing_to_bronze
                    |
       Lookup ingestion metadata
                    |
               ForEach
                    |
          Databricks Notebook
           nb_landing_to_bronze
                    |
             PySpark Processing
                    |
         Add Technical Metadata
                    |
            Write Delta Format
                    |
                    v
              ADLS Gen2
             Bronze (Delta)
                    |
            Row Count Validation
```

The original source ingestion is implemented in separate ADF pipelines. The Bronze pipeline does not re-extract the business data from SQL Server, MySQL or SFTP.

It reads orchestration metadata from the on-premises SQL Server control database and processes the corresponding files already stored in ADLS Landing.

## 3. Azure Resources

| Component | Resource |
|---|---|
| Resource group | `rg-hybrid-lakehouse-dev` |
| Azure Data Factory | `adf-hybrid-lakehouse-dev` |
| Storage account | `sthybridlakeprojectdev` |
| Landing container | `landing` |
| Bronze container | `bronze` |
| Databricks workspace | `dbw-hybrid-lakehouse-dev` |
| ADF Bronze pipeline | `pl_landing_to_bronze` |
| Databricks notebook | `nb_landing_to_bronze` |
| Databricks linked service | `ls_databricks_hybrid_lakehouse` |
| Git feature branch | `feature/bronze-layer` |

### Databricks development compute

The implementation was tested using existing All-Purpose, single-node Databricks compute.

- Runtime: Databricks Runtime 16.4 LTS
- Node type used in the successful development configuration: `Standard_D4a_v4`
- Execution mode: Single node
- Auto termination: 10 minutes of inactivity
- ADF compute connection: Existing interactive cluster

This configuration is intended for cost-conscious development and testing. It is not a production cluster-sizing recommendation.

## 4. Source Objects

The Bronze framework processes nine registered ingestion objects across three source systems.

| Source system | Connection ID | Source object | Landing folder | Bronze folder |
|---|---|---|---|---|
| SQL Server | 1 | transactions_2021 | sqlserver/transactions_2021 | sqlserver/transactions_2021 |
| SQL Server | 1 | transactions_2022 | sqlserver/transactions_2022 | sqlserver/transactions_2022 |
| SQL Server | 1 | transactions_2023 | sqlserver/transactions_2023 | sqlserver/transactions_2023 |
| SQL Server | 1 | calendar | sqlserver/calendar | sqlserver/calendar |
| MySQL | 2 | product | mysql/product | mysql/product |
| MySQL | 2 | category | mysql/category | mysql/category |
| MySQL | 2 | subcategory | mysql/subcategory | mysql/subcategory |
| SFTP | 3 | channel.csv | sftp/channel | sftp/channel |
| SFTP | 3 | promotion.csv | sftp/promotion | sftp/promotion |

All nine objects were reported successfully processed with passing notebook validation.

The SFTP source files originate as CSV but are stored as Parquet in Landing, allowing the Bronze notebook to use a common Parquet reader.

## 5. Metadata-Driven Orchestration

### Metadata source

The control table is:

`metadata_schema.ingestion_object`

It is stored in the on-premises SQL Server database and accessed through the existing self-hosted integration runtime.

Relevant metadata fields:

| Column | Purpose |
|---|---|
| ingestion_id | Unique ingestion object identifier |
| connection_id | Identifies source-system type |
| source_schema | Original source schema where applicable |
| source_object | Original table or file name |
| object_type | Source object classification |
| load_type | Configured ingestion load type |
| target_container | ADLS Landing container from the source-ingestion stage |
| target_folder | ADLS Landing folder from the source-ingestion stage |
| file_format | Configured file format metadata |
| is_active | Controls which registered objects are eligible for processing |

The field `target_container` represents the target of the earlier source-to-Landing ingestion stage. That location becomes the source for the Landing-to-Bronze processing stage.

### Lookup query

```sql
SELECT
    ingestion_id,
    connection_id,
    source_schema,
    source_object,
    object_type,
    load_type,
    target_container,
    target_folder,
    file_format
FROM metadata_schema.ingestion_object
WHERE is_active = 1;
```

The Lookup activity `lkp_bronze_ingestion_metadata` retrieves all active registered objects.

Its `First row only` option is disabled to return an array of metadata records.

### ForEach configuration

Activity:

`fe_process_landing_objects`

Items expression:

```text
@activity('lkp_bronze_ingestion_metadata').output.value
```

Execution is sequential for the development implementation, prioritizing predictable resource use and straightforward troubleshooting.

### Databricks Notebook activity

Activity:

`nb_execute_landing_to_bronze`

Notebook:

`nb_landing_to_bronze`

ADF passes five base parameters:

| Parameter | Purpose |
|---|---|
| source_system | Derived from connection ID |
| source_object | Name of the source table or file |
| landing_path | Metadata-derived Landing ADLS URI |
| bronze_path | Metadata-derived Bronze ADLS URI |
| load_id | Pipeline run ID combined with ingestion ID |

### Dynamic parameter expressions

**source_system**

```text
@if(equals(item().connection_id,1),'sqlserver',if(equals(item().connection_id,2),'mysql','sftp'))
```

**source_object**

```text
@item().source_object
```

**landing_path**

```text
@concat('abfss://',item().target_container,'@sthybridlakeprojectdev.dfs.core.windows.net/',item().target_folder,'/')
```

**bronze_path**

```text
@concat('abfss://bronze@sthybridlakeprojectdev.dfs.core.windows.net/',item().target_folder,'/')
```

**load_id**

```text
@concat(pipeline().RunId,'_',string(item().ingestion_id))
```

All ADF dynamic expressions must be stored as expressions and begin directly with `@`, without leading newlines.

## 6. Databricks Notebook Implementation

### Notebook widgets

The notebook receives configuration through five Databricks widgets.

```python
dbutils.widgets.text("source_system", "")
dbutils.widgets.text("source_object", "")
dbutils.widgets.text("landing_path", "")
dbutils.widgets.text("bronze_path", "")
dbutils.widgets.text("load_id", "")
```

Parameters are retrieved using:

```python
source_system = dbutils.widgets.get("source_system")
source_object = dbutils.widgets.get("source_object")
landing_path = dbutils.widgets.get("landing_path")
bronze_path = dbutils.widgets.get("bronze_path")
load_id = dbutils.widgets.get("load_id")
```

### Read Landing Parquet

```python
df = spark.read.format("parquet").load(landing_path)
```

The notebook reads the files from the Landing folder passed by ADF.

### Technical metadata

```python
from pyspark.sql.functions import current_timestamp, lit

bronze_df = (
    df
    .withColumn("LoadID", lit(load_id))
    .withColumn("ingestion_timestamp", current_timestamp())
    .withColumn("source_system", lit(source_system))
    .withColumn("source_object", lit(source_object))
)
```

The Bronze layer preserves source records while adding operational lineage columns.

| Column | Purpose |
|---|---|
| LoadID | Associates a Bronze load with its pipeline execution and ingestion object |
| ingestion_timestamp | Records Bronze ingestion time |
| source_system | Identifies the original source system |
| source_object | Identifies the original table or file |

### Write Bronze Delta

```python
(
    bronze_df.write
    .format("delta")
    .mode("overwrite")
    .save(bronze_path)
)
```

The output is stored as Delta Lake data in the Bronze container.

**Current behavior:** Each execution replaces the existing Delta contents for that object.

The notebook currently implements full-refresh behavior. Incremental writes, historical load retention and change-data capture have not been implemented.

## 7. Data Validation

The notebook compares Landing and Bronze record counts after writing the Delta output.

```python
landing_df = spark.read.parquet(landing_path)
bronze_check = spark.read.format("delta").load(bronze_path)

landing_count = landing_df.count()
bronze_count = bronze_check.count()

print("Source system:", source_system)
print("Source object:", source_object)
print("Landing rows:", landing_count)
print("Bronze rows:", bronze_count)

bronze_check.select(
    "LoadID",
    "ingestion_timestamp",
    "source_system",
    "source_object"
).show(5, truncate=False)

assert landing_count == bronze_count, "Landing/Bronze row count mismatch"
assert source_system.strip(), "Missing source_system"
assert source_object.strip(), "Missing source_object"

print("Bronze validation PASSED")
```

### Verified calendar example

| Check | Actual result |
|---|---|
| Source system | sqlserver |
| Source object | calendar |
| Landing rows | 1,095 |
| Bronze rows | 1,095 |
| LoadID | Populated |
| Ingestion timestamp | Populated |
| Row-count validation | PASSED |

### Full execution

All nine registered source objects completed the Bronze pipeline with passing notebook validations.

The current checks verify row-count equality, readable Delta output, and nonempty source parameter values. More comprehensive checks for persisted lineage values, schema compatibility, duplicates and data-quality constraints are future improvements.

## 8. Security and Access

The implementation uses:

- A dedicated SQL Server metadata access account.
- Self-Hosted Integration Runtime for on-premises SQL Server connectivity.
- A Databricks Access Connector with managed identity for ADLS access.
- Databricks storage credentials and external locations for Landing and Bronze.
- ADF Databricks linked-service authentication for notebook orchestration.
- A private Azure DevOps repository for implementation artifacts.

Storage access was configured with Azure Storage Blob Data Contributor permissions on the relevant storage account.

For development, the Databricks linked service used a personal access token. Longer-term improvements include stronger service identity management, appropriate permission scoping and secure secret references.

Passwords, personal access tokens, account keys and other reusable credentials must never be committed to public GitHub.

## 9. Design Decisions

### Metadata-driven execution

A single pipeline processes multiple registered objects using control-table metadata rather than separate pipelines for each source table.

### Source-preserving Bronze

Bronze performs minimal transformations and adds technical lineage metadata. Business cleaning and standardization are deferred to Silver.

### Delta Lake storage

Delta format provides transactional table storage and supports later lakehouse processing.

### Sequential execution

ForEach is configured sequentially to simplify troubleshooting and limit concurrent execution on the development compute.

### Reusable notebook

The same notebook processes objects from SQL Server, MySQL and SFTP by accepting source information and storage paths through parameters.

### Full-refresh implementation

Overwrite mode is currently used to validate the initial data-loading framework. Incremental and historical processing require further design.

## 10. Current Limitations and Future Improvements

The following capabilities are not yet implemented or fully validated:

1. Incremental Bronze ingestion and watermark management.
2. Idempotent historical load processing and append/upsert strategies.
3. Automated discovery of new, unregistered ADLS folders.
4. Dedicated Bronze-stage activation and destination metadata.
5. Automated audit logging and operational alerting.
6. Automated retry and recovery policies.
7. Comprehensive persisted lineage and schema validation.
8. Production-scale compute sizing and performance benchmarking.
9. Automated CI/CD deployment and integration tests.

The pipeline discovers registered active metadata objects, not every arbitrary file or folder in ADLS.

## 11. Execution and Cost Controls

During development:

- A single-node Databricks All-Purpose cluster was used.
- The existing compute was connected to ADF.
- Auto termination was configured for 10 minutes.
- Manual termination was used when compute was no longer needed.
- Sequential execution limited notebook concurrency.
- Small individual objects were validated before the full nine-object run.

All-Purpose Compute incurs usage charges while running and is not automatically the most economical choice for scheduled production execution.

A future implementation should evaluate job compute, compute policies, scheduling, throughput and cost.

## 12. Validation Evidence and Delivery Status

**Completed implementation:**

- Metadata Lookup across registered source systems.
- Sequential ForEach orchestration.
- Parameterized Databricks notebook execution.
- Landing Parquet reads.
- Bronze Delta writes.
- Technical lineage columns.
- Row-count validation.
- Tests across SQL Server, MySQL and SFTP.
- Successful full nine-object execution.

**Repository delivery pending verification:**

- Notebook artifact committed to Git.
- Final credentials and repository secret scan.
- Bronze feature Pull Request review and merge.
- Completion of Azure DevOps work items.

The Bronze processing implementation is complete for the current full-refresh scope, but feature delivery and production hardening remain separate activities.
