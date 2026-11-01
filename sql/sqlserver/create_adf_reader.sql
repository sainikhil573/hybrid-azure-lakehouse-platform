USE master;
GO

CREATE LOGIN adf_reader
WITH PASSWORD = '<PASSWORD_FROM_SECURE_STORE>';
GO

USE bhaskar_contoso_db;
GO

CREATE USER adf_reader FOR LOGIN adf_reader;
GO

ALTER ROLE db_datareader ADD MEMBER adf_reader;
GO