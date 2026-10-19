-- ============================================================
-- GOLD: golden thread per contract-month, and the exception dataset
-- ============================================================
USE ROLE RA_ENGINEER; USE WAREHOUSE RA_WH; USE SCHEMA RA_DEMO.GOLD;

-- Every month a contract should have been invoiced and billed
CREATE OR REPLACE TABLE GOLD.EXPECTED AS
SELECT c.contract_id, c.account_id, m.period, c.monthly_amount
FROM SILVER.CONTRACTS c JOIN SILVER.MONTHS m ON m.period BETWEEN c.start_month AND c.end_month;

-- Golden thread: contracted vs invoiced vs billed, one row per contract-month
CREATE OR REPLACE TABLE GOLD.GOLDEN_THREAD AS
SELECT e.contract_id, e.account_id, e.period, e.monthly_amount AS contracted,
       inv.n_invoices, inv.invoiced, inv.invoice_ids,
       bil.billed, bil.bill_ids
FROM GOLD.EXPECTED e
LEFT JOIN (SELECT contract_id, period, COUNT(*) AS n_invoices, SUM(amount) AS invoiced,
                  LISTAGG(invoice_id, ',') WITHIN GROUP (ORDER BY invoice_id) AS invoice_ids
           FROM SILVER.INVOICE_CONTRACT WHERE contract_id IS NOT NULL GROUP BY contract_id, period) inv
  ON inv.contract_id = e.contract_id AND inv.period = e.period
LEFT JOIN (SELECT service_ref AS contract_id, period, SUM(billed_amount) AS billed,
                  LISTAGG(bill_id, ',') WITHIN GROUP (ORDER BY bill_id) AS bill_ids
           FROM SILVER.BILLING GROUP BY service_ref, period) bil
  ON bil.contract_id = e.contract_id AND bil.period = e.period;

-- Exceptions: each row traceable to the contract, period and source records
CREATE OR REPLACE TABLE GOLD.EXCEPTIONS AS
SELECT 'MISSING_INVOICE' AS exception_type, contract_id, account_id, period,
       contracted AS value_at_risk, 'billed: ' || COALESCE(bill_ids, 'none') AS evidence
FROM GOLD.GOLDEN_THREAD WHERE n_invoices IS NULL
UNION ALL
SELECT 'NOT_BILLED', contract_id, account_id, period, contracted, 'invoiced: ' || COALESCE(invoice_ids, 'none')
FROM GOLD.GOLDEN_THREAD WHERE billed IS NULL
UNION ALL
SELECT 'UNDER_BILLED', contract_id, account_id, period, contracted - billed, 'bills: ' || bill_ids
FROM GOLD.GOLDEN_THREAD WHERE billed < contracted
UNION ALL
SELECT 'DUPLICATE_INVOICE', contract_id, account_id, period, invoiced - contracted, 'invoices: ' || invoice_ids
FROM GOLD.GOLDEN_THREAD WHERE n_invoices > 1
UNION ALL
SELECT 'BILLED_AFTER_END', b.service_ref, c.account_id, b.period, 0, 'bill: ' || b.bill_id || ', term ends ' || c.end_month
FROM SILVER.BILLING b JOIN SILVER.CONTRACTS c ON c.contract_id = b.service_ref
WHERE b.period > c.end_month
UNION ALL
SELECT 'UNLINKED_INVOICE', NULL, account_id, period, amount, 'invoice: ' || invoice_id || ' (' || link_method || ')'
FROM SILVER.INVOICE_CONTRACT WHERE contract_id IS NULL;

-- Summary for the dashboard
CREATE OR REPLACE VIEW GOLD.EXCEPTION_SUMMARY AS
SELECT exception_type, COUNT(*) AS cases, SUM(value_at_risk) AS value_at_risk
FROM GOLD.EXCEPTIONS GROUP BY exception_type;
