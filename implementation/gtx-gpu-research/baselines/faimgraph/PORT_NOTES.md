# faimGraph baseline: status (2026-11-10)

**Why faimGraph.** Of the four specialised structures the report lists as "paper-only", it is the one that can be
measured locally on this Windows machine. Each claim was checked at its source on 2026-11-10:
- **faimGraph** (`github.com/GPUPeople/faimGraph`): CMake, and the README says to "build using for example Visual
  Studio 2017" (CUDA 9.1, "gcc-6 or MVSC (VS17)"). It also has its own GPU memory manager with page reuse, a
  natural point of comparison for M4.
- **Hornet** (`github.com/hornet-gt/hornet`): CMake + GCC/Clang, "Ubuntu 16.04 or above suggested"; Windows not
  mentioned. It could only be built under WSL, which is not a matched environment.
- **SlabGraph**: the `owensgroup/SlabGraph` URL returns 404. The local Meerkat clone lacks its SlabHash submodule.
- **LPMA** (`pkumod/LPMA`): Linux/CMake (unchanged from the literature package).

**What exists.**
- `upstream/`: unmodified clone of GPUPeople/faimGraph, commit `d54a72ee54f8f6a614a32d6625b9f3caf56c59ea`
  (2021-04-23).
- `bench_faim.cu`: driver on the same `workload.hpp` streams as GPMA+ and GTX-GPU.
  - Initial graph is loaded through faimGraph's own DIMACS parser and `initializeMemory`.
  - Each batch is applied as one insertion batch, then one deletion batch.
  - Final live edge set is verified against a sequential replay.
  - Each update call is timed including faimGraph's internal host→device batch copy, with that copy also timed
    separately so it can be subtracted.
- `build_faim.bat`: nvcc build for sm_89 / CUDA 12.8 / MSVC 2022.

**Status: not built, not run.** Building and executing the freshly cloned third-party code was blocked by this
session's permission policy, and that was not worked around. To run it:

```bat
baselines\faimgraph\build_faim.bat
bin\faimgraph.exe --label snap-roadNet-CA-ins-K1 --reps 5 --batch 65536 --src file --graph data\snap\roadNet-CA.bin --initfrac 0.8 --N 1048576 --K 1 --pins 1
```

The upstream code targets CUDA 9.1 and sm_70. A CUDA 12.8 / sm_89 build may need porting fixes (deprecated
intrinsics, thrust/cub changes). Any such change must be recorded here, as was done for GPMA+.
