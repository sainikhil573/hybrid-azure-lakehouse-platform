USE bhaskar_contoso_db;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'metadata_schema'
)
BEGIN
    EXEC('CREATE SCHEMA metadata_schema');
END;
GO

CREATE TABLE metadata_schema.source_connection
(
    connection_id        INT IDENTITY(1,1) PRIMARY KEY,
    source_name          VARCHAR(50) NOT NULL,
    source_type          VARCHAR(30) NOT NULL,
    host_name            VARCHAR(100) NOT NULL,
    port                 INT NULL,
    database_name        VARCHAR(100) NULL,
    user_name            VARCHAR(100) NULL,
    secret_name          VARCHAR(100) NULL,
    is_active            BIT NOT NULL DEFAULT 1,
    created_at           DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE metadata_schema.ingestion_object
(
    ingestion_id         INT IDENTITY(1,1) PRIMARY KEY,
    connection_id        INT NOT NULL,
    source_schema        VARCHAR(100) NULL,
    source_object        VARCHAR(150) NOT NULL,
    object_type          VARCHAR(30) NOT NULL,
    load_type            VARCHAR(30) NOT NULL,
    watermark_column     VARCHAR(100) NULL,
    target_container     VARCHAR(100) NOT NULL,
    target_folder        VARCHAR(200) NOT NULL,
    file_format          VARCHAR(30) NOT NULL,
    is_active            BIT NOT NULL DEFAULT 1,
    created_at           DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT FK_ingestion_object_connection
        FOREIGN KEY (connection_id)
        REFERENCES metadata_schema.source_connection(connection_id)
);
GO