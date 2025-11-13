-- Migration script to add missing REVISION_UUID column to AM_API_URL_MAPPING table
-- This fixes the "Unknown column 'REVISION_UUID' in 'where clause'" error
-- when deploying APIs in WSO2 API Manager 4.6.0

USE WSO2AM_DB;

-- Check if column exists before adding (idempotent)
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'WSO2AM_DB'
  AND TABLE_NAME = 'AM_API_URL_MAPPING'
  AND COLUMN_NAME = 'REVISION_UUID';

-- Add column if it doesn't exist
SET @query = IF(
    @col_exists = 0,
    'ALTER TABLE AM_API_URL_MAPPING ADD COLUMN REVISION_UUID VARCHAR(255) AFTER MEDIATION_SCRIPT',
    'SELECT "Column REVISION_UUID already exists in AM_API_URL_MAPPING" AS message'
);

PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Verify the column was added
SELECT
    CASE
        WHEN COUNT(*) > 0 THEN 'SUCCESS: REVISION_UUID column exists in AM_API_URL_MAPPING'
        ELSE 'ERROR: REVISION_UUID column missing in AM_API_URL_MAPPING'
    END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'WSO2AM_DB'
  AND TABLE_NAME = 'AM_API_URL_MAPPING'
  AND COLUMN_NAME = 'REVISION_UUID';
