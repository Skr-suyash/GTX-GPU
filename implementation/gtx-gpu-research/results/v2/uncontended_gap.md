# Uncontended gap to 2PL: upper bound from profiling ablations (2026-11-10)

Pre-registered question (advisor, item 5): can any restructuring of the write path close the uniform small-transaction
gap to 2PL? Method: remove whole cost components with the profiling switches. These runs are **not** valid
executions; they only bound what an optimisation of that component could ever buy. Same binary, median of 5 runs,
V = 2^20, 4M initial edges.

| configuration (ms, median of 5) | uniform-ins-K1 | uniform-churn-K4 |
|---|---:|---:|
| 2PL vertex locks | 2.204 | 2.078 |
| GTX-GPU | 3.907 | 4.715 |
| GTX-GPU, bulk-loaded initial graph (degree-sized first generation) | 3.792 | 4.581 |
| GTX-GPU without result writes (`dbg 2`) | 3.824 | 4.524 |
| GTX-GPU without commit (`dbg 4`) | 3.909 | 4.710 |
| GTX-GPU without install walk + CAS + delta write (`dbg 1`) | 2.656 | n/a (deletes need the walk) |
| GTX-GPU without all three (`dbg 7`) | 2.563 | n/a |

In-kernel cycle profile for uniform-ins-K1: op loop 83% (install 23%), begin 6%, commit 10%, stamp 0.5%.

**Conclusion (negative result).**
- Removing the versioned install entirely, which is impossible while keeping versions, still leaves GTX-GPU 1.16–1.21×
  slower than 2PL on uniform-ins-K1. The transaction skeleton is slower than 2PL's entire run: descriptor allocation,
  per-attempt bookkeeping, epoch registration, the attempt loop and the advancer.
- A slimmer delta (16 B instead of 32 B) could recover part of the ~1.25 ms install cost, but it cannot close the gap.
  It was therefore not built.
- The write path cannot close the gap: it comes from the multi-version transaction skeleton that snapshot readers need. It is reported as a loss, not engineered
  away.
