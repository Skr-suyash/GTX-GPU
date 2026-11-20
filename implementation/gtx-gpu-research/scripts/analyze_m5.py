"""Evaluate M5 criteria Q1, Q2, Q4 from results/m5/longrun_raw.csv (last run per system and workload).

Q1: memory bounded: no OOM, and the max bytes over the last third of rounds is <= 1.10x the max over the middle third.
Q2: e2e throughput of gtx-qc vs gtx over the rounds gtx completed, and vs gtx-big-arena over the rounds it completed.
Q4: compaction pause p50 / max.
usage: python -P scripts/analyze_m5.py
"""
import collections, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rows = collections.OrderedDict()  # (lab, wl) -> list of rounds of the LAST run
for line in open(os.path.join(ROOT, "results", "m5", "longrun_raw.csv"), encoding="utf-8"):
    f = line.rstrip("\n").split(",")
    if len(f) < 13 or f[2] != "ROUND": continue
    key, r = (f[0], f[3]), int(f[5])
    if r == 0 or key not in rows: rows[key] = []
    rows[key].append((r, float(f[6]), float(f[7]), int(f[8]), int(f[12]), int(f[11])))

def e2e(rs, n=None):
    rs = rs if n is None else rs[:n]
    return sum(x[3] for x in rs) / (sum(x[1] + x[2] for x in rs) / 1e3) / 1e6

wls = sorted({k[1] for k in rows})
print(f"{'workload':24s} {'system':28s} rnds oom  hwMB  Q1(last/mid)  e2e(Mtx/s)  vs-gtx@n  vs-big@n  pauses p50/max ms")
for wl in wls:
    base = rows.get(("gtx", wl), []); big = rows.get(("gtx-big-arena", wl), [])
    nb = sum(1 for x in base if x[5] == 0) or len(base)
    ng = sum(1 for x in big if x[5] == 0) or len(big)
    for (lab, w), rs in rows.items():
        if w != wl: continue
        n = len(rs); oom = any(x[5] > 0 for x in rs)
        mid = max(x[4] for x in rs[n // 3: 2 * n // 3]) if n >= 3 else 0
        last = max(x[4] for x in rs[2 * n // 3:]) if n >= 3 else 0
        p = sorted(x[2] for x in rs if x[2] > 0)
        vs = lambda ref, k: (e2e(rs, k) / e2e(ref, k)) if ref and k and n >= k else float("nan")
        print(f"{wl:24s} {lab:28s} {n:4d} {'Y' if oom else 'n':3s} {max(x[4] for x in rs)/1e6:6.0f} {last/mid if mid else 0:8.3f}"
              f"     {e2e(rs):8.1f}   {vs(base, nb):7.2f}   {vs(big, ng):7.2f}   {len(p):2d}x {p[len(p)//2] if p else 0:.1f}/{p[-1] if p else 0:.1f}")
