# Item 86: summary of sweep86/*.json (L2 true, differentiated, needed, lost-with-tracking-intact; per reading).
import json, glob, os, re, sys
rows = []
for f in sorted(glob.glob(os.path.join(os.path.dirname(__file__), '*.json'))):
    tag = os.path.basename(f)[:-5]
    r = json.load(open(f)); runs = r['runs']
    for st in ('constituents', 'q'):
        rr = [x for x in runs if x['structure'] == st]
        n = len(rr)
        L2 = [x for x in rr if x['agency_L2']]
        rows.append((tag, st, n, len(L2), sum(x['differentiated'] for x in rr), sum(bool(x['value_needed']) for x in rr),
                     sum(not all(x['survival'].values()) for x in rr),
                     ' '.join(f"{x['H']}:{x['seed']}" for x in L2)))
filt = sys.argv[1] if len(sys.argv) > 1 else ''
print(f"{'tag':28} {'reading':12} {'n':>3} {'L2':>3} {'diff':>4} {'need':>4} {'lostIntact':>10}  L2 runs")
for t in rows:
    if filt in t[0]:
        print(f"{t[0]:28} {t[1]:12} {t[2]:>3} {t[3]:>3} {t[4]:>4} {t[5]:>4} {t[6]:>10}  {t[7]}")
