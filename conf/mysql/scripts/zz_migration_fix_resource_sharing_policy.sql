-- Migration script to add missing UNIQUE constraint to UM_RESOURCE_SHARING_POLICY
-- This fixes the "Failed to delete resource sharing policy by type and ID" error

USE WSO2_IDENTITY_DB;

-- First, remove any duplicate entries that might exist
-- Keep only the most recent policy for each (resource_type, resource_id, policy_holding_org) combination
DELETE t1 FROM UM_RESOURCE_SHARING_POLICY t1
INNER JOIN UM_RESOURCE_SHARING_POLICY t2
WHERE
    t1.UM_ID < t2.UM_ID
    AND t1.UM_RESOURCE_TYPE = t2.UM_RESOURCE_TYPE
    AND t1.UM_RESOURCE_ID = t2.UM_RESOURCE_ID
    AND t1.UM_POLICY_HOLDING_ORG_ID = t2.UM_POLICY_HOLDING_ORG_ID;

-- Add the UNIQUE constraint to prevent future duplicates
ALTER TABLE UM_RESOURCE_SHARING_POLICY
ADD CONSTRAINT UQ_RESOURCE_POLICY UNIQUE (UM_RESOURCE_TYPE, UM_RESOURCE_ID, UM_POLICY_HOLDING_ORG_ID);
