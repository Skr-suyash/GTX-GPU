# gtx-gpu-research — GTX-inspired GPU synchronization for atomic multi-edge transactions

A GPU adaptation of GTX (versioned edge deltas, destination-hashed delta chains, transaction descriptors, epoch group
commit) for **atomic multi-edge transactions with concurrent snapshot readers** on a dynamic graph, with a
history checker that validates every run, matched baselines, and a verified literature package.
Hardware: RTX 4060 Laptop GPU (sm_89), CUDA 12.8, Windows 11.

| path | contents |
|---|---|
| `report.md` | **results and conclusions** (read first) |
| `literature/literature_review.md`, `literature/source_manifest.csv` | verified literature review; every number traced to a page of a downloaded primary PDF (`literature/pdfs`, `literature/text`) |
| `audit/prototype_audit.md` | audit of the earlier prototype (`../gpu-stm-dynamic-graphs`) with concrete counterexample histories; GPMA baseline audit |
| `design/design.md` | data layout, operation semantics, pseudocode, invariants, memory-order requirements, progress assumptions, cost model, hypotheses + falsification criteria for methods M1–M4 |
| `benchmarks/benchmark_inventory.{md,csv}` | literature measurements with provenance (paper/version, figure/table, hardware, dataset, mix, batch, consistency, timing boundary, statistic, exact vs digitized vs reproduced) and the local benchmark matrix |
| `protocol/reproduction_protocol.md` | environment pins, build, timing boundaries, statistics, correctness gate, workloads, ranked experiment sequence, threats to validity |
| `src/gtxg.cuh` | GTX-GPU engine (SI and SER, ablation switches) |
| `src/baselines.cuh` | 2PL, TL2 word-STM (with/without degree word), non-transactional CAS — shared storage layout |
| `src/checker.hpp` | history checker C1–C5 (read rule, observation identity, write-write, final state, serialization graph) |
| `src/test_gtx.cu` | correctness suite (adversarial histories, write-skew probe, mutation tests, exhaustion) |
| `src/bench.cu`, `scripts/run_matrix.py`, `scripts/summarize.py` | benchmark driver, resumable sweep, statistics |
| `baselines/gpma/` | GPMA+ harness on identical streams; Windows port vs pristine upstream (CDP1); `PORT_NOTES.md` |
| `results/` | 2026-09 campaign: raw CSV, summaries, speedups with bootstrap CIs, defect log |
| `results/v2/` | **2026-11 campaign (current numbers):** same matrix re-measured with the final binary, plus Method 4, the 2× layout row, SNAP graphs, batch-size sweep vs GPMA+, layout sweep, uncontended-gap bound, correctness suite A–H |
| `design/proof.md` | paper proof of SI and serializability (L1–L10, Theorems 1–5) and of Method 4 (L11–L14), each lemma mapped to code and tests |
| `scripts/campaign_v2.py` | runs the whole 2026-11 measurement campaign in order (correctness first) |
| `scripts/snap2bin.py`, `data/snap/` | SNAP edge lists → binary edge caches (`--src file --graph ...`, sliding-window streams) |
| `baselines/faimgraph/` | faimGraph driver + build script on identical streams (**not built**: see its `PORT_NOTES.md`; clone `github.com/GPUPeople/faimGraph` at `d54a72e` into `upstream/` to build) |
| `endsem_report/` | **end-semester report** (`GTX-GPU_EndSem_Report_Group8_IIITA.pdf`, LaTeX source `main.tex`) |
| `midterm_report/` | mid-term report (PDF + LaTeX source) |
| `paper/` | technical report and presenter guide; `paper/sept2026/` = the September snapshot |
| `../../ppt/RM Presentation EndSem.{pptx,pdf}` | end-semester slides |

Not in the repository: `data/snap/` (SNAP graphs, ~680 MB; download from snap.stanford.edu and convert with
`scripts/snap2bin.py`), `bin/` (build output) and `endsem_report/fonts/` (the report uses Consolas and Nirmala UI;
copy them from `C:\Windows\Fonts` into `endsem_report/fonts/`, then build with `tectonic main.tex`).

Quick start: `build.bat test_gtx && bin\test_gtx.exe full` (correctness gate, sections A–H), then
`build.bat bench && python scripts\campaign_v2.py && python scripts\summarize.py --dir results\v2`.
Builds need MSVC (VS 2022 Community **or Build Tools** with the C++ workload) and CUDA 12.8.

Engine switches added in 2026-11:
- `--m4 {1,3,7}`: Method 4. `--sys gtx-m4` = `--m4 7`.
- `--sys gtx-gs1`: 2× growth layout.
- `--bulk 1`: degree-sized bulk loader.
- `--batch B`: one launch per B transactions.
- `--membreak 1`: per-category memory breakdown.
