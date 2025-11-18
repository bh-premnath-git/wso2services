-- Create separate databases for WSO2 IS 7.1.0 and APIM 4.6.0
-- This separates IS and APIM for cleaner architecture

-- Identity Server databases
CREATE DATABASE IF NOT EXISTS WSO2_IS_SHARED_DB;
CREATE DATABASE IF NOT EXISTS WSO2_IS_DB;

-- API Manager databases  
CREATE DATABASE IF NOT EXISTS WSO2AM_SHARED_DB;
CREATE DATABASE IF NOT EXISTS WSO2AM_DB;

-- Create database user
CREATE USER IF NOT EXISTS 'wso2carbon'@'%' IDENTIFIED BY 'wso2carbon';

-- Grant permissions for IS databases
GRANT ALL PRIVILEGES ON WSO2_IS_SHARED_DB.* TO 'wso2carbon'@'%';
GRANT ALL PRIVILEGES ON WSO2_IS_DB.* TO 'wso2carbon'@'%';

-- Grant permissions for APIM databases
GRANT ALL PRIVILEGES ON WSO2AM_SHARED_DB.* TO 'wso2carbon'@'%';
GRANT ALL PRIVILEGES ON WSO2AM_DB.* TO 'wso2carbon'@'%';

FLUSH PRIVILEGES;
