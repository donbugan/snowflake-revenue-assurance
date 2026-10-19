-- ============================================================
-- GOVERNANCE: masking, analyst access, Time Travel
-- ============================================================
USE ROLE ACCOUNTADMIN; USE WAREHOUSE RA_WH; USE SCHEMA RA_DEMO.SILVER;

-- Dynamic masking: only RA_ENGINEER (or above) sees contact emails
CREATE OR REPLACE MASKING POLICY EMAIL_MASK AS (v STRING) RETURNS STRING ->
  CASE WHEN IS_ROLE_IN_SESSION('RA_ENGINEER') THEN v
       ELSE REGEXP_REPLACE(v, '^[^@]+', '*****') END;
ALTER TABLE SILVER.ACCOUNTS MODIFY COLUMN contact_email SET MASKING POLICY EMAIL_MASK;

-- Expose accounts to analysts through GOLD, masked
CREATE OR REPLACE VIEW GOLD.ACCOUNTS_V AS SELECT account_id, account_name, contact_email FROM SILVER.ACCOUNTS;
GRANT SELECT ON VIEW GOLD.ACCOUNTS_V TO ROLE RA_ANALYST;

USE ROLE RA_ENGINEER; SELECT * FROM GOLD.ACCOUNTS_V LIMIT 3;          -- clear
USE ROLE RA_ANALYST;  SELECT * FROM GOLD.ACCOUNTS_V LIMIT 3;          -- masked
USE ROLE RA_ANALYST;  SELECT * FROM SILVER.INVOICES LIMIT 1;          -- should fail: no access to SILVER

-- Time Travel: delete by mistake, then recover
USE ROLE RA_ENGINEER;
DELETE FROM GOLD.EXCEPTIONS WHERE exception_type = 'NOT_BILLED';
SET del_id = LAST_QUERY_ID();                                          -- remember the bad statement
SELECT COUNT(*) FROM GOLD.EXCEPTIONS;                                  -- fewer rows
INSERT INTO GOLD.EXCEPTIONS
  SELECT * FROM GOLD.EXCEPTIONS BEFORE(STATEMENT => $del_id) WHERE exception_type = 'NOT_BILLED';
SELECT exception_type, COUNT(*) FROM GOLD.EXCEPTIONS GROUP BY 1;       -- restored

-- Cost check
SHOW RESOURCE MONITORS;
