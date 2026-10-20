# Run log

## 2026-10-19: Snowflake trial, AWS af-south-1 (Cape Town), Enterprise edition

| Step | Result |
|---|---|
| Bronze load | 55 / 70 / 315 / 308 / 33 rows, matching the source files |
| Name matching | 334 names resolved (exact or fuzzy), 2 billing names held for review |
| Invoice linking | 191 by reference, 111 inferred, 13 ambiguous |
| Detection | 33 of 33 planted exceptions found |
| False positives | 13 MISSING_INVOICE, from one account with two identical contracts (Challenge 1) |
| Governance | Masking policy (clear for engineer, masked for analyst), analyst blocked from SILVER, Time Travel recovery |
| SCD Type 2 | 76 rows; MERGE rerun inserted 0, updated 0 (idempotent) |
| Cost | XSMALL warehouse, 60s auto-suspend, 5-credit resource monitor |

Local DuckDB dry run (`uv run python test_duckdb.py`) gave identical results.
