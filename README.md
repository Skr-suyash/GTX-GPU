# GTX-GPU: Contention-Aware Transactions for Dynamic Graph Updates on GPUs

Research Methodology project, Group 8, IIIT Allahabad (Suyash Kumar, Aryan Pandey, Vivek G Nair).

GTX-GPU adapts GTX, a transactional dynamic-graph system for CPUs, to GPU (SIMT) execution: versioned edge records,
block generations instead of copying, one atomic per warp, lock-free per-edge check-then-swap, snapshot readers,
quiescent compaction for garbage collection, and a paper proof of snapshot isolation and serializability.

| Path | Contents |
|---|---|
| `implementation/gtx-gpu-research/endsem_report/GTX-GPU_EndSem_Report_Group8_IIITA.pdf` | end-semester report (LaTeX source alongside) |
| `ppt/RM Presentation EndSem.pptx` / `.pdf` | end-semester slides |
| `implementation/gtx-gpu-research/midterm_report/` | mid-term report |
| `implementation/gtx-gpu-research/` | CUDA engine, baselines, benchmarks, results, proof, technical report (see its `README.md`) |
| `papers/`, `implementation/gtx-gpu-research/literature/` | literature |
| `ppt/`, `slides/` | earlier presentation drafts |
