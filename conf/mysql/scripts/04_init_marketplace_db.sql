-- Create marketplace database
CREATE DATABASE IF NOT EXISTS marketplace_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Grant permissions
GRANT ALL PRIVILEGES ON marketplace_db.* TO 'root'@'%';
FLUSH PRIVILEGES;

-- Verify database creation
SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'marketplace_db';
