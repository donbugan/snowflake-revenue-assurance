"""Contract amendments for the SCD Type 2 exercise (synthetic, seeded)."""
import csv, random, os
random.seed(7)
HERE = os.path.dirname(os.path.abspath(__file__))
MONTHS = [f"2026-{m:02d}" for m in range(4, 10)]
rows = list(csv.DictReader(open(f"{HERE}/data/crm_contracts.csv")))
eligible = [r for r in rows if MONTHS.index(r["start_month"]) <= 2]
out = []
for i, r in enumerate(random.sample(eligible, 6), start=1):
    eff = MONTHS[MONTHS.index(r["start_month"]) + random.choice([2, 3])]
    amt, prod = float(r["monthly_amount"]), r["product"]
    if i % 3 == 0:
        prod = prod + " Plus"; amt = round(amt * 1.25, 2)      # upgrade
    else:
        amt = round(amt * random.choice([1.06, 1.08, 0.9]), 2)  # escalation or discount
    out.append(dict(change_id=f"AMD-{i:03d}", contract_id=r["contract_id"], effective_month=eff,
                    product=prod, monthly_amount=f"{amt:.2f}"))
with open(f"{HERE}/data/crm_contract_changes.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0])); w.writeheader(); w.writerows(out)
for o in out: print(o)
