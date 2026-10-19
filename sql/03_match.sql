-- ============================================================
-- MATCHING: resolve customer names to CRM accounts, link invoices to contracts
-- ============================================================
USE ROLE RA_ENGINEER; USE WAREHOUSE RA_WH; USE SCHEMA RA_DEMO.SILVER;

-- 1. Score every distinct ERP and billing name against every CRM account; keep the top two
CREATE OR REPLACE TABLE SILVER.NAME_CANDIDATES AS
WITH src AS (
  SELECT DISTINCT 'ERP' AS source, customer_name AS raw_name, name_norm FROM SILVER.INVOICES
  UNION
  SELECT DISTINCT 'BILLING', customer_name, name_norm FROM SILVER.BILLING
)
SELECT s.source, s.raw_name, s.name_norm, a.account_id, a.name_norm AS account_norm,
       JAROWINKLER_SIMILARITY(s.name_norm, a.name_norm) AS score,
       ROW_NUMBER() OVER (PARTITION BY s.source, s.raw_name ORDER BY JAROWINKLER_SIMILARITY(s.name_norm, a.name_norm) DESC, a.account_id) AS rnk
FROM src s CROSS JOIN SILVER.ACCOUNTS a
QUALIFY rnk <= 2;

-- 2. Decide: EXACT on normalised name; FUZZY if strong and clearly ahead of the runner-up; else REVIEW
CREATE OR REPLACE TABLE SILVER.NAME_MATCHES AS
WITH top2 AS (
  SELECT source, raw_name,
         MAX(CASE WHEN rnk = 1 THEN account_id END) AS account_id,
         MAX(CASE WHEN rnk = 1 THEN score END) AS best_score,
         MAX(CASE WHEN rnk = 2 THEN score END) AS runner_up,
         MAX(CASE WHEN rnk = 1 AND name_norm = account_norm THEN 1 ELSE 0 END) AS is_exact
  FROM SILVER.NAME_CANDIDATES GROUP BY source, raw_name
)
SELECT source, raw_name, account_id, best_score, runner_up,
       CASE WHEN is_exact = 1 THEN 'EXACT'
            WHEN best_score >= 90 AND best_score - runner_up >= 3 THEN 'FUZZY'
            ELSE 'REVIEW' END AS match_method
FROM top2;

-- 3. ERP customer key -> CRM account: majority vote over that key's resolved invoice names
CREATE OR REPLACE TABLE SILVER.ERP_CUSTOMER_XREF AS
SELECT i.customer_account, m.account_id, COUNT(*) AS votes,
       SUM(COUNT(*)) OVER (PARTITION BY i.customer_account) AS total_votes
FROM SILVER.INVOICES i
JOIN SILVER.NAME_MATCHES m ON m.source = 'ERP' AND m.raw_name = i.customer_name AND m.match_method IN ('EXACT', 'FUZZY')
GROUP BY i.customer_account, m.account_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY i.customer_account ORDER BY COUNT(*) DESC, m.account_id) = 1;

-- 4. Invoice -> contract: by reference where present; otherwise infer from account, period and amount
CREATE OR REPLACE TABLE SILVER.INVOICE_CONTRACT AS
WITH inv AS (
  SELECT i.*, x.account_id FROM SILVER.INVOICES i
  LEFT JOIN SILVER.ERP_CUSTOMER_XREF x ON x.customer_account = i.customer_account
),
cand AS (
  SELECT inv.invoice_id, c.contract_id
  FROM inv JOIN SILVER.CONTRACTS c
    ON c.account_id = inv.account_id AND inv.period BETWEEN c.start_month AND c.end_month
   AND c.monthly_amount = inv.amount
  WHERE inv.contract_ref IS NULL
),
cnt AS (SELECT invoice_id, COUNT(*) AS n, MIN(contract_id) AS contract_id FROM cand GROUP BY invoice_id)
SELECT inv.invoice_id, inv.customer_account, inv.account_id, inv.period, inv.amount,
       COALESCE(inv.contract_ref, CASE WHEN cnt.n = 1 THEN cnt.contract_id END) AS contract_id,
       CASE WHEN inv.contract_ref IS NOT NULL THEN 'REFERENCE'
            WHEN cnt.n = 1 THEN 'INFERRED'
            WHEN cnt.n > 1 THEN 'AMBIGUOUS'
            ELSE 'UNMATCHED' END AS link_method
FROM inv LEFT JOIN cnt ON cnt.invoice_id = inv.invoice_id;
