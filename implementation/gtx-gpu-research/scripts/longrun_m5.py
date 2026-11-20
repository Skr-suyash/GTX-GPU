"""M5 long-run campaign (design/design.md §7 M5): bounded memory under continuous update streams.

Writes results/m5/longrun_raw.csv (every ROUND and LONGRUN line, with rep) and results/m5/longrun.log.
usage: python -P scripts/longrun_m5.py [--reps 3] [--rounds 80] [--quick]
"""
import os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCH = os.path.join(ROOT, "bin", "bench.exe")
OUT = os.path.join(ROOT, "results", "m5")

def arg(k, d):
    return type(d)(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d

REPS, ROUNDS = arg("--reps", 3), arg("--rounds", 80)
QUICK = "--quick" in sys.argv
G = "--V 1048576 --init 4000000 --K 4 --perround 262144 --fifodel 1"
ARENA = "--arena 20000000 --desccap 20000000"
WL = {
    "uniform-churn-K4": "--pins .5 --pdel .5",
    "zipf-churn-K4": "--src zipf --zipf 1.0 --pins .5 --pdel .5",
    "identical-edge-1024-K4": "--hot 1024 --hotfrac 0.5 --pins .5 --pdel .5",
    "rmat-readers90-K4": "--src rmat --pins .5 --pdel .5 --ro .9 --roscan .1",
}
# (system label, bench sys, extra args). Policy chosen AFTER the registered criteria, from the sweep in
# results/m5/sweep.log (scripts/sweep_m5.py): triggered compaction, growShift 1, slack 100, hybrid kernels.
POL = "--growshift 1 --qcslack 100"
SYSTEMS = [
    ("gtx", "gtx", ""),
    ("gtx-gs1", "gtx-gs1", ""),                                             # layout effect without compaction
    ("gtx-big-arena", "gtx", "--arena 60000000 --desccap 60000000"),      # reference over more rounds (max arena)
    ("gtx-qc", "gtx-qc", POL),                                             # the M5 configuration reported
    ("gtx-qc-registered-default", "gtx-qc", ""),                           # growShift 3, slack 0 (as first registered)
    ("gtx-qc-legacy-kernels", "gtx-qc", POL + " --qcchunk 0"),             # warp-per-vertex compaction kernels
    ("gtx-qc-arena16M", "gtx-qc", POL + " --arena 16000000 --desccap 20000000"),   # headroom axis
    ("gtx-qc-arena40M", "gtx-qc", POL + " --arena 40000000 --desccap 20000000"),
]

def main():
    os.makedirs(OUT, exist_ok=True)
    raw = open(os.path.join(OUT, "longrun_raw.csv"), "a", encoding="utf-8")
    log = open(os.path.join(OUT, "longrun.log"), "a", encoding="utf-8")
    log.write(f"\n# {time.strftime('%Y-%m-%d %H:%M:%S')} reps={REPS} rounds={ROUNDS} bench={time.ctime(os.path.getmtime(BENCH))}\n")
    for wl, wargs in WL.items():
        for lab, sysn, extra in SYSTEMS:
            for rep in range(REPS if not QUICK else 1):
                cmd = [BENCH, "--sys", sysn, "--label", wl] + f"{G} {wargs} --rounds {ROUNDS} {ARENA} {extra} --seed {1 + rep}".split()  # later --arena wins
                t = time.time()
                p = subprocess.run(cmd, capture_output=True, text=True)
                for line in p.stdout.splitlines():
                    if line.startswith(("ROUND,", "LONGRUN,")):
                        raw.write(f"{lab},{rep},{line}\n")
                raw.flush()
                summ = [l for l in p.stdout.splitlines() if l.startswith("LONGRUN,")]
                log.write(f"{wl} {lab} rep{rep} exit={p.returncode} {time.time() - t:.0f}s {summ[-1] if summ else p.stderr[-300:]}\n")
                log.flush()
                print(wl, lab, rep, summ[-1] if summ else "NO SUMMARY " + p.stderr[-300:], flush=True)
    if "--nochecked" in sys.argv: return
    # one checked long run per workload (every 10th round history-checked, every compaction compared directly)
    for wl, wargs in WL.items():
        cmd = [BENCH, "--sys", "gtx-qc", "--label", wl + "-checked"] + f"{G} {wargs} --rounds {min(ROUNDS, 40)} {ARENA} {POL} --checkevery 10".split()
        p = subprocess.run(cmd, capture_output=True, text=True)
        for line in p.stdout.splitlines():
            if line.startswith(("ROUND,", "LONGRUN,")):
                raw.write(f"gtx-qc-checked,0,{line}\n")
        summ = [l for l in p.stdout.splitlines() if l.startswith("LONGRUN,")]
        log.write(f"{wl} checked exit={p.returncode} {summ[-1] if summ else p.stderr[-300:]}\n{p.stderr[-2000:]}\n")
        print(wl, "checked", summ[-1] if summ else "NO SUMMARY", flush=True)

if __name__ == "__main__":
    main()
