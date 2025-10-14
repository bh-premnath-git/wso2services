-- Create databases for WSO2 API Manager
CREATE DATABASE apim_db;
CREATE DATABASE shared_db;

-- Create user for WSO2
CREATE USER wso2carbon WITH PASSWORD 'wso2carbon';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE apim_db TO wso2carbon;
GRANT ALL PRIVILEGES ON DATABASE shared_db TO wso2carbon;

-- Connect to apim_db and grant schema privileges
\c apim_db
GRANT ALL ON SCHEMA public TO wso2carbon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO wso2carbon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO wso2carbon;

-- Connect to shared_db and grant schema privileges
\c shared_db
GRANT ALL ON SCHEMA public TO wso2carbon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO wso2carbon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO wso2carbon;
