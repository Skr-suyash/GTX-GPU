"""2026-11 re-measurement campaign: every number in report.md section "v2" comes from this run, one binary, one session.
Resumable (each step skips (label, sys) pairs already in its output). Order: correctness first, then performance.
usage: python scripts/campaign_v2.py [--only STEP]"""
import os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable
OUT = os.path.join(ROOT, "results", "v2")
RAW = os.path.join(OUT, "raw.csv")
GPMA = os.path.join(OUT, "gpma_raw.csv")

STEPS = [
    ("check", [PY, "scripts/run_matrix.py", "check", "--reps", "1", "--timeout", "600", "--out", RAW]),
    ("main", [PY, "scripts/run_matrix.py", "main", "--reps", "5", "--timeout", "90", "--out", RAW]),
    ("ser", [PY, "scripts/run_matrix.py", "ser", "--reps", "5", "--timeout", "90", "--out", RAW]),
    ("fairro", [PY, "scripts/run_matrix.py", "fairro", "--reps", "5", "--timeout", "90", "--out", RAW]),
    ("gpmamatch", [PY, "scripts/run_matrix.py", "gpmamatch", "--reps", "5", "--timeout", "90", "--out", RAW]),
    ("gpma", [PY, "scripts/run_gpma.py", "--reps", "5", "--out", GPMA]),
    ("snap", [PY, "scripts/run_matrix.py", "snap", "--reps", "5", "--timeout", "900", "--out", RAW]),
    ("gpma-snap", [PY, "scripts/run_gpma.py", "--snap", "--reps", "5", "--timeout", "900", "--out", GPMA]),
    ("sweep", [PY, "scripts/run_matrix.py", "sweep", "--reps", "5", "--timeout", "900", "--out", RAW]),
    ("gpma-sweep", [PY, "scripts/run_gpma.py", "--sweep", "--reps", "5", "--timeout", "900", "--out", GPMA]),
]


def main():
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    os.makedirs(OUT, exist_ok=True)
    log = open(os.path.join(OUT, "campaign.log"), "a", encoding="utf-8")
    for name, cmd in STEPS:
        if only and name != only:
            continue
        t0 = time.time()
        log.write(f"== {name} start {time.strftime('%Y-%m-%d %H:%M:%S')}\n"); log.flush()
        p = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        log.write(f"== {name} exit={p.returncode} {time.time() - t0:.0f}s\n"); log.flush()
    log.close()


if __name__ == "__main__":
    main()
