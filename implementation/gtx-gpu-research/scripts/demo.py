"""Live-demo helper: runs bin/bench.exe for a named slide scenario and prints a readable table.

usage: python scripts/demo.py <scenario> [--reps N]
       python scripts/demo.py list
"""
import os, statistics, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCH = os.path.join(ROOT, "bin", "bench.exe")
G = "--V 1048576 --init 4000000"   # 2^20 vertices, 4M initial edges (same as the slides)
NAMES = {"gtx": "GTX-GPU (ours)", "gtx-cons": "GTX rules"}

# name: (description, bench arguments, systems, slide value to expect)
SCEN = {
    "k32-uniform": ("Slide 13: uniform inserts, K=32", f"{G} --N 32768 --K 32 --pins 1", ["gtx", "gtx-cons"],
                    "ours ~141 M inserts/s, 0% aborts; GTX rules ~79 M/s, ~45% aborts (1.8x)"),
    "k32-hub": ("Slide 13: 50% hub inserts, K=32", f"{G} --N 32768 --K 32 --src hub --hub 0.5 --pins 1", ["gtx", "gtx-cons"],
                "ours ~74 M/s, ~26% aborts; GTX rules ~56 M/s, ~43% aborts (1.3x)"),
    "k8-uniform": ("Slide 13: uniform inserts, K=8", f"{G} --N 131072 --K 8 --pins 1", ["gtx", "gtx-cons"],
                   "ours ~165 M/s, 0% aborts; GTX rules ~148 M/s, ~8.5% aborts"),
    "k8-hub": ("Slide 13: 50% hub inserts, K=8", f"{G} --N 131072 --K 8 --src hub --hub 0.5 --pins 1", ["gtx", "gtx-cons"],
               "ours ~127 M/s, ~2.7% aborts; GTX rules ~100 M/s, ~6.5% aborts"),
    "k1-uniform": ("Slide 13: uniform inserts, K=1", f"{G} --N 1048576 --K 1 --pins 1", ["gtx", "gtx-cons"],
                   "ours ~181 M/s; GTX rules ~175 M/s"),
    "mixed-uniform": ("Slide 14: mixed 40/30/30 insert/delete/read, K=4, uniform",
                      f"{G} --N 262144 --K 4 --pins .4 --pdel .3 --pread .3", ["gtx"], "~50.9 M txn/s, ~140 M edge changes/s, ~1.1% aborts"),
    "mixed-hub": ("Slide 14: mixed, K=4, 50% hub",
                  f"{G} --N 262144 --K 4 --src hub --hub 0.5 --pins .4 --pdel .3 --pread .3", ["gtx"], "~50.5 M txn/s, ~105 M edge changes/s, ~1.9% aborts"),
    "mixed-zipf": ("Slide 14: mixed, K=4, Zipf",
                   f"{G} --N 262144 --K 4 --src zipf --zipf 1.0 --pins .4 --pdel .3 --pread .3", ["gtx"], "~34.8 M txn/s, ~94 M edge changes/s, ~1.1% aborts"),
    "churn-uniform": ("Slide 14 box: insert/delete churn, K=1, uniform", f"{G} --N 1048576 --K 1 --pins .5 --pdel .5", ["gtx"], "~156 M edge changes/s"),
    "churn-rmat": ("Slide 14 box: insert/delete churn, K=1, R-MAT", f"{G} --N 1048576 --K 1 --src rmat --pins .5 --pdel .5", ["gtx"], "~144 M edge changes/s"),
    "checked": ("Correctness: small mixed run verified by the history checker (snapshot isolation)",
                "--V 65536 --N 65536 --K 4 --init 200000 --src zipf --zipf 1.0 --pins .4 --pdel .3 --pread .2 --ro .2 --roscan .1 --check 1",
                ["gtx", "gtx-cons"], "check column = PASS"),
}


def run(name, reps):
    desc, args, systems, expect = SCEN[name]
    print(f"\n{desc}")
    print(f"  expected on the RTX 4060: {expect}")
    print(f"  {'system':<16}{'kernel ms':>10}{'commits':>10}{'aborts':>9}{'abort %':>9}{'M txn/s':>9}{'M edges/s':>11}  check")
    for s in systems:
        cmd = [BENCH, "--sys", s, "--label", name, "--reps", str(reps)] + args.split()
        p = subprocess.run(cmd, capture_output=True, text=True)
        rows = [l.split(",") for l in p.stdout.splitlines() if l.startswith("RESULT,")]
        if not rows:
            print(f"  {NAMES.get(s, s):<16} FAILED (exit {p.returncode}) {p.stderr.strip()[-200:]}")
            continue
        chk = next((x[30] for x in rows if x[30] != "-"), "-")  # the checker runs on the LAST repetition only
        rows.sort(key=lambda r: float(r[4]))
        r = rows[len(rows) // 2]  # median repetition
        commits, aborts = float(r[5]), float(r[6])
        flag = "" if r[31].strip() == "0" else f"  FLAG={r[31].strip()}"
        print(f"  {NAMES.get(s, s):<16}{float(r[4]):>10.2f}{int(commits):>10}{int(aborts):>9}{100 * aborts / max(1, commits + aborts):>9.1f}"
              f"{float(r[10]) / 1e6:>9.1f}{float(r[11]) / 1e6:>11.1f}  {chk}{flag}")
        print(f"    command: bin\\bench.exe --sys {s} --label {name} --reps {reps} {args}")


def main():
    if len(sys.argv) < 2 or sys.argv[1] == "list":
        for k, v in SCEN.items():
            print(f"  {k:<14} {v[0]}")
        return
    reps = int(sys.argv[sys.argv.index("--reps") + 1]) if "--reps" in sys.argv else 3
    names = list(SCEN) if sys.argv[1] == "all" else [sys.argv[1]]
    print("NOTE: 'expected' values are the 2026-09 slide numbers. On this laptop in 2026-11 every kernel runs\n"
          "      ~1.3-1.7x faster (system change, see protocol); the GTX-GPU vs 'GTX rules' ratios and abort rates are unchanged.")
    for n in names:
        if n not in SCEN:
            print("unknown scenario:", n, "(try: python scripts\\demo.py list)")
            return
        run(n, reps)


if __name__ == "__main__":
    main()
