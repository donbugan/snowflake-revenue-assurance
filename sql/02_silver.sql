-- ============================================================
-- SILVER: typed, cleaned, with normalised customer names
-- ============================================================
USE ROLE RA_ENGINEER; USE WAREHOUSE RA_WH; USE SCHEMA RA_DEMO.SILVER;

-- Strip punctuation, case and legal-form words so "The Karoo Foods (Pty) Ltd" == "KAROO FOODS"
CREATE OR REPLACE FUNCTION NORM_NAME(n STRING) RETURNS STRING AS
$$
  TRIM(REGEXP_REPLACE(
    REGEXP_REPLACE(REGEXP_REPLACE(
      ' ' || REGEXP_REPLACE(UPPER(n), '[^A-Z0-9 ]', '') || ' ',
      ' (THE|PTY|LTD|PROPRIETARY|LIMITED) ', ' '),
      ' (THE|PTY|LTD|PROPRIETARY|LIMITED) ', ' '),
    ' +', ' '))
$$;

CREATE OR REPLACE TABLE SILVER.MONTHS AS
SELECT column1 AS period FROM VALUES ('2026-04'), ('2026-05'), ('2026-06'), ('2026-07'), ('2026-08'), ('2026-09');

CREATE OR REPLACE TABLE SILVER.ACCOUNTS AS
SELECT account_id, account_name, SILVER.NORM_NAME(account_name) AS name_norm, contact_email, _file, _row
FROM BRONZE.CRM_ACCOUNTS;

CREATE OR REPLACE TABLE SILVER.CONTRACTS AS
SELECT contract_id, account_id, product, start_month, end_month,
       TRY_TO_NUMBER(monthly_amount, 12, 2) AS monthly_amount, _file, _row
FROM BRONZE.CRM_CONTRACTS;

CREATE OR REPLACE TABLE SILVER.INVOICES AS
SELECT invoice_id, customer_account, customer_name, SILVER.NORM_NAME(customer_name) AS name_norm,
       NULLIF(TRIM(contract_ref), '') AS contract_ref,
       TRY_TO_DATE(invoice_date) AS invoice_date,
       TO_CHAR(TRY_TO_DATE(invoice_date), 'YYYY-MM') AS period,
       TRY_TO_NUMBER(amount, 12, 2) AS amount, currency, _file, _row
FROM BRONZE.ERP_INVOICES;

CREATE OR REPLACE TABLE SILVER.BILLING AS
SELECT bill_id, customer_name, SILVER.NORM_NAME(customer_name) AS name_norm, service_ref, period,
       TRY_TO_NUMBER(billed_amount, 12, 2) AS billed_amount, _file, _row
FROM BRONZE.BILLING_LINES;

-- Rows that failed type conversion, kept for traceability rather than silently dropped
CREATE OR REPLACE TABLE SILVER.REJECTS AS
SELECT 'crm_contracts' AS source, _file, _row, 'monthly_amount not numeric' AS reason FROM SILVER.CONTRACTS WHERE monthly_amount IS NULL
UNION ALL SELECT 'erp_invoices', _file, _row, 'invoice_date or amount invalid' FROM SILVER.INVOICES WHERE invoice_date IS NULL OR amount IS NULL
UNION ALL SELECT 'billing_lines', _file, _row, 'billed_amount not numeric' FROM SILVER.BILLING WHERE billed_amount IS NULL;
