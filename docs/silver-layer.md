
# Silver Layer — Hybrid Azure Lakehouse Data Platform

## 1. Overview

The Silver Layer transforms source-preserving Bronze Delta datasets
into standardized, validated Delta datasets using Azure Databricks
and PySpark.

The implementation supports nine objects from three source systems:
- On-premises SQL Server
- MySQL
- SFTP

Azure Data Factory (ADF) orchestrates the transformations using
existing ingestion metadata and a parameterized Databricks notebook.

## 2. Architecture

SQL Server / MySQL / SFTP
    |
    v
ADLS Gen2 — Bronze Delta
    |
    v
ADF: pl_bronze_to_silver
    |
    +-- Lookup ingestion metadata
    |
    +-- Sequential ForEach
            |
            v
       Databricks:
       nb_bronze_to_silver_parameterized
            |
            +-- transform_silver()
            +-- validate_silver()
            +-- Delta write
            |
            v
ADLS Gen2 — Silver Delta
            |
            v
Gold Layer (Next Phase)

Storage account: sthybridlakeprojectdev

Bronze container: bronze
Silver container: silver

## 3. Source Objects

| Source | Object | Validated Rows |
|---|---|---:|
| SQL Server | transactions_2021 | 1,076,173 |
| SQL Server | transactions_2022 | 915,237 |
| SQL Server | transactions_2023 | 807,179 |
| SQL Server | calendar | 1,095 |
| MySQL | product | 2,517 |
| MySQL | category | 8 |
| MySQL | subcategory | 44 |
| SFTP | channel | 4 |
| SFTP | promotion | 28 |
| **Total** | **9 objects** | **2,802,285** |

## 4. Silver Transformation Rules

### SQL Server — Transactions

- Parse DateID using MMddyyyy.
- Create a typed TransactionDate column.
- Validate mandatory product, channel, quantity, amount and date fields.
- Reject negative SalesQuantity through validation failure.
- Preserve Decimal(19,4) monetary precision.
- Preserve all transaction rows without blind deduplication.

The source does not provide an obvious transaction-level
business identifier.

### SQL Server — Calendar

- Preserve the Date column.
- Derive Year, Month, Day, Quarter and DayOfWeek.
- Validate non-null and unique dates.
- Spark DayOfWeek uses Sunday = 1.

### MySQL — Product

- Trim product and classification text attributes.
- Validate mandatory ProductKey and ProductName.
- Validate ProductKey uniqueness.
- Validate non-null ProductSubcategoryKey references against
  the Silver Subcategory dataset.

### MySQL — Category

- Trim category label and name.
- Validate ProductCategoryKey uniqueness.
- Validate mandatory category fields.

### MySQL — Subcategory

- Trim subcategory label and name.
- Validate ProductSubcategoryKey uniqueness.
- Validate parent ProductCategoryKey references against
  the Silver Category dataset.

### SFTP — Channel

- Cast ChannelKey from String to Integer.
- Trim Channel text.
- Validate mandatory fields and unique ChannelKey.

### SFTP — Promotion

- Cast PromotionKey from String to Integer.
- Cast DiscountPercent to Decimal(5,4).
- Trim promotion text fields.
- Validate PromotionKey uniqueness.
- Require DiscountPercent between 0 and 1.

DiscountPercent is represented as a fractional rate.
For example, 0.05 represents 5%.

## 5. Parameterized Databricks Notebook

Notebook:
nb_bronze_to_silver_parameterized

The notebook contains four primary logical sections:

1. Parameter widgets
2. transform_silver() transformation dispatcher
3. validate_silver() data-quality checks
4. Parameterized execution, validation and Delta write

Parameters:

| Parameter | Purpose |
|---|---|
| source_system | Identifies the originating system |
| source_object | Selects the transformation rules |
| bronze_path | Bronze Delta input path |
| silver_path | Silver Delta output path |
| load_id | Pipeline execution identifier |

The notebook uses source_object to select source-specific
transformations rather than maintaining nine separate notebooks.

The current Delta write strategy is overwrite/full refresh.

Existing Bronze lineage columns are retained:
- LoadID
- ingestion_timestamp
- source_system
- source_object

The load_id execution parameter is accepted and logged by the
notebook but is not currently added as a separate persisted
Silver execution identifier.

## 6. ADF Orchestration

Pipeline:
pl_bronze_to_silver

Main activities:
1. lkp_silver_ingestion_metadata
2. fe_process_silver_objects
3. nb_execute_bronze_to_silver

The Lookup queries metadata_schema.ingestion_object
for active registered source objects.

ForEach executes sequentially to respect dependencies,
including:

Category -> Subcategory -> Product

ADF dynamically supplies notebook parameters for each object.

Expressions generate Bronze and Silver paths using
the registered target_folder values.

## 7. Security and Storage Access

Azure Databricks accesses ADLS Gen2 through Unity Catalog
external locations and managed-identity storage credentials.

Existing storage credential:
cred_adls_hybrid_lakehouse

Silver external location:
ext_adls_silver

No storage account keys or plaintext credentials should be
committed to source control.

## 8. Validation Results

The ADF pipeline completed successfully.

All nine Silver Delta locations were independently read
after execution.

Bronze and Silver counts matched for every object.

Total validated rows: 2,802,285

The following were also verified during development:
- Source-specific transformation logic
- Required-field checks
- Duplicate business-key checks for dimensions
- Category/Subcategory/Product parent relationships
- Transaction key relationships against Product,
  Channel, Promotion and Calendar

A separate transaction referential-integrity check found:
- 0 unmatched ProductKey values
- 0 unmatched ChannelKey values
- 0 unmatched PromotionKey values
- 0 unmatched TransactionDate values
- 0 null transaction keys for these relationships

## 9. Current Limitations

- The pipeline uses full overwrite, not incremental MERGE or CDC.
- Invalid-record handling fails the job rather than quarantining rows.
- Automated transaction-to-dimension referential checks are
  not yet integrated into the reusable validator.
- Full data-quality metrics and audit history are not yet persisted.
- Transaction-level uniqueness cannot be reliably enforced
  without an appropriate transaction identifier.
- Notebook parameter paths are supplied by ADF; source-object
  and path consistency should be explicitly validated to
  prevent incorrect reads or overwrites.
- Data-quality validation can be extended with additional
  financial, range and relationship checks.

## 10. Next Phase

Implement Gold dimensional modeling, including:

- Fact Sales
- Date Dimension
- Product Dimension
- Channel Dimension
- Promotion Dimension

Serve curated Gold datasets for Power BI reporting.
