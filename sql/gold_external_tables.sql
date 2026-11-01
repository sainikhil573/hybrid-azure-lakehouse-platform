
-- Gold external Delta tables for Power BI
-- Requires an existing Unity Catalog schema and
-- appropriate privileges on the Gold external location.

CREATE SCHEMA IF NOT EXISTS
dbw_hybrid_lakehouse_dev.gold_reporting;

CREATE TABLE IF NOT EXISTS
dbw_hybrid_lakehouse_dev.gold_reporting.dim_date
USING DELTA
LOCATION 'abfss://gold@sthybridlakeprojectdev.dfs.core.windows.net/dim_date/';

CREATE TABLE IF NOT EXISTS
dbw_hybrid_lakehouse_dev.gold_reporting.dim_product
USING DELTA
LOCATION 'abfss://gold@sthybridlakeprojectdev.dfs.core.windows.net/dim_product/';

CREATE TABLE IF NOT EXISTS
dbw_hybrid_lakehouse_dev.gold_reporting.dim_channel
USING DELTA
LOCATION 'abfss://gold@sthybridlakeprojectdev.dfs.core.windows.net/dim_channel/';

CREATE TABLE IF NOT EXISTS
dbw_hybrid_lakehouse_dev.gold_reporting.dim_promotion
USING DELTA
LOCATION 'abfss://gold@sthybridlakeprojectdev.dfs.core.windows.net/dim_promotion/';

CREATE TABLE IF NOT EXISTS
dbw_hybrid_lakehouse_dev.gold_reporting.fact_sales
USING DELTA
LOCATION 'abfss://gold@sthybridlakeprojectdev.dfs.core.windows.net/fact_sales/';
