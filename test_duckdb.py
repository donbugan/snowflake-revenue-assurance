"""Dry-run the Snowflake SQL (02-05) locally in DuckDB to check the logic before the real build.

Translates the handful of Snowflake-only functions; setup, COPY INTO and governance are Snowflake-only.
"""
import re, sys, os, duckdb

HERE = os.path.dirname(os.path.abspath(__file__))
con = duckdb.connect()
for s in ("bronze", "silver", "gold"):
    con.execute(f"CREATE SCHEMA {s}")
for t, f in [("crm_accounts", "crm_accounts"), ("crm_contracts", "crm_contracts"), ("erp_invoices", "erp_invoices"),
             ("billing_lines", "billing_lines"), ("answer_key", "answer_key")]:
    con.execute(f"CREATE TABLE bronze.{t} AS SELECT *, '{f}.csv' AS _file, row_number() OVER () AS _row "
                f"FROM read_csv('{HERE}/data/{f}.csv', all_varchar=true, header=true)")
con.execute(r"""CREATE MACRO silver.norm_name(n) AS trim(regexp_replace(
    regexp_replace(regexp_replace(' ' || regexp_replace(upper(n), '[^A-Z0-9 ]', '', 'g') || ' ',
      ' (THE|PTY|LTD|PROPRIETARY|LIMITED) ', ' ', 'g'), ' (THE|PTY|LTD|PROPRIETARY|LIMITED) ', ' ', 'g'), ' +', ' ', 'g'))""")

SUBS = [
    (r"TRY_TO_NUMBER\(([^,()]+), 12, 2\)", r"TRY_CAST(\1 AS DECIMAL(12,2))"),
    (r"TRY_TO_DATE\(([^()]+)\)", r"TRY_CAST(\1 AS DATE)"),
    (r"TO_CHAR\((.*?), 'YYYY-MM'\)", r"strftime(\1, '%Y-%m')"),
    (r"JAROWINKLER_SIMILARITY\(([^,()]+), ([^,()]+)\)", r"round(jaro_winkler_similarity(\1, \2) * 100)"),
    (r"LISTAGG\((\w+), ','\) WITHIN GROUP \(ORDER BY (\w+)\)", r"string_agg(\1, ',' ORDER BY \2)"),
    (r"FROM VALUES (.*);", r"FROM (VALUES \1) v(column1);"),
]

def run(path):
    sql = open(path, encoding="utf-8").read()
    sql = re.sub(r"--[^\n]*", "", sql)
    sql = re.sub(r"CREATE OR REPLACE FUNCTION.*?\$\$;", "", sql, flags=re.S)
    for a, b in SUBS:
        sql = re.sub(a, b, sql)
    for stmt in [s.strip() for s in sql.split(";")]:
        body = "\n".join(l for l in stmt.splitlines() if not l.strip().startswith("--")).strip()
        if not body or body.upper().startswith("USE "):
            continue
        res = con.execute(body)
        if body.upper().startswith("SELECT"):
            cols = [d[0] for d in res.description]
            print(" | ".join(cols))
            for r in res.fetchall():
                print(" | ".join(str(v) for v in r))
            print()

for f in ["02_silver.sql", "03_match.sql", "04_gold.sql", "05_validate.sql"]:
    print(f"===== {f}")
    run(os.path.join(HERE, "sql", f))
