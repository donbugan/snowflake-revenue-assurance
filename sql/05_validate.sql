-- ============================================================
-- VALIDATION: completeness, match quality, and results vs the answer key
-- ============================================================
USE ROLE RA_ENGINEER; USE WAREHOUSE RA_WH; USE SCHEMA RA_DEMO.GOLD;

-- 1. Completeness: every bronze row is in silver (rejects are counted, not lost)
SELECT 'crm_contracts' AS source, (SELECT COUNT(*) FROM BRONZE.CRM_CONTRACTS) AS bronze, (SELECT COUNT(*) FROM SILVER.CONTRACTS) AS silver UNION ALL
SELECT 'erp_invoices', (SELECT COUNT(*) FROM BRONZE.ERP_INVOICES), (SELECT COUNT(*) FROM SILVER.INVOICES) UNION ALL
SELECT 'billing_lines', (SELECT COUNT(*) FROM BRONZE.BILLING_LINES), (SELECT COUNT(*) FROM SILVER.BILLING);
SELECT source, COUNT(*) AS rejected FROM SILVER.REJECTS GROUP BY source;

-- 2. Name matching quality
SELECT source, match_method, COUNT(*) AS names FROM SILVER.NAME_MATCHES GROUP BY source, match_method ORDER BY 1, 2;
SELECT link_method, COUNT(*) AS invoices FROM SILVER.INVOICE_CONTRACT GROUP BY link_method ORDER BY 1;

-- 3. Control: billing names should resolve to the same account as the contract they bill
SELECT COUNT(*) AS billing_name_conflicts
FROM SILVER.BILLING b
JOIN SILVER.NAME_MATCHES m ON m.source = 'BILLING' AND m.raw_name = b.customer_name AND m.match_method IN ('EXACT', 'FUZZY')
JOIN SILVER.CONTRACTS c ON c.contract_id = b.service_ref
WHERE m.account_id <> c.account_id;

-- 4. Detection vs answer key: true positives, false positives, missed
CREATE OR REPLACE TABLE GOLD.SCORECARD AS
WITH found AS (SELECT exception_type, contract_id, period FROM GOLD.EXCEPTIONS WHERE exception_type <> 'UNLINKED_INVOICE'),
truth AS (SELECT exception_type, contract_id, period FROM BRONZE.ANSWER_KEY)
SELECT COALESCE(f.exception_type, t.exception_type) AS exception_type,
       SUM(CASE WHEN f.contract_id IS NOT NULL AND t.contract_id IS NOT NULL THEN 1 ELSE 0 END) AS true_pos,
       SUM(CASE WHEN t.contract_id IS NULL THEN 1 ELSE 0 END) AS false_pos,
       SUM(CASE WHEN f.contract_id IS NULL THEN 1 ELSE 0 END) AS missed
FROM found f FULL OUTER JOIN truth t
  ON f.exception_type = t.exception_type AND f.contract_id = t.contract_id AND f.period = t.period
GROUP BY 1 ORDER BY 1;
SELECT * FROM GOLD.SCORECARD;
