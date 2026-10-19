# Revenue assurance reconciliation in Snowflake (demo)

A small build of the pattern behind a revenue assurance programme: three systems that should agree
(CRM contracts, ERP invoices, billing lines) are landed, cleaned, matched and reconciled, and every
mismatch becomes a traceable exception.

**All data is synthetic.** Company names, IDs and amounts are invented by `gen.py` (seeded, so it is
reproducible). `answer_key.csv` lists the 33 problems deliberately planted in the data, so the
pipeline's detection can be scored.

## What is in the data

| File | Rows | Plays the part of |
|---|---|---|
| crm_accounts.csv | 55 | CRM accounts (Salesforce-style IDs) |
| crm_contracts.csv | 70 | CRM contracts: product, term, monthly amount |
| erp_invoices.csv | 315 | ERP invoices: own customer key, re-keyed names, contract ref missing on 124 |
| billing_lines.csv | 308 | Billing system lines: service ref, period, billed amount |
| crm_contract_changes.csv | 6 | CRM contract amendments for the SCD Type 2 step |
| answer_key.csv | 33 | Planted problems: missing invoices, unbilled contracts, under-billing, duplicates, billing after term end |

Names are re-keyed the way they drift between real systems: "(PTY) LTD" in capitals, "Pty Ltd",
"Proprietary Limited", a leading "The", abbreviations ("Eng.", "Svcs", "Hldgs") and swapped letters.

## Layers

- **BRONZE**: files loaded as text with `COPY INTO`, file name and row number kept on every row.
- **SILVER**: typed with `TRY_TO_*` (failures go to `REJECTS`, not the floor), names normalised by a SQL UDF,
  customers resolved to CRM accounts, invoices linked to contracts.
- **GOLD**: `GOLDEN_THREAD` (contracted vs invoiced vs billed per contract-month), `EXCEPTIONS`
  (one traceable row per problem with evidence IDs), `EXCEPTION_SUMMARY`, `SCORECARD`.

## Matching

1. **Deterministic**: normalised names equal, or the invoice carries a contract reference.
2. **Fuzzy**: `JAROWINKLER_SIMILARITY` of 90 or more, and at least 3 points clear of the runner-up.
   Anything weaker goes to `REVIEW` rather than being guessed.
3. **ERP key cross-reference**: each ERP customer key is mapped to the CRM account most of its invoice
   names resolve to, so one well-matched invoice carries the rest.
4. **Invoices without a reference** are inferred from account + period + amount when exactly one contract fits.

## Run order (about 15 minutes once files are uploaded)

1. Sign up for a Snowflake trial; open a SQL worksheet as ACCOUNTADMIN.
2. Run `00_setup.sql`.
3. Upload the five CSVs to `RA_DEMO.BRONZE.RA_STAGE` (Snowsight: Data > Databases > RA_DEMO > BRONZE > Stages > RA_STAGE > + Files).
4. Run `01_bronze.sql`: expect 55, 70, 315, 308, 33.
5. Run `02_silver.sql`, `03_match.sql`, `04_gold.sql`, `05_validate.sql`.
6. Run `06_governance.sql`: masked email for the analyst role, analyst blocked from SILVER, Time Travel recovery.
7. Upload `crm_contract_changes.csv` and run `07_scd2.sql`: contract dimension with history (expect 76 rows), then run its MERGE a second time to prove it is idempotent (still 76).

## First-pass result (dry-run locally; Snowflake's Jaro-Winkler may shift numbers slightly)

| Exception | Found correctly | False alarms | Missed |
|---|---|---|---|
| BILLED_AFTER_END | 3 | 0 | 0 |
| DUPLICATE_INVOICE | 3 | 0 | 0 |
| MISSING_INVOICE | 7 | **13** | 0 |
| NOT_BILLED | 14 | 0 | 0 |
| UNDER_BILLED | 6 | 0 | 0 |

Plus 2 billing names left in REVIEW. Both are the build's real work for tonight:

### Challenge 1: the 13 false alarms
One customer holds two identical contracts (same product, same R18,500 a month). Invoices without a
reference fit both, so they are marked `AMBIGUOUS`, never linked, and the contract-months look uninvoiced.
Fix idea: allocate by elimination. Within each account + period + amount group, if the number of
unreferenced invoices equals the number of contracts still lacking an invoice, pair them off in a
fixed order. Re-run 04 and 05; MISSING_INVOICE false alarms should go to 0.

### Challenge 2: abbreviations
"Ndlovu Eng." and "Umoya Eng." land in REVIEW because the runner-up is too close. Add an abbreviation
step to `NORM_NAME` (ENG to ENGINEERING, SVCS to SERVICES, HLDGS to HOLDINGS) and re-run 02 to 05.

### Challenge 3 (optional): make the reconciliation history-aware
`crm_contract_changes.csv` holds 6 amendments (escalations, a discount, two upgrades). The ERP and billing
extracts were never updated for them, which is exactly how leakage happens in real life. Rebuild
`GOLD.EXPECTED` from `SILVER.DIM_CONTRACT` (the version valid in each period, not the original amount)
and re-run 04. New UNDER_BILLED rows appear where an escalation was never billed, and over-billing where a
discount was never applied. Those are not in the answer key: they are findings.

## SCD Type 2 design (07_scd2.sql)

- Surrogate key per version; `valid_from` inclusive, `valid_to` exclusive, `is_current` flag.
- One `MERGE`: source rows keyed by `contract_id` close the current version; NULL-keyed copies of the
  changed rows fall through to `NOT MATCHED` and insert the new version.
- Only real changes (product or amount differs from the current version) create history, so a rerun
  changes nothing.
- Checks: one current row per contract, the history of each amended contract, and a point-in-time lookup.

## What this demonstrates, honestly

Medallion layering, `COPY INTO` with load lineage, typed casting with a rejects table, a SQL UDF,
deterministic and fuzzy entity resolution, exception datasets with evidence, source-to-target counts,
detection scored against ground truth, SCD Type 2 with an idempotent MERGE, warehouse auto-suspend and a resource monitor, role separation,
a dynamic masking policy, and Time Travel recovery. It is a demo on a trial account, not production experience.
