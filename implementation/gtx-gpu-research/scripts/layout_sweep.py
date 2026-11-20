"""Layout sweep (no new engine code): growShift x minCap x chRatio (+ prewalk on hot cells) for GTX-GPU.
Records median kernel ms over --reps, bytes (bump high-water mark) and the MEM breakdown line of the last rep.
Output: results/v2/layout_sweep.csv (resumable)."""
import csv, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCH = os.path.join(ROOT, "bin", "bench.exe")
V = 1 << 20
CELLS = {
    "uniform-ins-K1": f"--V {V} --N {1 << 20} --K 1 --init 4000000 --pins 1",
    "hub50-ins-K8": f"--V {V} --N {1 << 17} --K 8 --init 4000000 --src hub --hub 0.5 --pins 1",
    "rmat-readers90-K4": f"--V {V} --N {1 << 18} --K 4 --init 4000000 --src rmat --pins .5 --pdel .5 --ro 0.9 --roscan 0.1",
    "identical-edge-64-K4": f"--V {V} --N {1 << 18} --K 4 --init 4000000 --hot 64 --hotfrac 0.5 --pins .5 --pdel .5",
    "identical-edge-1024-K4": f"--V {V} --N {1 << 18} --K 4 --init 4000000 --hot 1024 --hotfrac 0.5 --pins .5 --pdel .5",
}


FIELDS = ["cell", "cfg", "median_ms", "aborts", "giveup", "flag", "bytes_MB", "total_MB", "slots_MB", "unwritten_MB",
          "void_MB", "aborted_MB", "pending_MB", "reservedEmpty_MB", "liveIns_MB", "deadIns_MB", "del_MB", "orphan_MB",
          "blocks_MB", "heads_MB", "desc_MB", "vtx_MB", "liveEdges", "gens", "maxGens", "vertsWithBlocks",
          "deadOldGens", "deadOld_MB", "liveOldGens", "liveOld_MB", "liveOldKeepSlots"]


def configs():
    for gs in (3, 2, 1):
        for mc in (8, 4):
            for cr in (1, 2, 4):
                yield f"gs{gs}-mc{mc}-cr{cr}", f"--growshift {gs} --mincap {mc} --chratio {cr}"
    yield "gs3-mc8-cr1-prewalk", "--growshift 3 --mincap 8 --chratio 1 --prewalk 1"
    yield "gs1-mc4-cr2-prewalk", "--growshift 1 --mincap 4 --chratio 2 --prewalk 1"


def main():
    reps = int(sys.argv[sys.argv.index("--reps") + 1]) if "--reps" in sys.argv else 3
    out = os.path.join(ROOT, "results", "v2", "layout_sweep.csv")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    done = set()
    if os.path.exists(out):
        with open(out, newline="") as f:
            done = {(r["cell"], r["cfg"]) for r in csv.DictReader(f)}
    new = not os.path.exists(out)
    with open(out, "a", newline="") as f:
        w = None
        for cell, cargs in CELLS.items():
            for name, args in configs():
                if (cell, name) in done or ("prewalk" in name and "identical" not in cell and "hub" not in cell):
                    continue
                cmd = [BENCH, "--sys", "gtx", "--label", cell, "--reps", str(reps), "--membreak", "1"] + cargs.split() + args.split()
                p = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
                res = [l.split(",") for l in p.stdout.splitlines() if l.startswith("RESULT,")]
                mem = [l for l in p.stdout.splitlines() if l.startswith("MEM,")]
                # RESULT,label,sys,rep,ms,commits,aborts,giveup,...,bytes(index 17),...,flag(last)
                ms = sorted(float(r[4]) for r in res)
                row = {"cell": cell, "cfg": name, "median_ms": ms[len(ms) // 2] if ms else "ERR",
                       "aborts": res[0][6] if res else "", "giveup": res[0][7] if res else "",
                       "flag": res[-1][-1].strip() if res else p.returncode,
                       "bytes_MB": round(int(res[0][17]) / 2**20, 1) if res else ""}
                if mem:
                    for kv in mem[0].split(",")[2:]:
                        k, v = kv.split("=")
                        row[k] = v
                if w is None:
                    w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
                    if new:
                        w.writeheader()
                w.writerow(row)
                f.flush()
                print(f"{cell:24s} {name:22s} ms={row['median_ms']} MB={row.get('total_MB')} unwritten={row.get('unwritten_MB')} "
                      f"maxGens={row.get('maxGens')} deadOld={row.get('deadOld_MB')} flag={row['flag']}", flush=True)


if __name__ == "__main__":
    main()
