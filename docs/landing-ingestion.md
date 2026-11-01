# Landing Ingestion Architecture

## Overview

The landing ingestion layer extracts data from three simulated on-premises source systems and loads the source data into Azure Data Lake Storage Gen2 using Azure Data Factory.

The implemented flow is:

```text
SQL Server
MySQL
SFTP
   ↓
Self-Hosted Integration Runtime
   ↓
Azure Data Factory
   ↓
ADLS Gen2 - landing container
```

The ingestion framework is metadata-driven and uses reusable parameterized datasets instead of separate hard-coded pipelines for every source object.

---

## Source Systems

### SQL Server

Database:

`bhaskar_contoso_db`

Source objects:

- `dbo.transactions_2021`
- `dbo.transactions_2022`
- `dbo.transactions_2023`
- `dbo.calendar`

ADF linked service:

`ls-sqlserver-onprem`

Integration Runtime:

`shir-hybrid-lakehouse-dev`

Target folders:

```text
landing/sqlserver/transactions_2021/
landing/sqlserver/transactions_2022/
landing/sqlserver/transactions_2023/
landing/sqlserver/calendar/
```

Large SQL Server transaction tables use dynamic-range partitioning during extraction to improve stability and performance.

---

## MySQL

Database:

`bhaskar_retail_db`

Source objects:

- `product`
- `category`
- `subcategory`

ADF linked service:

`ls-mysql-onprem`

Integration Runtime:

`shir-hybrid-lakehouse-dev`

Target folders:

```text
landing/mysql/product/
landing/mysql/category/
landing/mysql/subcategory/
```

---

## SFTP

The SFTP source is hosted locally using Windows OpenSSH Server.

Source files:

- `channel.csv`
- `promotion.csv`

ADF linked service:

`ls-sftp-onprem`

Integration Runtime:

`shir-hybrid-lakehouse-dev`

Target folders:

```text
landing/sftp/channel/
landing/sftp/promotion/
```

---

## Metadata-Driven Ingestion

The ingestion framework uses two SQL Server metadata tables:

- `metadata_schema.source_connection`
- `metadata_schema.ingestion_object`

The `source_connection` table stores source-system connection metadata.

The `ingestion_object` table stores object-level ingestion configuration such as:

- source object
- connection ID
- source schema
- object type
- load type
- watermark column
- target container
- target folder
- file format
- active status

The pipelines filter metadata using `connection_id`.

Example:

```text
connection_id = 1 → SQL Server
connection_id = 2 → MySQL
connection_id = 3 → SFTP
```

This allows one centralized metadata table to drive ingestion for multiple source systems.

---

## Pipeline Pattern

Each source pipeline follows the same orchestration pattern:

```text
Lookup
   ↓
ForEach
   ↓
Copy Data
```

### Lookup

The Lookup activity reads active ingestion objects from:

`metadata_schema.ingestion_object`

Example:

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
WHERE connection_id = 1
  AND is_active = 1;
```

### ForEach

The ForEach activity iterates over the metadata returned by Lookup.

Example expression:

```text
@activity('Lookup_SQLServer_Objects').output.value
```

### Copy Data

The Copy activity receives source and target configuration dynamically.

Example SQL Server source parameters:

```text
schema_name = @item().source_schema
table_name  = @item().source_object
```

Example ADLS sink parameters:

```text
container_name = @item().target_container
folder_path    = @item().target_folder
```

---

## Parameterized Datasets

### SQL Server

Dataset:

`ds_sqlserver_source`

Parameters:

- `schema_name`
- `table_name`

### MySQL

Dataset:

`ds_mysql_source`

Parameter:

- `table_name`

### SFTP

Dataset:

`ds_sftp_source`

Parameter:

- `file_name`

### ADLS Gen2

Dataset:

`ds_adls_parquet_sink`

Parameters:

- `container_name`
- `folder_path`

This approach avoids creating separate datasets for every table or file.

---

## Landing Layer Design

The landing layer stores source data with minimal transformation.

Current structure:

```text
landing/
├── sqlserver/
│   ├── transactions_2021/
│   ├── transactions_2022/
│   ├── transactions_2023/
│   └── calendar/
│
├── mysql/
│   ├── product/
│   ├── category/
│   └── subcategory/
│
└── sftp/
    ├── channel/
    └── promotion/
```

The purpose of the landing layer is to preserve extracted source data before Databricks processing begins.

---

## Monitoring

ADF Monitor is used to track:

- pipeline status
- activity status
- run duration
- rows read
- rows copied
- files written
- error messages
- Integration Runtime used

Successful and failed pipeline runs were validated during implementation.

---

## Current Status

The landing ingestion layer has been successfully implemented for:

- SQL Server
- MySQL
- SFTP

All three sources have been validated through the Self-Hosted Integration Runtime and successfully loaded into ADLS Gen2.

The next processing stage is:

```text
ADLS Landing
    ↓
Azure Databricks
    ↓
Bronze Delta Layer
```