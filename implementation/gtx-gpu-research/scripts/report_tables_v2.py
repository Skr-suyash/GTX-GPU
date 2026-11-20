"""Print the report.md v2 tables from results/v2 (summary.csv, speedups.csv, gpma_raw.csv). No hand-copied numbers.
Speedup = GTX-GPU committed txn/s / baseline committed txn/s (medians); CI = 95% bootstrap from speedups.csv.
For reader scenarios each baseline is taken in its better scan mode (plain vs '-roCoop'), as in the 2026-09 report."""
import csv, os, statistics
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "results", "v2")
S = {(r["label"], r["sys"]): r for r in csv.DictReader(open(os.path.join(D, "summary.csv")))}
SP = {(r["label"], r["vs"]): r for r in csv.DictReader(open(os.path.join(D, "speedups.csv")))}


def tps(label, sysn):
    r = S.get((label, sysn))
    if not r:
        return None
    if r["status"] != "ok":
        return r["status"]
    return float(r["txn_per_s"])


def cell(label, vs, alt=None):
    """speedup of gtx over vs on label (or the better of label / alt label for the baseline)."""
    cands = [label] + ([alt] if alt else [])
    best = None
    for lab in cands:
        sp = SP.get((lab, vs))
        if not sp:
            continue
        g = tps(lab, "gtx") if lab == label else tps(label, "gtx")
        b = tps(lab, vs)
        if isinstance(b, str):  # DNF
            val = sp["speedup"]
            key = float("inf")
        else:
            gv = tps(label, "gtx")
            key = b
            val = f"{gv / b:.2f}"
            if lab == label and sp["ci_lo"]:
                val += f" [{sp['ci_lo']}, {sp['ci_hi']}]"
        # better baseline = higher throughput (DNF is worst)
        if best is None or (not isinstance(b, str) and (best[0] == float("inf") or key > best[0])):
            best = (key if not isinstance(b, str) else float("inf"), val, lab)
    if not best:
        return "—"
    return best[1] + (" (roCoop)" if best[2] != label else "")


HEAD = [
    ("R-MAT, 90% snapshot readers", "rmat-readers90-K4", "rmat-readers90-K4-roCoop"),
    ("Zipf(1.0), 50% readers", "zipf-readers50-K4", "zipf-readers50-K4-roCoop"),
    ("Uniform, 50% readers", "uniform-readers50-K4", "uniform-readers50-K4-roCoop"),
    ("Serializable rw, Zipf", "SER-zipf-rw-K4", None),
    ("Serializable rw, 50% hub", "SER-hub50-rw-K4", None),
    ("Serializable rw, uniform", "SER-uniform-rw-K4", None),
    ("R-MAT churn, K=4", "rmat-churn-K4", None),
    ("Zipf churn, K=4", "zipf-churn-K4", None),
    ("Uniform churn, K=4", "uniform-churn-K4", None),
    ("Identical-edge contention, 1,024 hot edges", "identical-edge-1024-K4", None),
    ("Identical-edge contention, 64 hot edges", "identical-edge-64-K4", None),
    ("Large transactions, K=32, uniform", "uniform-ins-K32", None),
    ("Large transactions, K=32, 50% hub", "hub50-ins-K32", None),
    ("Hub (50%) inserts, K=8", "hub50-ins-K8", None),
    ("Hub (50%) inserts, K=1", "hub50-ins-K1", None),
    ("Uniform inserts, K=1", "uniform-ins-K1", None),
    ("Uniform deletes, K=4", "uniform-delete-K4", None),
]
print("## headline (speedup of GTX-GPU; >1 = GTX-GPU faster)\n")
print("| scenario | 2PL | TL2 STM | TL2 STM no-degree | non-tx CAS | GTX-conservative |")
print("|---|---:|---:|---:|---:|---:|")
for name, lab, alt in HEAD:
    print(f"| {name} | " + " | ".join(cell(lab, v, alt) for v in ("2pl", "stm", "stm-nodeg", "nontx", "gtx-cons")) + " |")

print("\n## GTX-GPU absolute + variants (median ms, MB)\n")
print("| scenario | gtx ms | gtx MB | gtx-m4 ms (×) | gtx-m4 MB | gtx-gs1 ms (×) | gtx-gs1 MB | 2PL ms | 2PL MB | abort ratio gtx | abort ratio gtx-m4 |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
labs = sorted({k[0] for k in S if not k[0].startswith(("check-", "snap-", "sweep-"))})
for lab in labs:
    g = S.get((lab, "gtx"))
    if not g or g["status"] != "ok":
        continue
    def f(sysn):
        r = S.get((lab, sysn))
        if not r:
            return ("", "", "")
        if r["status"] != "ok":
            return (r["status"], "", "")
        return (f"{float(r['ms_median']):.3f}", f"{int(r['bytes']) / 2**20:.0f}", r["abort_ratio"])
    gm, gb, ga = f("gtx"); mm, mb, ma = f("gtx-m4"); sm, sb, _ = f("gtx-gs1"); pm, pb, _ = f("2pl")
    rm = f" ({float(gm) / float(mm):.2f}×)" if mm and mm[0].isdigit() else ""
    rs = f" ({float(gm) / float(sm):.2f}×)" if sm and sm[0].isdigit() else ""
    fa = lambda x: f"{float(x):.3f}" if x else ""
    print(f"| {lab} | {gm} | {gb} | {mm}{rm} | {mb} | {sm}{rs} | {sb} | {pm} | {pb} | {fa(ga)} | {fa(ma)} |")

print("\n## SNAP sliding-window streams (median ms; speedup of GTX-GPU in committed txn/s)\n")
print("| stream | gtx ms | gtx MB | gtx-m4 × | gtx-gs1 × | 2PL | TL2 STM | TL2 no-deg | non-tx CAS |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
for lab in sorted({k[0] for k in S if k[0].startswith("snap-")}):
    g = S.get((lab, "gtx"))
    if not g or g["status"] != "ok":
        print(f"| {lab} | {g['status'] if g else 'missing'} | | | | | | | |")
        continue
    gv = float(g["txn_per_s"])
    def x(sysn):
        r = S.get((lab, sysn))
        if not r:
            return "—"
        if r["status"] != "ok":
            sp = SP.get((lab, sysn))
            return sp["speedup"] + " (DNF)" if sp else r["status"]
        return f"{gv / float(r['txn_per_s']):.2f}"
    print(f"| {lab} | {float(g['ms_median']):.3f} | {int(g['bytes']) / 2**20:.0f} | {x('gtx-m4')} | {x('gtx-gs1')} | {x('2pl')} | {x('stm')} | {x('stm-nodeg')} | {x('nontx')} |")

# GPMA+: effective edge changes/s, GTX-GPU K=1 streams vs GPMA+ batches
g = defaultdict(list)
for r in csv.DictReader(open(os.path.join(D, "gpma_raw.csv"))):
    if r["ms"].replace(".", "", 1).isdigit():
        g[(r["label"], r["sys"], int(r["batch"]))].append(r)
def gmed(rs):
    rs = sorted(rs, key=lambda r: float(r["ms"])); return rs[len(rs) // 2]
print("\n## GPMA+ on identical streams (effective edge changes/s; GTX-GPU = one transaction per op, K=1;")
print("GPMA+ = the FASTER of upstream (CDP1) and Windows port, per cell)\n")
print("| stream | batch | GPMA+ upstream ms | GPMA+ port ms | GPMA+ verify | GTX-GPU ms | GTX-GPU speedup (eff. edges/s, vs faster GPMA+) |")
print("|---|---:|---:|---:|---|---:|---:|")
for (lab, sysn, b), rs in sorted(g.items()):
    if sysn != "gpma-upstream" or lab.startswith("sweep"):
        continue
    mu = gmed(rs); po = g.get((lab, "gpma-port", b)); mp = gmed(po) if po else None
    best = mu if not mp or float(mu["eff_per_s"]) >= float(mp["eff_per_s"]) else mp
    gt = S.get((lab, "gtx"))
    ver = ";".join(sorted({r["verify"] for r in rs + (po or [])}))
    if gt and gt["status"] == "ok":
        print(f"| {lab} | {b} | {float(mu['ms']):.2f} | {float(mp['ms']) if mp else float('nan'):.2f} | {ver} | {float(gt['ms_median']):.2f} | {float(gt['eff_per_s']) / float(best['eff_per_s']):.1f}× |")
    else:
        print(f"| {lab} | {b} | {float(mu['ms']):.2f} | {float(mp['ms']) if mp else float('nan'):.2f} | {ver} | — | — |")

print("\n## Batch-size sweep, uniform churn K=1, 4M ops (total GPU ms; GTX-GPU = one launch per batch)\n")
print("| batch | GTX-GPU ms | GPMA+ upstream ms | GPMA+ port ms | GPMA+ verify | GTX-GPU speedup vs faster GPMA+ |")
print("|---:|---:|---:|---:|---|---:|")
for lg in (10, 12, 14, 16, 18, 20, 22):
    b = 1 << lg
    gt = S.get((f"sweep-uniform-churn-K1-b{lg}", "gtx"))
    up = g.get(("sweep-uniform-churn-K1", "gpma-upstream", b)); po = g.get(("sweep-uniform-churn-K1", "gpma-port", b))
    gm = float(gt["ms_median"]) if gt and gt["status"] == "ok" else None
    um = float(gmed(up)["ms"]) if up else None; pm = float(gmed(po)["ms"]) if po else None
    ver = ";".join(sorted({r["verify"] for r in (up or [])}))
    print(f"| 2^{lg} | {gm:.2f} | {um:.2f} | {pm:.2f} | {ver} | {min(um, pm) / gm:.1f}× |" if gm and um and pm else f"| 2^{lg} | {gm} | {um} | {pm} | {ver} | |")
