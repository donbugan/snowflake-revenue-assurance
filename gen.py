"""Generate synthetic revenue-assurance extracts (CRM, ERP, billing) plus an answer key.

All names and figures are invented. Seeded, so reruns give identical files.
"""
import csv, random, os
from datetime import date

random.seed(20261019)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(OUT, exist_ok=True)

MONTHS = [f"2026-{m:02d}" for m in range(4, 10)]  # Apr..Sep 2026
FIRST = ["Karoo", "Atlantic", "Highveld", "Protea", "Baobab", "Fynbos", "Drakensberg", "Kalahari",
         "Umoya", "Ndlovu", "Seaboard", "Tafelberg", "Limpopo", "Vaal", "Mopani", "Ubuntu",
         "Aloe", "Springbok", "Cederberg", "Zambezi", "Kestrel", "Marula", "Riverside", "Summit",
         "Oakridge", "Pinnacle", "Meridian", "Granite", "Lighthouse", "Silverleaf"]
SECOND = ["Logistics", "Foods", "Mining Services", "Engineering", "Retail", "Health", "Telecoms",
          "Water", "Freight", "Holdings", "Packaging", "Security", "Energy", "Agri", "Construction"]
PRODUCTS = [("Fleet Telematics", 4200), ("Managed Network", 18500), ("Cloud Backup", 2600),
            ("Field Service Licences", 7800), ("Metering Service", 12400), ("Support Retainer", 9500)]

def pick_names(n):
    seen, out = set(), []
    while len(out) < n:
        nm = f"{random.choice(FIRST)} {random.choice(SECOND)}"
        if nm not in seen:
            seen.add(nm); out.append(nm)
    return out

def variant(name):
    """A realistic re-keying of a customer name in another system."""
    r = random.random()
    if r < 0.25: return name.upper() + " (PTY) LTD"
    if r < 0.45: return name + " Pty Ltd"
    if r < 0.60: return name.replace("Engineering", "Eng.").replace("Services", "Svcs").replace("Holdings", "Hldgs") + " (Pty) Ltd"
    if r < 0.75:  # one-letter typo
        i = random.randrange(1, len(name) - 1)
        while name[i] == " ":
            i = random.randrange(1, len(name) - 1)
        return name[:i] + name[i + 1] + name[i] + name[i + 2:]
    if r < 0.85: return "The " + name
    return name + " Proprietary Limited"

def mi(month):  # month index
    return MONTHS.index(month)

accounts = []
for k, nm in enumerate(pick_names(55), start=1):
    accounts.append(dict(account_id=f"0015g00000{k:05d}AAA", account_name=nm + " (Pty) Ltd", base=nm,
                         contact_email=f"accounts@{nm.lower().replace(' ', '')}.co.za",
                         erp_cust=f"C-{10000 + k}"))

contracts, k = [], 0
for a in accounts:
    for _ in range(random.choice([1, 1, 1, 2, 2])):
        k += 1
        prod, price = random.choice(PRODUCTS)
        amt = round(price * random.choice([0.8, 1, 1, 1.2, 1.5]), 2)
        s = random.choice(MONTHS[:3]); e = random.choice(MONTHS[3:] + ["2027-03"] * 3)
        contracts.append(dict(contract_id=f"CTR-{k:04d}", account_id=a["account_id"], product=prod,
                              start_month=s, end_month=e, monthly_amount=amt, acct=a))

def active(c):
    return [m for m in MONTHS if c["start_month"] <= m <= c["end_month"]]

answer, invoices, bills = [], [], []
inv_n = bill_n = 0
# Choose injected problems
pool = contracts[:]; random.shuffle(pool)
not_billed = set(c["contract_id"] for c in pool[:3])           # contract never billed
missing_inv = {}                                                # contract -> month with no invoice
for c in pool[3:10]:
    missing_inv[c["contract_id"]] = random.choice(active(c))
under = {}                                                      # contract -> month under-billed
for c in pool[10:16]:
    under[c["contract_id"]] = random.choice(active(c))
after_end = [c for c in pool[16:40] if c["end_month"] < MONTHS[-1]][:3]  # billed past end
dupes = {}
for c in pool[40:43]:
    dupes[c["contract_id"]] = random.choice(active(c))
noref = set(c["contract_id"] for c in pool[43:70])             # invoices missing contract ref (need fuzzy match)

for c in contracts:
    a = c["acct"]
    for m in active(c):
        # ERP invoice
        if missing_inv.get(c["contract_id"]) != m:
            for _ in range(2 if dupes.get(c["contract_id"]) == m else 1):
                inv_n += 1
                invoices.append(dict(invoice_id=f"INV-{26000 + inv_n}", customer_account=a["erp_cust"],
                                     customer_name=variant(a["base"]),
                                     contract_ref="" if c["contract_id"] in noref else c["contract_id"],
                                     invoice_date=f"{m}-{random.randint(1, 5):02d}", amount=f"{c['monthly_amount']:.2f}",
                                     currency="ZAR"))
        else:
            answer.append(dict(exception_type="MISSING_INVOICE", contract_id=c["contract_id"], period=m,
                               value_at_risk=f"{c['monthly_amount']:.2f}"))
        # Billing line
        if c["contract_id"] in not_billed:
            answer.append(dict(exception_type="NOT_BILLED", contract_id=c["contract_id"], period=m,
                               value_at_risk=f"{c['monthly_amount']:.2f}"))
            continue
        amt = c["monthly_amount"]
        if under.get(c["contract_id"]) == m:
            amt = round(amt * random.choice([0.5, 0.75, 0.9]), 2)
            answer.append(dict(exception_type="UNDER_BILLED", contract_id=c["contract_id"], period=m,
                               value_at_risk=f"{c['monthly_amount'] - amt:.2f}"))
        bill_n += 1
        bills.append(dict(bill_id=f"PB{700000 + bill_n}", customer_name=variant(a["base"]),
                          service_ref=c["contract_id"], period=m, billed_amount=f"{amt:.2f}"))
    if dupes.get(c["contract_id"]):
        answer.append(dict(exception_type="DUPLICATE_INVOICE", contract_id=c["contract_id"],
                           period=dupes[c["contract_id"]], value_at_risk=f"{c['monthly_amount']:.2f}"))

for c in after_end:
    nxt = MONTHS[mi(c["end_month"]) + 1]
    bill_n += 1
    bills.append(dict(bill_id=f"PB{700000 + bill_n}", customer_name=variant(c["acct"]["base"]),
                      service_ref=c["contract_id"], period=nxt, billed_amount=f"{c['monthly_amount']:.2f}"))
    answer.append(dict(exception_type="BILLED_AFTER_END", contract_id=c["contract_id"], period=nxt,
                       value_at_risk="0.00"))

def w(name, rows, cols):
    with open(os.path.join(OUT, name), "w", newline="", encoding="utf-8") as f:
        wr = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore"); wr.writeheader(); wr.writerows(rows)
    print(f"{name}: {len(rows)} rows")

w("crm_accounts.csv", accounts, ["account_id", "account_name", "contact_email"])
w("crm_contracts.csv", contracts, ["contract_id", "account_id", "product", "start_month", "end_month", "monthly_amount"])
w("erp_invoices.csv", invoices, ["invoice_id", "customer_account", "customer_name", "contract_ref", "invoice_date", "amount", "currency"])
w("billing_lines.csv", bills, ["bill_id", "customer_name", "service_ref", "period", "billed_amount"])
w("answer_key.csv", sorted(answer, key=lambda r: (r["exception_type"], r["contract_id"], r["period"])),
  ["exception_type", "contract_id", "period", "value_at_risk"])
print("invoices without contract_ref:", sum(1 for i in invoices if not i["contract_ref"]))
