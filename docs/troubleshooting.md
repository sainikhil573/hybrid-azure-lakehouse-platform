# Troubleshooting Guide

This document records implementation issues encountered while building the Hybrid Azure Lakehouse Data Platform and the steps used to resolve them.

The purpose is to preserve practical debugging knowledge and provide repeatable recovery steps.

---

## 1. SQL Server Copy Failed Due to Buffer Pool Memory

### Problem

The SQL Server to ADLS pipeline failed while copying the large `transactions_2021` table.

ADF reported:

```text
There is insufficient memory available in the buffer pool.
```

The failed Copy activity read only a small portion of the source table before stopping.

### Investigation

The source table contained more than one million rows.

Windows Task Manager showed high system memory utilization during the copy operation.

SQL Server was also using the default effectively unlimited configuration for:

`max server memory (MB)`

The original copy attempted to read the large table without source partitioning.

### Resolution

The table was evaluated for a suitable numeric partition column.

`ProductKey` was selected because:

- datatype: `INT`
- minimum value: `1`
- maximum value: `2517`
- high number of distinct values

ADF Copy Activity was configured with:

```text
Partition option: Dynamic range
Partition column: ProductKey
Lower bound: 1
Upper bound: 2517
```

The pipeline was then rerun successfully.

### Lesson Learned

Large relational source tables should not always be extracted as one continuous stream.

Dynamic range partitioning can improve stability and throughput by dividing the source read into smaller ranges.

---

## 2. Incorrect Dataset Parameter Expression

### Problem

The SQL Server Copy activity failed with an error similar to:

```text
Invalid object name 'dbo.table_name = @item().source_object'
```

### Cause

The entire assignment text had been entered into the dataset parameter value:

```text
table_name = @item().source_object
```

ADF interpreted this as a literal table name.

### Resolution

Only the dynamic expression was entered in the Value field:

```text
@item().source_object
```

Similarly:

```text
@item().source_schema
```

was used for the schema parameter.

### Lesson Learned

ADF dataset parameter fields already contain the parameter name.

Only the expression should be entered as the parameter value.

---

## 3. Lookup Returned No Rows but Pipeline Succeeded

### Problem

A failure test was attempted by filtering the SFTP metadata Lookup for:

`missing_file.csv`

The pipeline still showed a successful status.

### Cause

The Lookup query returned an empty array.

The ForEach activity received no items, so it had nothing to execute.

ADF treats an empty ForEach as successful rather than as an error.

### Resolution

The Lookup query was restored so that valid SFTP metadata rows were returned.

The Copy activity source file parameter was then temporarily changed to:

`missing_file.csv`

This caused:

```text
Lookup → Succeeded
ForEach → Failed
Copy Data → Failed
Pipeline → Failed
```

ADF Monitor successfully captured the error.

The source parameter was then restored to:

```text
@item().source_object
```

and the pipeline succeeded again.

### Lesson Learned

A metadata Lookup returning zero rows is not automatically a pipeline failure.

To test downstream failure handling, the pipeline must receive a valid work item and fail during an activity such as Copy Data.

---

## 4. MySQL Lookup Used the Wrong Dataset

### Problem

The MySQL pipeline Lookup failed with:

```text
SELECT command denied to user 'adf_reader'@'localhost'
for table 'ingestion_object'
```

### Cause

The Lookup activity had been configured with the MySQL dataset.

However, the ingestion metadata table exists in SQL Server:

`metadata_schema.ingestion_object`

The MySQL read-only account therefore attempted to access a table that did not belong to the MySQL source design.

### Resolution

The Lookup dataset was changed back to:

`ds_sqlserver_source`

with:

```text
schema_name = metadata_schema
table_name = ingestion_object
```

The MySQL dataset was used only inside the Copy activity for extracting MySQL source tables.

### Lesson Learned

The control metadata repository and business source system are separate concerns.

In this project, SQL Server hosts the centralized ingestion metadata even when the actual source data comes from MySQL or SFTP.

---

## 5. MySQL ADF Reader User Already Existed

### Problem

Creating the MySQL account returned:

```text
Error Code: 1396
Operation CREATE USER failed for 'adf_reader'@'localhost'
```

### Cause

The `adf_reader` user already existed.

### Resolution

The existing account was identified using:

```sql
SELECT user, host
FROM mysql.user
WHERE user = 'adf_reader';
```

The password was reset using:

```sql
ALTER USER 'adf_reader'@'localhost'
IDENTIFIED BY '<PASSWORD_FROM_SECURE_STORE>';
```

Read-only access was confirmed using:

```sql
GRANT SELECT
ON bhaskar_retail_db.*
TO 'adf_reader'@'localhost';
```

and:

```sql
SHOW GRANTS FOR 'adf_reader'@'localhost';
```

### Lesson Learned

Existing service accounts should be checked before creating new accounts.

---

## 6. SFTP Authentication and Local Account Configuration

### Problem

The original Windows username contained a space and caused issues when testing SFTP login.

### Resolution

A dedicated local Windows account was created:

`sftp_reader`

SFTP authentication was successfully validated using:

```text
sftp sftp_reader@localhost
```

The account was granted access to the local SFTP source folder containing:

- `channel.csv`
- `promotion.csv`

### Lesson Learned

Dedicated service accounts provide cleaner authentication and better separation of responsibilities than personal operating-system accounts.

---

## Monitoring Validation

ADF Monitor was used to validate both successful and failed pipeline executions.

The monitoring view confirmed:

- successful pipeline runs
- failed pipeline runs
- successful Lookup activities
- failed Copy activities
- failed ForEach activities
- activity duration
- Integration Runtime usage
- detailed error information

The intentional SFTP failure was corrected and followed by a successful rerun, demonstrating a complete troubleshooting and recovery cycle.

---

## Security Notes

Passwords, access keys, and authentication secrets must not be committed to Git.

Repository scripts use placeholders such as:

```text
<PASSWORD_FROM_SECURE_STORE>
```

Dedicated read-only accounts are used whenever possible for source-system ingestion.


---

# Databricks Bronze Layer — Troubleshooting and Resolution

This section documents technical issues encountered while implementing the metadata-driven Landing-to-Bronze processing pipeline.

**Pipeline:** `pl_landing_to_bronze`  
**Notebook:** `nb_landing_to_bronze`  
**Environment:** Azure East US  
**Phase:** Databricks Bronze Layer

## Issue 1 — ADF datasets missing from the feature branch

**Problem:** Existing ADF datasets were visible in the `main` branch but missing from `feature/bronze-layer`.

**Root cause:** The feature branch did not contain the latest committed Landing ingestion artifacts from the main branch.

**Resolution:**

1. Inspected the Git branches in Azure DevOps.
2. Confirmed the completed ADF datasets existed in `main`.
3. Created a synchronization Pull Request from `main` into `feature/bronze-layer`.
4. Checked for merge conflicts.
5. Completed the merge.
6. Verified that all four datasets appeared in the feature branch.

**Lesson learned:** Synchronize completed upstream dependencies into a feature branch before building new pipeline functionality.

## Issue 2 — SQL Server Lookup failed with JSON parsing error

**Error:**

```text
Unexpected character encountered while parsing value: <.
Path '', line 0, position 0.
```

**Problem:** ADF Lookup could not read the on-premises ingestion metadata table.

**Root cause:** Encrypted credential fields in linked-service configuration had previously been replaced with placeholder text during repository sanitization.

Example invalid credential configuration:

```json
"encryptedCredential": "<ENCRYPTED_CREDENTIAL_REMOVED>"
```

**Resolution:**

1. Opened the SQL Server linked service in ADF.
2. Re-entered the dedicated `adf_reader` account password through the ADF interface.
3. Successfully tested the connection.
4. Re-executed the metadata Lookup.
5. Confirmed records were returned.

**Lesson learned:** Sanitization should be performed on a separate public-export artifact, without breaking the configuration used by the active private development environment. A secure deployment mechanism and secret-management strategy are required.

## Issue 3 — Databricks VM capacity stockout

**Error:**

```text
CLOUD_PROVIDER_RESOURCE_STOCKOUT
SkuNotAvailable: Standard_DS3_v2
Location: eastus
```

**Problem:** ADF successfully submitted the Databricks notebook execution, but Azure could not provision the selected VM type.

**Root cause:** The requested compute SKU was unavailable because of regional capacity restrictions at the time of execution.

**Resolution attempted:** Changed the Databricks job cluster node type to `Standard_D4as_v5`.

This removed the original VM-size selection but exposed an additional subscription quota limitation.

**Lesson learned:** VM SKU availability and subscription quota are separate requirements. Both must be satisfied for cluster provisioning.

## Issue 4 — Insufficient Azure CPU quota

**Problem:** The Databricks job cluster could not start using the replacement VM type.

**Observed configuration:**

| Resource | vCPUs |
|---|---:|
| Driver | 4 |
| Worker | 4 |
| Total requested | 8 |
| Available DASv5 family quota | 4 |

**Root cause:** The driver-plus-worker configuration exceeded the available VM-family quota.

**Resolution:**

1. Reviewed the Azure regional VM-family quota.
2. Evaluated smaller development compute configurations.
3. Created an existing All-Purpose single-node cluster using `Standard_D4a_v4`.
4. Used Databricks Runtime 16.4 LTS.
5. Configured 10-minute automatic termination.
6. Reconfigured the ADF linked service to use Existing interactive cluster.
7. Successfully executed the notebook.

**Lesson learned:** For small development workloads, single-node Spark compute may be sufficient and can reduce required vCPU capacity. This should not be presented as a substitute for distributed-compute scalability testing.

## Issue 5 — Missing Bronze lineage metadata

**Problem:** Row counts matched after the initial `calendar` execution, but source lineage metadata was missing.

**Observed behavior:**

```text
source_system = NULL
source_object = NULL
```

**Root cause:** Databricks notebook widget names differed from ADF base parameter names.

ADF used:

```text
source_system
source_object
```

The notebook initially used:

```text
source_systems
source_objects
```

**Resolution:** Standardized the notebook widgets, variable names and transformation logic to singular names matching the ADF parameters.

```python
source_system = dbutils.widgets.get("source_system")
source_object = dbutils.widgets.get("source_object")
```

**Lesson learned:** Parameter names must match exactly between ADF Notebook activity configuration and Databricks widgets.

## Issue 6 — Attempting to remove nonexistent Databricks widgets

**Error:**

```text
InputWidgetNotDefined:
No input widget named source_systems is defined
```

**Root cause:** Old notebook cleanup cells attempted to remove widgets that no longer existed.

**Resolution:** Deleted obsolete widget-removal cells and retained the five correctly named widget declarations.

**Lesson learned:** Remove temporary development and debugging code before orchestrated execution. Widget-removal operations should not be included unnecessarily in reusable processing notebooks.

## Issue 7 — Obsolete notebook variable reference

**Error:**

```text
NameError:
name 'source_systems' is not defined
```

**Root cause:** An old debugging cell referenced the previous plural variable name after parameter variables had been renamed.

**Resolution:** Removed the obsolete debugging cell and reviewed the notebook for inconsistent variable names.

**Lesson learned:** A successful Delta write does not guarantee that the notebook run will succeed. Later failing cells can cause ADF to mark the entire notebook activity as failed.

## Issue 8 — Incorrect column name in Bronze validation

**Problem:** A validation cell referenced an outdated metadata column name:

```python
"source_systems"
```

The DataFrame transformation created:

```python
"source_system"
```

**Resolution:** Corrected the validation code to use the actual persisted column names and added checks for row-count equality and required source parameters.

**Lesson learned:** Validation logic must use the same schema contract as the transformation.

## Issue 9 — ADF dynamic expression passed literally to Databricks

**Error:**

```text
java.net.URISyntaxException:
Illegal character in scheme name at index 0
```

**Observed incorrect notebook input:**

```text
@concat('abfss://',item().target_container,...)
```

**Root cause:** The ADF `landing_path` and `bronze_path` expressions were saved with leading newline characters before the `@concat` expressions.

Example problematic JSON:

```json
"landing_path": {
  "value": "\n@concat(...)",
  "type": "Expression"
}
```

Databricks consequently received an unevaluated expression string rather than a valid ADLS URI.

**Resolution:**

1. Opened the pipeline's Code view.
2. Inspected the `baseParameters` JSON.
3. Identified the leading `\n` characters.
4. Corrected both path expressions to start directly with `@concat`.
5. Saved and validated the pipeline.
6. Re-executed the MySQL `category` test successfully.

**Correct Landing expression:**

```text
@concat('abfss://',item().target_container,'@sthybridlakeprojectdev.dfs.core.windows.net/',item().target_folder,'/')
```

**Correct Bronze expression:**

```text
@concat('abfss://bronze@sthybridlakeprojectdev.dfs.core.windows.net/',item().target_folder,'/')
```

**Lesson learned:** Examine the serialized ADF JSON when a value behaves unexpectedly. Valid-looking expressions in the editor do not guarantee correct runtime parameter evaluation.

## Issue 10 — Clarifying source and target metadata across processing stages

**Problem:** The `target_container` and `target_folder` column names appeared misleading when reused in the Landing-to-Bronze pipeline.

**Explanation:**

During source ingestion:

```text
Original source -> ADLS Landing
```

Landing was the destination.

During Bronze processing:

```text
ADLS Landing -> ADLS Bronze
```

Landing becomes the source.

Therefore, the previously recorded `target_container` and `target_folder` values correctly identify the current Landing source location.

The Bronze destination is constructed using the Bronze container and the same relative folder structure.

**Resolution:** Preserved the existing metadata values and documented their stage-specific interpretation.

**Lesson learned:** Metadata column semantics should be explicitly defined. Future iterations may introduce distinct Landing and Bronze destination fields.

## Issue 11 — Cost-conscious Databricks development execution

**Problem:** Repeated new-job-cluster provisioning increased execution overhead and complicated debugging.

**Resolution:**

- Switched to existing All-Purpose single-node compute.
- Configured automatic termination after inactivity.
- Kept ADF ForEach sequential.
- Validated small objects before executing larger datasets.
- Manually terminated compute when not needed.

**Lesson learned:** Development compute configuration should be chosen based on workload, quota, availability and cost. All-Purpose clusters are suitable for interactive development but are not necessarily optimal for production scheduling.

## Final Resolution and Validation

After correcting the issues above, the metadata-driven Bronze pipeline executed successfully for all nine registered objects.

| Source system | Objects validated |
|---|---|
| SQL Server | transactions_2021, transactions_2022, transactions_2023, calendar |
| MySQL | product, category, subcategory |
| SFTP | channel.csv, promotion.csv |

The `calendar` validation confirmed 1,095 records in both Landing and Bronze.

The full nine-object execution was reported successful, with passing notebook validation checks.

### Outstanding engineering improvements

- Incremental load and rerun behavior.
- Automated operational audit tables.
- Retry policies and recovery testing.
- Comprehensive schema and persisted lineage validation.
- Secret-management and source-control hardening.
- Production scheduling and compute optimization.
- Automated CI/CD deployment verification.

These improvements remain outside the currently validated full-refresh Bronze implementation.



---

# Silver Layer — Troubleshooting

## 1. ADLS Silver Authentication Failure

Error:
AZURE_INVALID_CREDENTIALS_CONFIGURATION
Invalid configuration value detected for fs.azure.account.key

Observation:
- Bronze container access succeeded.
- Silver container access initially failed.
- The Silver container existed in Azure Storage.

Investigation:
Unity Catalog contained external locations for Landing and
Bronze, but no external location for Silver.

Resolution:
Created ext_adls_silver using the existing managed-identity
storage credential cred_adls_hybrid_lakehouse.

Result:
Silver storage access and Delta writes succeeded.

## 2. Unsupported SparkContext and JVM Access

Errors:
JVM_ATTRIBUTE_NOT_SUPPORTED

Cause:
Diagnostic code attempted to access spark.sparkContext
or spark._jsc in restricted Databricks compute environments.

Resolution:
Avoided direct JVM access and used supported storage
operations to verify accessibility.

## 3. Databricks Widget Defaults vs Current Values

Issue:
The Python widget definition continued to show channel,
even after the widget was changed to promotion.

Cause:
dbutils.widgets.text() defines a default when creating the
widget. Changing the current widget value does not rewrite
the Python source code.

Resolution:
Updated widget control values and reran the parameter-reading
cell to refresh the Python variables.

Production design:
ADF supplies notebook parameters dynamically.

## 4. UNRESOLVED_COLUMN — PromotionKey

Error:
PromotionKey cannot be resolved.

Cause:
source_object was set to promotion, but bronze_path still
pointed to the Channel Delta dataset.

Resolution:
Updated both input and output paths to sftp/promotion.

Prevention:
Validate that source_system, source_object, bronze_path
and silver_path refer to the same registered object.

## 5. Empty Parameter Validation

Error:
ValueError: Missing parameter: source_system

Cause:
The notebook widgets existed with empty current values.

Resolution:
Set appropriate widget values for manual testing.
Recreated widgets when necessary.

Production design:
ADF provides all five parameters.

## 6. Successful End-to-End Execution

ADF pl_bronze_to_silver completed successfully.

All nine registered objects were processed.

Persisted Bronze and Silver row counts matched for all objects.

Total: 2,802,285 records.

Outstanding improvements:
- Parameter/path consistency checks
- Automated transaction referential-integrity validation
- Quarantine handling and persisted quality metrics
- Incremental processing support


---

# Gold Layer — Troubleshooting

## 1. Gold ADLS Authentication Failure

Error:
Invalid configuration value detected for fs.azure.account.key

Cause:
Gold container existed but did not initially have a
Unity Catalog external location configured.

Resolution:
Created ext_adls_gold using the existing managed-identity
storage credential cred_adls_hybrid_lakehouse.

Result:
Gold Delta writes succeeded.

## 2. ADF Notebook Activity Validation Error

Errors:
- Parameter name can't be empty
- Parameter value can't be empty

Cause:
An empty Base parameters row was present in the ADF
Databricks Notebook activity.

Resolution:
Removed the empty parameter row.

The Gold notebook does not currently require Base parameters.

## 3. Gold Star Schema Validation

Validated the following relationships:

fact_sales -> dim_date
fact_sales -> dim_product
fact_sales -> dim_channel
fact_sales -> dim_promotion

All four relationships returned zero unmatched fact records.

Gold fact_sales row count: 2,798,589

Result:
GOLD STAR SCHEMA VALIDATION PASSED