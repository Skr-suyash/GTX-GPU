# Method 4: outcome against the pre-registered criteria, and diagnosis (2026-11-10)

## Verdict: falsified on P1 and P2 (thresholds unchanged)

The criteria were written before any M4 performance run (`design/design.md` §7 M4). Measurements are from the main
matrix (`results/v2/raw.csv`, same session, same binary, median of 5; bytes from `results/v2/summary.csv`, in MiB).

| criterion | cell | result | verdict |
|---|---|---|---|
| P1: ≥ 40% fewer bytes than `gtx`, and ≤ `gtx-gs1` | identical-edge-64-K4 | 1486 → 721 MB (−51%); `gtx-gs1` 671 MB | **fail** (not ≤ gs1) |
| P1 | identical-edge-1024-K4 | 749 → 636 MB (−15%); `gtx-gs1` 480 MB | **fail** |
| P2: throughput ≥ 0.80× `gtx` on every main / SER cell | identical-edge-1024-K4 | 0.33× | **fail** |
| P2 | identical-edge-64-K4 | 0.66× | **fail** |
| P2 | all other 24 cells | 0.87×–1.04× | pass |
| P3: gate A–H, all four registered mutations rejected | — | gate all as expected; 3 of 4 registered mutations rejected, the per-lane generation-list mutation is not observable on this GPU (SIMT lockstep) | **fail as registered** (3/4) |
| P4: SER abort ratio reported | — | `results/v2/summary.md` | reported |

## Diagnosis (identical-edge-1024-K4, `bin/bench_next.exe` = campaign source + truncation fix, median of 3)

| variant | ms | MB | max generations | merges |
|---|---:|---:|---:|---:|
| default layout (`m4 0`) | 13.78 | 749 | 4 | – |
| announce + reclaimer only (`m4 1`) | 14.96 | 748 | 4 | – |
| hold-sizing, merges disabled (`m4 7`, `mergemin` = ∞) | 17.14 | 577 | **170** | 0 |
| M4 as registered (`m4 7`) | **64.01** | 634 | 9 | 23,784 |
| hold only for cap ≥ 64 (`holdmin 64`) | 30.96 | 645 | 3 | 15,496 |
| merge on the merged generations' garbage (`mergeoldgarb 1`) | 48.14 | 597 | 19 | 14,136 |
| both | 43.01 | 636 | 5 | 12,936 |
| **2× growth layout (`gtx-gs1`, no M4)** | **13.92** | **480** | 8 | – |

Reading:
1. **Hold-sizing alone** cuts bytes, but deepens hot vertices to 170 generations (+24% time).
2. **Merging bounds the depth**, but each merge re-copies the live and pending versions of a vertex. 84% of linked
   versions were kept on this cell, so merges cost far more than they save.
3. **The reclaimer lags.** 51.5K of 59.6K retired blocks were freed, but only 10.3K reused, so the bump high-water mark
   still grows.
4. **The plain 2× growth layout dominates every merge-based variant** on both time and memory. P1 requires
   ≤ `gtx-gs1` memory, so no variant in this family can pass. The single permitted exploratory revision was therefore
   not spent.

## What remains true and useful

- The announce/EBR, forwarding and merge machinery is correct under the gate (sections F–H, including forced-truncation
  merges F2) and the proof (`design/proof.md` §8). It stays in the code as `Cfg::m4` (off by default).
- The memory problem is a *layout* problem (measured, `layout_sweep.csv`). Recommendation per workload:
  - `growShift = 1` for uniform and contended/hot workloads: −20% to −55% bytes at ≤ 1% time.
  - `growShift = 3` for skewed live-insert workloads (hub, R-MAT, Zipf churn), where 2× growth costs 17–30% through
    generation depth.
- A merge-based method could only pay off if a merge copied little, i.e. if hot vertices held few live versions. It
  would need a trigger based on the garbage accumulated since the last merge relative to the copy size. That design
  is future work, not claimed.
- The truncated-merge DEL hole (found by review; L11) is fixed in the source and the current binaries. The
  campaign's `gtx-m4` performance rows were produced by the binary before that fix; only their checked rows are
  correctness evidence, and all of those passed.
