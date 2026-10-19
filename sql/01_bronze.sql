-- ============================================================
-- BRONZE: load files as text, keep file name and row number
-- ============================================================
USE ROLE RA_ENGINEER; USE WAREHOUSE RA_WH; USE SCHEMA RA_DEMO.BRONZE;

CREATE OR REPLACE TABLE CRM_ACCOUNTS (account_id STRING, account_name STRING, contact_email STRING,
  _file STRING, _row NUMBER, _loaded_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE CRM_CONTRACTS (contract_id STRING, account_id STRING, product STRING,
  start_month STRING, end_month STRING, monthly_amount STRING,
  _file STRING, _row NUMBER, _loaded_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE ERP_INVOICES (invoice_id STRING, customer_account STRING, customer_name STRING,
  contract_ref STRING, invoice_date STRING, amount STRING, currency STRING,
  _file STRING, _row NUMBER, _loaded_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE BILLING_LINES (bill_id STRING, customer_name STRING, service_ref STRING,
  period STRING, billed_amount STRING,
  _file STRING, _row NUMBER, _loaded_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE ANSWER_KEY (exception_type STRING, contract_id STRING, period STRING, value_at_risk STRING,
  _file STRING, _row NUMBER, _loaded_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());

COPY INTO CRM_ACCOUNTS (account_id, account_name, contact_email, _file, _row)
  FROM (SELECT $1, $2, $3, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER FROM @RA_STAGE)
  FILES = ('crm_accounts.csv') FILE_FORMAT = (FORMAT_NAME = 'CSV_FF') ON_ERROR = ABORT_STATEMENT;
COPY INTO CRM_CONTRACTS (contract_id, account_id, product, start_month, end_month, monthly_amount, _file, _row)
  FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER FROM @RA_STAGE)
  FILES = ('crm_contracts.csv') FILE_FORMAT = (FORMAT_NAME = 'CSV_FF') ON_ERROR = ABORT_STATEMENT;
COPY INTO ERP_INVOICES (invoice_id, customer_account, customer_name, contract_ref, invoice_date, amount, currency, _file, _row)
  FROM (SELECT $1, $2, $3, $4, $5, $6, $7, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER FROM @RA_STAGE)
  FILES = ('erp_invoices.csv') FILE_FORMAT = (FORMAT_NAME = 'CSV_FF') ON_ERROR = ABORT_STATEMENT;
COPY INTO BILLING_LINES (bill_id, customer_name, service_ref, period, billed_amount, _file, _row)
  FROM (SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER FROM @RA_STAGE)
  FILES = ('billing_lines.csv') FILE_FORMAT = (FORMAT_NAME = 'CSV_FF') ON_ERROR = ABORT_STATEMENT;
COPY INTO ANSWER_KEY (exception_type, contract_id, period, value_at_risk, _file, _row)
  FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER FROM @RA_STAGE)
  FILES = ('answer_key.csv') FILE_FORMAT = (FORMAT_NAME = 'CSV_FF') ON_ERROR = ABORT_STATEMENT;

-- Row-count check against the file row counts (expected: 55, 70, 315, 308, 33)
SELECT 'crm_accounts' t, COUNT(*) n FROM CRM_ACCOUNTS UNION ALL
SELECT 'crm_contracts', COUNT(*) FROM CRM_CONTRACTS UNION ALL
SELECT 'erp_invoices', COUNT(*) FROM ERP_INVOICES UNION ALL
SELECT 'billing_lines', COUNT(*) FROM BILLING_LINES UNION ALL
SELECT 'answer_key', COUNT(*) FROM ANSWER_KEY;
