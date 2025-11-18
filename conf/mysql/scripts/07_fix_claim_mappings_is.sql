-- ------------------------------------------------------------------------
-- Ensure critical claim mappings exist for the shared user store.
-- This resolves authentication flows that expect the http://wso2.org/claims
-- dialect to expose the identity/accountLocked claim.
-- ------------------------------------------------------------------------

USE WSO2_IS_SHARED_DB;
-- Fix claim mappings for APIM shared database

-- Create the WSO2 local claim dialect when it is missing.
INSERT INTO UM_DIALECT (UM_DIALECT_URI, UM_TENANT_ID)
SELECT 'http://wso2.org/claims', 0
WHERE NOT EXISTS (
    SELECT 1
    FROM UM_DIALECT
    WHERE UM_DIALECT_URI = 'http://wso2.org/claims'
      AND UM_TENANT_ID = 0
);

-- Ensure the accountLocked claim is mapped to a user store attribute.
UPDATE UM_CLAIM
SET UM_MAPPED_ATTRIBUTE = 'accountLock',
    UM_MAPPED_ATTRIBUTE_DOMAIN = 'PRIMARY',
    UM_SUPPORTED = 1,
    UM_REQUIRED = 0,
    UM_DISPLAY_TAG = 'Account Locked',
    UM_DESCRIPTION = 'Account Locked'
WHERE UM_CLAIM_URI = 'http://wso2.org/claims/identity/accountLocked'
  AND UM_TENANT_ID = 0
  AND (UM_MAPPED_ATTRIBUTE IS NULL OR UM_MAPPED_ATTRIBUTE = '');

-- Insert the accountLocked claim definition if it does not exist.
INSERT INTO UM_CLAIM (
    UM_DIALECT_ID,
    UM_CLAIM_URI,
    UM_DISPLAY_TAG,
    UM_DESCRIPTION,
    UM_MAPPED_ATTRIBUTE_DOMAIN,
    UM_MAPPED_ATTRIBUTE,
    UM_REG_EX,
    UM_SUPPORTED,
    UM_REQUIRED,
    UM_DISPLAY_ORDER,
    UM_CHECKED_ATTRIBUTE,
    UM_READ_ONLY,
    UM_TENANT_ID
)
SELECT
    d.UM_ID,
    'http://wso2.org/claims/identity/accountLocked',
    'Account Locked',
    'Account Locked',
    'PRIMARY',
    'accountLock',
    NULL,
    1,
    0,
    0,
    0,
    0,
    d.UM_TENANT_ID
FROM UM_DIALECT d
WHERE d.UM_DIALECT_URI = 'http://wso2.org/claims'
  AND d.UM_TENANT_ID = 0
  AND NOT EXISTS (
      SELECT 1
      FROM UM_CLAIM c
      WHERE c.UM_CLAIM_URI = 'http://wso2.org/claims/identity/accountLocked'
        AND c.UM_TENANT_ID = d.UM_TENANT_ID
  );
