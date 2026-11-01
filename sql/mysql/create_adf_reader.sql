CREATE USER 'adf_reader'@'localhost'
IDENTIFIED BY '<PASSWORD_FROM_SECURE_STORE>';

GRANT SELECT
ON bhaskar_retail_db.*
TO 'adf_reader'@'localhost';

FLUSH PRIVILEGES;