"""Resumable benchmark sweep. Each (scenario, system) runs in its own bench.exe process with a timeout;
a timeout is recorded as DNF (lower bound = timeout). Rows are appended to results/raw.csv.

usage: python scripts/run_matrix.py [matrix-name] [--reps N] [--timeout S] [--only SUBSTR] [--out FILE]
                                    [--systems a,b,c] [--extra "--bulk 1"]
--out defaults to results/raw.csv (the 2026-09 campaign); the 2026-11 re-measurement uses results/v2/raw.csv.
--systems overrides each scenario's system list (intersected with nothing: exactly these systems).
--extra appends arguments to every bench.exe call (e.g. an engine switch); use it together with a distinct sys name.
"""
import csv, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCH = os.path.join(ROOT, "bin", "bench.exe")
COLS = ["label", "sys", "rep", "ms", "commits", "aborts", "giveup", "eff", "noop", "txn_per_s", "eff_per_s",
        "upd_p50_us", "upd_p95_us", "upd_p99_us", "ro_p50_us", "ro_p99_us", "bytes", "ab_ww_pending", "ab_ww_late",
        "ab_chain_false", "ab_ser_point", "ab_ser_scan", "ab_resource", "ab_lock", "ab_stm_read", "casfail",
        "growths", "resv_atomics", "epochs", "check", "flag"]

V = 1 << 20
TXN_SYSTEMS = ["gtx", "gtx-m4", "gtx-gs1", "gtx-cons", "2pl", "stm", "stm-nodeg", "nontx"]  # gtx-m4/-gs1 added 2026-11
# (graph, stream length N) -- N must not exceed the 20% insert tail of the graph (workload.hpp aborts otherwise)
SNAP_GRAPHS = [("roadNet-CA", 1 << 20), ("wiki-Talk", 1 << 19), ("cit-Patents", 1 << 21), ("soc-pokec", 1 << 21)]
SWEEP_LOG2 = (10, 12, 14, 16, 18, 20, 22)
SWEEP_ARGS = f"--V {V} --N {1 << 22} --K 1 --init 4000000 --pins .5 --pdel .5"


def scen(label, args, systems=TXN_SYSTEMS):
    return {"label": label, "args": args, "systems": systems}


def matrix(name):
    m = []
    if name in ("main", "all"):
        for K in (1, 2, 4, 8, 32):
            N = (1 << 20) // K
            base = f"--V {V} --N {N} --K {K} --init 4000000"
            m.append(scen(f"uniform-ins-K{K}", base + " --pins 1"))
            m.append(scen(f"hub50-ins-K{K}", base + " --src hub --hub 0.5 --pins 1"))
        base = f"--V {V} --N {1 << 18} --K 4 --init 4000000"
        m.append(scen("uniform-churn-K4", base + " --pins .5 --pdel .5"))
        m.append(scen("rmat-churn-K4", base + " --src rmat --pins .5 --pdel .5"))
        m.append(scen("zipf-churn-K4", base + " --src zipf --zipf 1.0 --pins .5 --pdel .5"))
        m.append(scen("uniform-delete-K4", base + " --pins 0 --pdel 1"))
        m.append(scen("identical-edge-1024-K4", base + " --hot 1024 --hotfrac 0.5 --pins .5 --pdel .5"))
        m.append(scen("identical-edge-64-K4", base + " --hot 64 --hotfrac 0.5 --pins .5 --pdel .5"))
        m.append(scen("zipf-readers50-K4", base + " --src zipf --zipf 1.0 --pins .5 --pdel .5 --ro 0.5 --roscan 0.1"))
        m.append(scen("uniform-readers50-K4", base + " --pins .5 --pdel .5 --ro 0.5 --roscan 0.1"))
        m.append(scen("rmat-readers90-K4", base + " --src rmat --pins .5 --pdel .5 --ro 0.9 --roscan 0.1"))
    if name in ("ser", "all"):
        base = f"--V {V} --N {1 << 18} --K 4 --init 4000000"
        for lab, a in (("uniform-rw-K4", " --pins .4 --pdel .3 --pread .3"), ("zipf-rw-K4", " --src zipf --zipf 1.0 --pins .4 --pdel .3 --pread .3"),
                       ("hub50-rw-K4", " --src hub --hub 0.5 --pins .4 --pdel .3 --pread .3")):
            m.append(scen("SER-" + lab, base + a + " --ser 1", ["gtx", "gtx-m4", "gtx-cons", "2pl", "stm", "stm-nodeg"]))
            m.append(scen("SI-" + lab, base + a, ["gtx", "gtx-m4", "gtx-cons"]))
    if name in ("ablation", "all"):
        for K in (1, 8):
            N = (1 << 20) // K
            for h in ("0", "0.5", "1.0"):
                src = "" if h == "0" else f" --src hub --hub {h}"
                m.append(scen(f"abl-hub{h}-ins-K{K}", f"--V {V} --N {N} --K {K} --init 4000000 --pins 1{src}",
                              ["gtx", "gtx-cons", "gtx-coop-only", "gtx-dst-only"]))
        base = f"--V {V} --N {1 << 18} --K 4 --init 4000000"
        m.append(scen("abl-zipf-churn-K4", base + " --src zipf --zipf 1.0 --pins .5 --pdel .5", ["gtx", "gtx-cons", "gtx-coop-only", "gtx-dst-only"]))
    if name in ("fair", "all"):  # GTX with per-lane scans (baselines scan per thread): isolates scan parallelization
        base = f"--V {V} --N {1 << 18} --K 4 --init 4000000"
        for lab, a in (("zipf-readers50-K4", " --src zipf --zipf 1.0 --pins .5 --pdel .5 --ro 0.5 --roscan 0.1"),
                       ("uniform-readers50-K4", " --pins .5 --pdel .5 --ro 0.5 --roscan 0.1"),
                       ("rmat-readers90-K4", " --src rmat --pins .5 --pdel .5 --ro 0.9 --roscan 0.1")):
            m.append(scen(lab + "-lanescan", base + a + " --coopscan 0", ["gtx", "gtx-cons"]))
    if name in ("fairro", "all"):  # every system with warp-cooperative scans in read-only transactions
        base = f"--V {V} --N {1 << 18} --K 4 --init 4000000"
        for lab, a in (("zipf-readers50-K4", " --src zipf --zipf 1.0 --pins .5 --pdel .5 --ro 0.5 --roscan 0.1"),
                       ("uniform-readers50-K4", " --pins .5 --pdel .5 --ro 0.5 --roscan 0.1"),
                       ("rmat-readers90-K4", " --src rmat --pins .5 --pdel .5 --ro 0.9 --roscan 0.1")):
            m.append(scen(lab + "-roCoop", base + a + " --blcoop 1", TXN_SYSTEMS))
    if name in ("gpmamatch", "all"):  # identical K=1 streams to scripts/run_gpma.py
        for lab, a in (("uniform-churn-K1", " --pins .5 --pdel .5"), ("rmat-churn-K1", " --src rmat --pins .5 --pdel .5")):
            m.append(scen(lab, f"--V {V} --N {1 << 20} --K 1 --init 4000000" + a))
    if name in ("snap",):  # real SNAP graphs, sliding window (workload.hpp makeFileWorkload); GTX bulk-loaded
        for g, n in SNAP_GRAPHS:
            path = os.path.join(ROOT, "data", "snap", g + ".bin")
            if not os.path.exists(path):
                continue
            base = f"--src file --graph {path} --initfrac 0.8 --bulk 1"  # --bulk only affects GTX (baselines pre-size)
            m.append(scen(f"snap-{g}-ins-K1", base + f" --N {n} --K 1 --pins 1"))
            m.append(scen(f"snap-{g}-churn-K1", base + f" --N {n} --K 1 --pins .5 --pdel .5"))
            m.append(scen(f"snap-{g}-churn-K4", base + f" --N {n // 4} --K 4 --pins .5 --pdel .5"))
            m.append(scen(f"snap-{g}-readers90-K4", base + f" --N {n // 4} --K 4 --pins .5 --pdel .5 --ro 0.9 --roscan 0.1"))
            m.append(scen(f"snap-{g}-SER-rw-K4", base + f" --N {n // 4} --K 4 --pins .4 --pdel .3 --pread .3 --ser 1",
                          ["gtx", "2pl", "stm", "stm-nodeg"]))
    if name in ("sweep",):  # batch-size sweep, identical K=1 stream to scripts/run_gpma.py --sweep (GTX: one launch per batch)
        for lg in SWEEP_LOG2:
            m.append(scen(f"sweep-uniform-churn-K1-b{lg}", SWEEP_ARGS + f" --batch {1 << lg}", ["gtx"]))
    if name == "check":  # every transactional system validated with the history checker (small)
        base = "--V 65536 --N 65536 --K 4 --init 200000"
        for lab, a in (("uniform", " --pins .4 --pdel .3 --pread .2 --ro .2 --roscan .1"), ("hub50", " --src hub --hub 0.5 --pins .4 --pdel .3 --pread .2 --ro .2 --roscan .1"),
                       ("zipf", " --src zipf --zipf 1.0 --pins .4 --pdel .3 --pread .2 --ro .2 --roscan .1")):
            m.append(scen("check-SI-" + lab, base + a + " --check 1", ["gtx", "gtx-m4", "gtx-cons"]))
            m.append(scen("check-SER-" + lab, base + a + " --check 1 --ser 1", ["gtx", "gtx-m4", "gtx-cons", "2pl", "stm", "stm-nodeg"]))
        # checked runs of the new harness paths: bulk loader, batch mode, file source (advisor: each needs a checked run)
        m.append(scen("check-bulk-SI-uniform", base + " --pins .4 --pdel .3 --pread .2 --ro .2 --roscan .1 --check 1 --bulk 1", ["gtx", "gtx-m4"]))
        m.append(scen("check-bulk-SER-hub50", base + " --src hub --hub 0.5 --pins .4 --pdel .3 --pread .2 --ro .2 --roscan .1 --check 1 --ser 1 --bulk 1", ["gtx", "gtx-m4"]))
        m.append(scen("check-batch4096-SER-zipf", base + " --src zipf --zipf 1.0 --pins .4 --pdel .3 --pread .2 --ro .2 --roscan .1 --check 1 --ser 1 --batch 4096", ["gtx", "gtx-m4"]))
        rn = os.path.join(ROOT, "data", "snap", "roadNet-CA.bin")
        if os.path.exists(rn):
            m.append(scen("check-file-roadNet-SER", f"--src file --graph {rn} --N 65536 --K 4 --pins .4 --pdel .3 --pread .2 --pscan .1 --check 1 --ser 1 --bulk 1",
                          ["gtx", "gtx-m4", "2pl", "stm"]))
        wt = os.path.join(ROOT, "data", "snap", "wiki-Talk.bin")
        if os.path.exists(wt):
            m.append(scen("check-file-wikiTalk-SI", f"--src file --graph {wt} --N 65536 --K 4 --pins .4 --pdel .3 --pread .2 --pscan .1 --check 1 --bulk 1",
                          ["gtx", "gtx-m4"]))
    return m


def main():
    name = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "main"
    reps = int(sys.argv[sys.argv.index("--reps") + 1]) if "--reps" in sys.argv else 5
    timeout = float(sys.argv[sys.argv.index("--timeout") + 1]) if "--timeout" in sys.argv else 90
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else os.path.join(ROOT, "results", "raw.csv")
    systems = sys.argv[sys.argv.index("--systems") + 1].split(",") if "--systems" in sys.argv else None
    extra = sys.argv[sys.argv.index("--extra") + 1].split() if "--extra" in sys.argv else []
    os.makedirs(os.path.dirname(out), exist_ok=True)
    done = set()
    if os.path.exists(out):
        with open(out, newline="") as f:
            for r in csv.DictReader(f):
                done.add((r["label"], r["sys"]))
    new = not os.path.exists(out)
    with open(out, "a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(COLS + ["args", "timestamp"])
        for s in matrix(name):
            for sysname in (systems or s["systems"]):
                if only and only not in s["label"]:
                    continue
                if (s["label"], sysname) in done:
                    continue
                cmd = [BENCH, "--sys", sysname, "--label", s["label"], "--reps", str(reps)] + s["args"].split() + extra
                t0 = time.time()
                try:
                    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
                    rows = [l.split(",")[1:] for l in p.stdout.splitlines() if l.startswith("RESULT,")]
                    if not rows:
                        rows = [[s["label"], sysname, "-1", "ERR"] + [""] * (len(COLS) - 4)]
                        print("ERR", s["label"], sysname, p.returncode, p.stderr[-300:])
                    if p.stderr.strip():
                        print("  stderr:", p.stderr.strip()[-300:])
                except subprocess.TimeoutExpired:
                    rows = [[s["label"], sysname, "-1", f"DNF>{timeout * 1000:.0f}"] + [""] * (len(COLS) - 4)]
                for r in rows:
                    w.writerow(r + [s["args"], time.strftime("%Y-%m-%d %H:%M:%S")])
                f.flush()
                ms = sorted(float(r[3]) for r in rows if r[3].replace(".", "", 1).isdigit())
                med = ms[len(ms) // 2] if ms else rows[0][3]
                print(f"{s['label']:28s} {sysname:14s} median_ms={med} ({time.time() - t0:.1f}s)", flush=True)


if __name__ == "__main__":
    main()
