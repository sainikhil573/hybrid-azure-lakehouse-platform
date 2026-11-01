
# Gold Layer — Hybrid Azure Lakehouse Data Platform

## 1. Overview

The Gold Layer transforms validated Silver Delta datasets into
a dimensional data model for business intelligence and reporting.

Technologies:
- Azure Data Factory
- Azure Databricks
- PySpark
- Delta Lake
- Azure Data Lake Storage Gen2
- Power BI (downstream)

## 2. Architecture

SQL Server / MySQL / SFTP
          |
          v
     Bronze Delta
          |
          v
     Silver Delta
          |
          v
ADF: pl_silver_to_gold
          |
          v
Databricks: nb_silver_to_gold
          |
          v
     Gold Delta
          |
          v
       Power BI

Storage account: sthybridlakeprojectdev
Gold container: gold

## 3. Gold Dimensional Model

The Gold Layer implements a sales-oriented star schema.

Fact table:
- fact_sales

Dimensions:
- dim_date
- dim_product
- dim_channel
- dim_promotion

### Fact Grain

The fact_sales table preserves the row-level grain of the
original SQL Server transaction datasets.

The source does not expose a confirmed unique transaction ID.
No blind transaction deduplication is performed.

## 4. Gold Tables

| Table | Validated Records |
|---|---:|
| dim_date | 1,095 |
| dim_product | 2,517 |
| dim_channel | 4 |
| dim_promotion | 28 |
| fact_sales | 2,798,589 |

## 5. Dimension Transformations

### dim_date

Source: Silver sqlserver/calendar

Transformations:
- Generate integer DateKey using yyyyMMdd.
- Derive Year, Quarter, Month, MonthName and Day.
- Derive DayOfWeek and DayName.
- Create IsWeekend indicator.

### dim_product

Sources:
- Silver mysql/product
- Silver mysql/subcategory
- Silver mysql/category

Transformations:
- Join Product to Subcategory and Category.
- Include product, brand, manufacturer and classification attributes.
- Preserve all products through left joins.
- Validate ProductKey uniqueness.

### dim_channel

Source: Silver sftp/channel

Attributes:
- ChannelKey
- Channel

### dim_promotion

Source: Silver sftp/promotion

Attributes:
- PromotionKey
- PromotionName
- PromotionDescription
- DiscountPercent
- PromotionType
- PromotionCategory

DiscountPercent is stored as a fractional rate.
For example, 0.05 represents 5%.

## 6. Fact Sales

Sources:
- Silver transactions_2021
- Silver transactions_2022
- Silver transactions_2023

The three datasets are combined using unionByName().

Fact columns include:
- DateKey
- ProductKey
- ChannelKey
- PromotionKey
- UnitCost
- UnitPrice
- SalesQuantity
- ReturnQuantity
- ReturnAmount
- DiscountQuantity
- DiscountAmount
- TotalCost
- SalesAmount
- LoadID
- ingestion_timestamp
- source_system
- source_object

Financial amounts retain their original decimal precision.

SalesAmount is preserved as supplied by the source;
returns and discounts are not subtracted again.

## 7. Orchestration

ADF pipeline: pl_silver_to_gold

Databricks notebook: nb_silver_to_gold

Activity: nb_execute_silver_to_gold

The notebook creates dimensions, builds fact_sales,
and performs final relationship validation.

Processing strategy:
Full-refresh Delta overwrite.

## 8. Data Quality and Validation

Validation completed:
- Gold dimension key uniqueness
- Null-key checks
- Source-to-Gold record reconciliation
- Persisted fact_sales row-count verification
- Fact-to-dimension referential integrity

Results:

dim_date: 0 unmatched fact rows
dim_product: 0 unmatched fact rows
dim_channel: 0 unmatched fact rows
dim_promotion: 0 unmatched fact rows

Gold fact_sales records: 2,798,589

Final result:
GOLD STAR SCHEMA VALIDATION PASSED

## 9. Storage Security

Gold ADLS access uses a Unity Catalog external location.

External location:
ext_adls_gold

Existing storage credential:
cred_adls_hybrid_lakehouse

Authentication uses managed identity.

No plaintext storage credentials are stored in
the notebooks.

## 10. Current Limitations

- Full refresh rather than incremental MERGE.
- No confirmed unique transaction-level identifier.
- Financial business definitions require source-owner confirmation.
- Gold Delta data is stored by path; no registered serving tables
  or Power BI semantic model have been documented yet.
- Automated data-quality reporting can be extended.

## 11. Next Phase

Build Power BI reporting using the Gold dimensional model.

Planned reporting includes:
- Sales trends
- Product/category performance
- Channel sales
- Promotion analysis
- Sales quantities, returns and discounts
