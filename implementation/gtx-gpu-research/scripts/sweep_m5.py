"""M5 policy sweep (run AFTER the registered criteria; the chosen policy is disclosed as post-probe tuning).

Writes results/m5/sweep_raw.csv (ROUND/LONGRUN lines prefixed by config,rep) and results/m5/sweep.log.
usage: python -P scripts/sweep_m5.py [--rounds 20] [--reps 1]
"""
import os, subprocess, sys, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCH = os.path.join(ROOT, "bin", "bench.exe")
OUT = os.path.join(ROOT, "results", "m5")
def arg(k, d): return type(d)(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d
ROUNDS, REPS = arg("--rounds", 20), arg("--reps", 1)
G = "--V 1048576 --init 4000000 --K 4 --perround 262144 --fifodel 1"
WL = {"uniform-churn-K4": "--pins .5 --pdel .5", "zipf-churn-K4": "--src zipf --zipf 1.0 --pins .5 --pdel .5"}
CFGS = [
    ("gtx", "gtx", "--arena 20000000 --desccap 20000000"),
    ("gtx-big60M", "gtx", "--arena 60000000 --desccap 60000000"),
    ("qc-trig-gs3-s0", "gtx-qc", "--arena 20000000 --desccap 20000000"),
    ("qc-trig-gs1-s100", "gtx-qc", "--arena 20000000 --desccap 20000000 --growshift 1 --qcslack 100"),
    ("qc-ev1-gs3-s0", "gtx-qc", "--arena 20000000 --desccap 20000000 --qcevery 1"),
    ("qc-ev1-gs3-s100", "gtx-qc", "--arena 20000000 --desccap 20000000 --qcevery 1 --qcslack 100"),
    ("qc-ev1-gs1-s100", "gtx-qc", "--arena 20000000 --desccap 20000000 --qcevery 1 --growshift 1 --qcslack 100"),
    ("qc-ev2-gs1-s100", "gtx-qc", "--arena 20000000 --desccap 20000000 --qcevery 2 --growshift 1 --qcslack 100"),
    ("qc-ev4-gs1-s100", "gtx-qc", "--arena 20000000 --desccap 20000000 --qcevery 4 --growshift 1 --qcslack 100"),
]
os.makedirs(OUT, exist_ok=True)
raw = open(os.path.join(OUT, "sweep_raw.csv"), "a", encoding="utf-8")
log = open(os.path.join(OUT, "sweep.log"), "a", encoding="utf-8")
log.write(f"\n# {time.strftime('%Y-%m-%d %H:%M:%S')} rounds={ROUNDS} reps={REPS} bench={time.ctime(os.path.getmtime(BENCH))}\n")
for wl, wargs in WL.items():
    for lab, sysn, extra in CFGS:
        for rep in range(REPS):
            cmd = [BENCH, "--sys", sysn, "--label", wl] + f"{G} {wargs} --rounds {ROUNDS} {extra} --seed {1 + rep}".split()
            p = subprocess.run(cmd, capture_output=True, text=True)
            for line in p.stdout.splitlines():
                if line.startswith(("ROUND,", "LONGRUN,")):
                    raw.write(f"{lab},{rep},{line}\n")
            raw.flush()
            s = [l for l in p.stdout.splitlines() if l.startswith("LONGRUN,")]
            msg = f"{wl} {lab} rep{rep} exit={p.returncode} {s[-1] if s else p.stderr[-300:]}"
            log.write(msg + "\n"); log.flush(); print(msg, flush=True)
