-- ============================================================
-- SCD TYPE 2: contract dimension with full history
-- Upload crm_contract_changes.csv to RA_STAGE first.
-- ============================================================
USE ROLE RA_ENGINEER; USE WAREHOUSE RA_WH; USE SCHEMA RA_DEMO.SILVER;

-- Bronze: amendments as text
CREATE OR REPLACE TABLE BRONZE.CRM_CONTRACT_CHANGES (change_id STRING, contract_id STRING, effective_month STRING,
  product STRING, monthly_amount STRING, _file STRING, _row NUMBER, _loaded_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());
COPY INTO BRONZE.CRM_CONTRACT_CHANGES (change_id, contract_id, effective_month, product, monthly_amount, _file, _row)
  FROM (SELECT $1, $2, $3, $4, $5, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER FROM @BRONZE.RA_STAGE)
  FILES = ('crm_contract_changes.csv') FILE_FORMAT = (FORMAT_NAME = 'BRONZE.CSV_FF');

-- 1. Initial load: one current version per contract, valid from its start month
CREATE OR REPLACE TABLE SILVER.DIM_CONTRACT (
  contract_key NUMBER AUTOINCREMENT,          -- surrogate key, one per version
  contract_id STRING, account_id STRING, product STRING, monthly_amount NUMBER(12,2),
  valid_from STRING, valid_to STRING,         -- valid_to exclusive; NULL = open
  is_current BOOLEAN, change_id STRING
);
INSERT INTO SILVER.DIM_CONTRACT (contract_id, account_id, product, monthly_amount, valid_from, valid_to, is_current, change_id)
SELECT contract_id, account_id, product, monthly_amount, start_month, NULL, TRUE, 'INITIAL' FROM SILVER.CONTRACTS;

-- 2. Apply amendments with one MERGE:
--    rows keyed by contract_id close the current version; the NULL-keyed copies insert the new version
MERGE INTO SILVER.DIM_CONTRACT t
USING (
  SELECT c.contract_id AS merge_key, c.* FROM (
    SELECT ch.change_id, ch.contract_id, k.account_id, ch.effective_month, ch.product,
           TRY_TO_NUMBER(ch.monthly_amount, 12, 2) AS monthly_amount
    FROM BRONZE.CRM_CONTRACT_CHANGES ch JOIN SILVER.CONTRACTS k ON k.contract_id = ch.contract_id) c
  UNION ALL
  SELECT NULL AS merge_key, c.* FROM (
    SELECT ch.change_id, ch.contract_id, k.account_id, ch.effective_month, ch.product,
           TRY_TO_NUMBER(ch.monthly_amount, 12, 2) AS monthly_amount
    FROM BRONZE.CRM_CONTRACT_CHANGES ch JOIN SILVER.CONTRACTS k ON k.contract_id = ch.contract_id) c
  JOIN SILVER.DIM_CONTRACT d ON d.contract_id = c.contract_id AND d.is_current
  WHERE d.product <> c.product OR d.monthly_amount <> c.monthly_amount
) s
ON t.contract_id = s.merge_key AND t.is_current
WHEN MATCHED AND (t.product <> s.product OR t.monthly_amount <> s.monthly_amount) THEN
  UPDATE SET valid_to = s.effective_month, is_current = FALSE
WHEN NOT MATCHED AND s.merge_key IS NULL THEN
  INSERT (contract_id, account_id, product, monthly_amount, valid_from, valid_to, is_current, change_id)
  VALUES (s.contract_id,
          s.account_id,
          s.product, s.monthly_amount, s.effective_month, NULL, TRUE, s.change_id);

-- 3. Checks
-- exactly one current row per contract (expect 0 rows)
SELECT contract_id, COUNT(*) FROM SILVER.DIM_CONTRACT WHERE is_current GROUP BY contract_id HAVING COUNT(*) <> 1;
-- history for amended contracts
SELECT contract_id, product, monthly_amount, valid_from, valid_to, is_current, change_id
FROM SILVER.DIM_CONTRACT
WHERE contract_id IN (SELECT contract_id FROM BRONZE.CRM_CONTRACT_CHANGES)
ORDER BY contract_id, valid_from;
-- point-in-time: what was each amended contract worth in July 2026?
SELECT contract_id, monthly_amount AS amount_jul_2026
FROM SILVER.DIM_CONTRACT
WHERE contract_id IN (SELECT contract_id FROM BRONZE.CRM_CONTRACT_CHANGES)
  AND valid_from <= '2026-07' AND (valid_to IS NULL OR valid_to > '2026-07')
ORDER BY contract_id;

-- 4. Idempotency: run the MERGE in step 2 again, then re-run the checks. Row count must not change.
SELECT COUNT(*) AS dim_rows FROM SILVER.DIM_CONTRACT;   -- expect 76 (70 initial + 6 new versions)
