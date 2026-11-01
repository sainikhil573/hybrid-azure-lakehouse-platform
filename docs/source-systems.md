# On-Premises Source Systems

## SQL Server

Database: `bhaskar_contoso_db`

Source tables:

- `dbo.transactions_2021` — 1,076,173 rows
- `dbo.transactions_2022` — 915,237 rows
- `dbo.transactions_2023` — 807,179 rows
- `dbo.calendar` — 1,095 rows

A dedicated read-only account, `adf_reader`, is used for ingestion access.

## Metadata Framework

Two metadata tables were created:

- `metadata_schema.source_connection`
- `metadata_schema.ingestion_object`

The connection table stores source-system configuration.

The ingestion-object table stores object-level ingestion configuration such as source object, load type, target folder, and file format.

## MySQL

Database: `bhaskar_retail_db`

Source tables:

- `product`
- `category`
- `subcategory`

A dedicated read-only `adf_reader` account is used for ingestion access.

## SFTP

A local Windows OpenSSH Server is used to simulate an on-premises SFTP source.

Source files:

- `channel.csv`
- `promotion.csv`

Source folder:

`C:\SFTP\retail`

A dedicated Windows account named `sftp_reader` is used for SFTP access.

## Security

Passwords and credentials are not stored in source control.

<<<<<<< HEAD
Repository scripts contain placeholders only. Production-style credentials will be managed securely during Azure integration.


## Self-Hosted Integration Runtime

A Self-Hosted Integration Runtime was installed and configured on the local Windows machine to provide secure connectivity between Azure Data Factory and the simulated on-premises source systems.

Integration Runtime:

- Name: `shir-hybrid-lakehouse-dev`
- Type: Self-Hosted Integration Runtime
- Status: Running
- Host environment: Local Windows machine
- Purpose: Connect Azure Data Factory to local SQL Server, MySQL, and SFTP sources

## Azure Data Factory Linked Services

The following linked services were configured and validated through the Self-Hosted Integration Runtime.

### SQL Server

Linked service:

`ls-sqlserver-onprem`

Configuration:

- Source: Local SQL Server
- Database: `bhaskar_contoso_db`
- Authentication: Dedicated read-only `adf_reader` account
- Integration Runtime: `shir-hybrid-lakehouse-dev`
- Connection validation: Successful

### MySQL

Linked service:

`ls-mysql-onprem`

Configuration:

- Source: Local MySQL 8.0
- Database: `bhaskar_retail_db`
- Port: `3306`
- Authentication: Dedicated read-only `adf_reader` account
- Integration Runtime: `shir-hybrid-lakehouse-dev`
- Connection validation: Successful

### SFTP

Linked service:

`ls-sftp-onprem`

Configuration:

- Source: Local Windows OpenSSH SFTP server
- Host: `localhost`
- Port: `22`
- Authentication: Dedicated `sftp_reader` account
- Source path: `C:\SFTP\retail`
- Source files:
  - `channel.csv`
  - `promotion.csv`
- Integration Runtime: `shir-hybrid-lakehouse-dev`
- Connection validation: Successful

SSH host-key validation is disabled only for this local development environment. A production implementation should validate the SFTP server host key.

## Security Approach

Dedicated service accounts are used instead of administrator accounts:

- SQL Server: `adf_reader`
- MySQL: `adf_reader`
- SFTP: `sftp_reader`

Passwords and authentication secrets are not stored in Git or project documentation.

The repository contains only configuration documentation and credential placeholders.

## Hybrid Connectivity Validation

Azure Data Factory successfully established connectivity to all three simulated on-premises source systems through the Self-Hosted Integration Runtime:

- SQL Server — validated
- MySQL — validated
- SFTP — validated

This completes the hybrid source connectivity foundation required for the Azure landing ingestion layer.
=======
Repository scripts contain placeholders only. Production-style credentials will be managed securely during Azure integration.
>>>>>>> origin/main
