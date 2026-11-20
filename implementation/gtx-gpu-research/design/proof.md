# GTX-GPU: correctness proof (paper proof)

This document proves that every history produced by the GTX-GPU engine (`src/gtxg.cuh`) satisfies **snapshot isolation**
in SI mode (`Cfg::ser = 0`) and **serializability** in SER mode (`Cfg::ser = 1`), for the transaction model of
`design/design.md` §2. It is a hand proof against the CUDA/PTX memory model, not a machine-checked one. Every lemma names
the code site it depends on and the test or mutation that exercises it (§7). Section §8 extends the proof to block
consolidation and reclamation (Method M4), and §9 to quiescent compaction (Method M5).

**Configurations covered.** All combinations of:
- `ser ∈ {0, 1}`, `coop ∈ {0, 1}`, `dstconf ∈ {0, 1}`, `coopScan ∈ {0, 1}`, `prewalk ∈ {0, 1}`;
- `stamp ∈ {0, 1}` (stamps only cache the epoch that resolution through `desc` yields);
- any `minCap`, `chRatio` and `growShift` (power-of-two capacities and head counts);
- `bulk ∈ {0, 1}`: the bulk loader produces a state that loader transactions could have produced, with one committed
  loader transaction at epoch 1.

**Not covered.** The deliberately broken switches: `mut ≠ 0`, `dbg & 8|16|32|64`, and the profiling short-cuts
`dbg & 1|2|4`.

The pre-walk is a read-only walk that only *filters*. A write it does not filter goes through the full
reserve/walk/CAS path. A write it does filter is a no-op or abort decided from a version visible at `rts`, which is
exactly the decision Theorem 2 would give. In SER mode, a filtered no-op is recorded as a read and validated.

Assumptions for §1–§6 (the base protocol, `Cfg::m4 = 0`):

* **A1 (no reuse).** Delta slots, chain heads, block records and descriptors are never reused. Descriptor ids are fresh
  per attempt (`warpAggInc(c.txTop)`), and arena memory is bump-allocated (`allocBlock`). §8 drops A1 for M4.
* **A2 (memory model).** The PTX memory model (scoped, morally-strong operations; release/acquire patterns built from
  fences plus relaxed operations; causality order is transitive). All protocol atomics use device scope
  (`cuda::atomic_ref<…, thread_scope_device>`). The CUDA C++ Programming Guide (*Warp Synchronization Functions*)
  states: "Executing `__syncwarp()` guarantees memory ordering among threads participating in the barrier." For the
  warp vote functions it states: "These intrinsics do not imply a memory barrier. They do not guarantee any memory
  ordering." The proof therefore assumes ordering only from `__syncwarp`, never from `__ballot_sync` or `__shfl_sync`.
  (Guide text as quoted in NVIDIA developer forum thread 279421; the extension of that guarantee to *global* memory
  combined with device-scope atomics is the PTX causality-order reading of the same statement.)
* **A3 (no overflow).** Epochs fit in 32 bits (the high half of `E`). Per-epoch registration counts are below 2^32. The
  arena fits 2^31 − 1 slots (`NILD`).
* **A4 (fixed vertex set, single kernel run or quiescent boundary between runs).** `Store::publishAll` runs only between
  kernel launches, when no transaction is in flight.

Notation. `hb` is happens-before. `mo(x)` is the modification (coherence) order of location `x`. For an attempt T, `rts(T)` is the
frontier it loaded and `e(T)` its registration epoch. `desc[T]` is its descriptor word: 0 ACTIVE, 1 ABORTED, `(e<<2)|2`
COMMITTED(e). A *version* of key k = (u, v) is a non-VOID delta with `dstop.dst = v` that was linked into a chain of a
generation of u.

---------------------------------------------------------------------------------------------------------------------

## 1. Descriptors and epochs

**L1 (descriptor finality).** Each attempt writes its descriptor at most once with a final value. Every load of
`desc[T]` returns 0 or that final value.
*Proof.* `desc[T]` is zero-initialised (`Store::reset`), and T is the only writer (ids are fresh, A1). The possible stores are:
- line `desc := 1` for an alive read-only attempt;
- the registered path `desc := alive ? COMMITTED(e) : 1`;
- the abort path `desc := 1` for `act && !alive`.

The registered and abort paths can both execute only when a registered SER writer fails validation. Both then store
1. No path stores 0. ∎

**L2 (registration is exact).** Let `close(e)` be the advancer's `E.exchange((e+1)<<32)` that returns `reg(e)`.
Exactly `reg(e)` attempts register in epoch e, and each of their registration RMWs precedes `close(e)` in mo(E).
*Proof.* Only the advancer changes the high half of `E`. It reads `e = E>>32` and then exchanges. Between the two, only
registrations (`fetch_add` of the low half) can intervene, so the exchange returns high half e and the sum of the
registrations since `close(e−1)`. Every RMW on `E` reads the immediately preceding value in mo(E). A registration
therefore receives epoch e if and only if it lies between `close(e−1)` and `close(e)`. ∎

**L3 (frontier safety, invariant I3).** If a transaction's acquire load of `frontier` returns r, then for every attempt
T with `e(T) ≤ r`, T's final descriptor store and every store T issued before it happen-before that load.
*Proof.* For a registered warp, the order is:
1. Each registered lane runs `__threadfence(); desc[T].store(final, relaxed)`.
2. `__syncwarp()`.
3. The leader runs `__threadfence(); inflight[e&1].fetch_add(popc(reg), relaxed)`.

The advancer spins on an acquire load of `inflight[e&1]` until it equals `reg(e)` (L2). It then stores
`frontier := e` with release.

Fence plus relaxed RMW, read by an acquire load, is a release/acquire pattern. Every RMW to `inflight[e&1]` continues
the release sequence, so each registered warp's stores happen-before the advancer's exit from the spin. The advancer
resets `inflight[e&1]` to 0 only after epoch e−2 is complete. That reset is ordered before `close(e−1)` and `close(e)`
in program order, and every registration of e reads from or after `close(e−1)` (acq_rel). Hence no stale count from e−2
is present and no count from e+2 can arrive early.

The frontier store is release and the reader's load is acquire, and frontier values are monotone. ∎

**L4 (fresh epochs).** For every registered attempt T, `e(T) > rts(T)`.
*Proof.* T's frontier load returned r, which was stored by the advancer after `close(r)`, which opened epoch r+1.
The leader's registration RMW is ordered after every registering lane's frontier load: the `__syncwarp()` placed before
the RMW in `registerEpoch` puts that lane's load before the RMW (A2). The load in turn follows `close(r)` through the
frontier release/acquire. So the RMW is after `close(r)` in mo(E) and returns epoch ≥ r+1. ∎

This is the first of the two places where `__syncwarp` matters. Before 2026-11-10 the code relied on
`__ballot_sync`/`__shfl_sync`, which do not order memory under A2. The defect is latent and was never observed.
`Cfg::dbg & 64` restores the old code for comparison.

**L5 (the visible/invisible split is stable).** Fix a reader R with snapshot r and a creator T ≠ R. Each evaluation
of `createVis`/`resolveTx` by R returns `V_VIS` if and only if T commits with `e(T) ≤ r`. The *invisible* answers can
change between evaluations: `V_ACTIVE` may later read as `V_ABORTED` or `V_LATE`. The protocol never relies on which
invisible answer it gets, except that writers abort on `V_ACTIVE`/`V_LATE`, which is conservative. The set of versions
R treats as visible is therefore exactly {own} ∪ {versions of attempts committed at an epoch ≤ r}, at every point
of R's execution.
*Proof.*
- If T commits at e ≤ r, then by L3 T's descriptor (and its `cts` stamp, if already written) happen-before R's
  frontier load. Every later load by R returns COMMITTED(e) (coherence) or the stamp e. A stamp is written only after
  T's commit (program order) and only with T's own epoch.
- If T is not committed at an epoch ≤ r, R can never read COMMITTED(e ≤ r). Either T commits later at some e, and then
  e > r by L2, since an epoch ≤ r was closed before frontier r was published; or T aborts. A loaded `cts` of 0 falls
  back to the descriptor.

By L1 nothing else is possible. ∎

**Read-only commits.** An alive attempt without effective writes stores `desc := 1`, not COMMITTED(rts). If it read
COMMITTED(rts), the slots it voided would be "committed in the past" for concurrent scanners that may still load a
pre-VOID opcode (defect D7). With `desc = 1`, every slot such an attempt ever touched is invisible to everyone (L5).

## 2. Write-write exclusion and version order (invariants I1, I2)

**L6 (one chain per key per generation; sealing).** Within generation g of u, all versions of key (u, v) are linked
into the single chain head `H[headSlot(g, v)]` (deterministic hash). A writer that installs into generation g+j (j ≥ 1)
first applies `fetch_or(SEAL)` to the head of v in every older generation it walks (`walkGens(seal = true)`), before
walking it. After that RMW, no CAS can link a delta into that head. The head CAS compares the full word, so its
expected value carries no SEAL bit and fails. The failing writer voids its slot and re-reserves (`IN_RESEAL`).

**L7 (validate-then-CAS on the observed head).** If writer T links delta d into head h with a CAS that expected value
h0, then T has walked every delta reachable from h0 in that chain. If the CAS first failed and observed h1, T has
also walked the prefix h1 … h0 before retrying. Hence T walked every delta that was linked into h before d.
*Proof.* The CAS succeeds only if the head still equals the value T walked from (or last re-walked to). Every delta
linked earlier is reachable from that value through `prev` links. `prev` is fixed before linking, and slots are never
relinked (I6). The head CAS is acq_rel, so the contents of each linked delta, written before its own linking CAS,
are visible to T's walk. ∎

**Theorem 1 (version order, first-updater-wins, invariant I1).** Let `W_k` be the attempts that linked a non-VOID
version of key k and later committed. The versions of `W_k`, ordered by (generation, chain position), are totally
ordered. For consecutive committed versions by T1 then T2: `e(T1) ≤ rts(T2) < e(T2)`.
*Proof.* Take two committed versions d1 (by T1) and d2 (by T2) of key k, where d2 was linked later. There are three
cases:
- **Same generation.** By L7, T2 walked d1 before linking d2.
- **d1 in an older generation than d2.** By L6, T2 sealed d1's head and walked it. d1 was linked before the seal,
  otherwise its CAS would have failed. So T2 saw d1.
- **d1 in a newer generation than d2.** Impossible. T1 sealed d2's head before walking it, so d2 was linked before
  the seal and T1 walked d2. Hence d2 precedes d1 in link order, contradicting the choice of d2 as the later version.

So T2's writer walk encountered d1, or encountered a newer committed version of k first, which by induction is itself
preceded by d1. The writer rules (`walkChain` with `writer = true`) skip aborted versions. They abort on `V_ACTIVE`
(pending) and on `V_LATE` (committed after `rts`). They stop at the first remaining version. Since T2 did not abort,
the newest non-aborted version it found was visible to it: by L5, `e(found) ≤ rts(T2)`. By L4, `rts(T2) < e(T2)`.

Commit epochs therefore increase strictly along the version order, and no committed writer of k has its epoch in
`(rts(T2), e(T2))`. That is SI's first-committer-wins, checker C3, including "no two writers share an epoch". ∎

**Corollary 1 (newest non-aborted = newest visible for writers).** When a writer proceeds to link, the version it found
is the newest version visible at its `rts`, overlaid by its own versions. A foreign non-aborted version linked after one
of T's own versions would have required that writer to pass T's pending version, which aborts it with `WW_PENDING`.

## 3. Point reads and write effects (checker C1, C2)

Let `S(r)` be the model state: the initial graph with the net writes of every committed transaction with `cts ≤ r`
applied in cts order (`checker.hpp`).

**Theorem 2 (point reads).** A `lookup(u, v)`, or the no-op/effective decision of an `insert`/`delete`, by R with
snapshot r returns `S(r)[k]` overlaid with R's own earlier writes, and the observed delta is that version's delta.
*Proof.* The read walks the chains of v from `vcur[u]` newest-first and returns the first version that is own or
visible (L5). By Theorem 1, committed versions are ordered by epoch along the chain order, so the first version with
`e ≤ r` is the one with the largest `e ≤ r`, which is `S(r)[k]`. Own versions come before all foreign non-aborted
versions (Corollary 1). The reachability of every generation that holds a version with `e ≤ r` is Lemma 8. For writers
the decision uses the same version (Corollary 1). ∎

## 4. Adjacency scans (checker C1 for scans)

**L8 (generation reachability, invariant I2 and defect D8).** If version d of vertex u lives in generation g and its
creator T commits with `e(T) ≤ r`, then R's scan or walk from `vcur[u]` reaches g. If g is still the reservation
generation in `vfill[u]`, the fill bound R reads covers d's slot.
*Proof.*
1. The grower of g wrote `B[g]`, then fenced, then stored `vcur[u] := g` (release), then `vfill[u] := (g<<32)|0`
   (release).
2. T's reservation `fetch_add` on `vfill[u]` is **acq_rel**. It reads from the release sequence of the grower's store,
   so the grower's `vcur` store happens-before T's reservation.
3. T's reservation happens-before T's descriptor store (program order plus the commit fences), which happens-before
   R's frontier load (L3).
4. By coherence, R's later load of `vcur[u]` returns g or a generation created later. Later generations reach g
   through `prevGen` links that were written before publication.
5. For the fill bound: T's RMW on `vfill[u]` happens-before R's load of `vfill[u]`, so R reads T's value or a later
   one. If the generation half is still g, the fill half exceeds d's slot. Otherwise R treats g as full (`cap`).

With a relaxed reservation (`dbg & 32`), step 2 fails. That is exactly defect D8, found by the checker. ∎

**L9 (invalidation word).** For an INS version x of key k:
- `x.its` is written only by transactions that linked the version immediately after x. Such a version is necessarily a
  DEL, because an INS of a present key is a no-op.
- The value R reads from `x.its` decides "x is superseded for R" exactly when the next version after x is own or
  visible to R.

*Proof.*
- **Who writes it.** A deleter D writes `TAG|D` only after its DEL was linked with x as the version it found
  (`install` returned `IN_EFF` with `o.cur = x`). After commit, D replaces the tag with `e(D)` (stamp).
- **Several candidate deleters.** Several deleters can successively find x only if each earlier one's DEL is aborted
  when the later one walks. Otherwise the later one aborts with `WW_PENDING`, or finds that DEL as the newest version.
  The earlier deleter's `its` store happens-before its `desc := 1` (program order, release store). The later
  deleter's `resolveTx` acquires that descriptor. So the tags are written in coherence order D1, D2, …, and at most the
  last of them commits (Theorem 1).
- **Stamps.** A stamp is written by the committed deleter after its own tag, so no older tag can overwrite it.
- **What R decides.** With L5: `TAG|D` resolves to own or visible exactly when D is R or D committed ≤ r. An epoch e
  decides `e ≤ r`. ∎

**Theorem 3 (scans).** `scan(u)` by R returns exactly the set of v with `S(r)[(u, v)]` present, overlaid with R's own
writes: count plus xor-hash.
*Proof.*
- **Completeness.** Every INS version that is own or visible to R lies in a reachable generation, within the scanned
  slot range (L8).
- **Exactness.** Such an x is counted iff it is not superseded for R (L9). That holds iff x is the newest visible
  version of k, using Theorem 1's order.
- **Uniqueness per key.** If two INS versions x1 before x2 of k were both visible, then x2's creator, being effective,
  saw k absent. So a committed DEL y lies between them, with `e(y) < e(x2) ≤ r`, and y is x1's next version. So x1 is
  superseded for R and is not counted.
- **Voided slots.** A slot is either linked content or VOID. A transaction that re-reserves after `IN_RESEAL` or a
  CAS-failure abort writes VOID **before** its descriptor publication. A scanner for which that transaction is visible
  therefore reads VOID by L3 and coherence. A scanner for which it is not visible ignores the slot anyway (L5).
  Unwritten slots have `owner = 0` and are skipped. ∎

**Theorem 4 (snapshot isolation).** In SI mode every committed transaction reads `S(rts)` overlaid with its own writes
(Theorems 2 and 3). Its writes become visible atomically: by L5 all of a transaction's versions and invalidations
resolve through one descriptor or epoch, which gives invariant I4, no torn visibility. No two committed writers of a
key are concurrent (Theorem 1). These are the defining properties of SI: checker C1, C2, C3. C4 is Theorem 3 applied at
`r = frontier` after `publishAll`. ∎

## 5. Serializability (SER mode, checker C5)

In SER mode a writer registers **before** validating (Silo order, defect D6). It then checks every recorded point read
and no-op write with `validatePoint`, and every scan with `scanBody(mode = 1)`. Attempts without effective writes skip
registration and validation; they serialize at `rts`.

Define a total order `ord` on committed transactions:
- a writer T is placed at `(e(T), position of its registration RMW in mo(E), lane index)`;
- a read-only T is placed at `(rts(T), +∞)`, after every writer of epoch `rts(T)`.

**L10 (registration order dominates anti-dependencies).** Let T be a committed SER writer that read version x of key k
(or scanned u, with k a key of u). Let U be a committed writer that linked the version y immediately after x (for a
scan: any version y of a key of u that T did not observe). Then T's registration RMW precedes U's in mo(E), and they
are distinct RMWs.
*Proof.* There are two cases.

Suppose first that U's registration RMW precedes T's in mo(E), or is the same RMW. U linked y with a head CAS during
its op loop. In `registerEpoch`, `__syncwarp()` orders that CAS before U's leader's acq_rel RMW on `E`.
- If the RMWs are distinct, T's leader's acq_rel RMW reads from the release sequence that contains U's RMW, and the
  `__syncwarp()` after T's RMW orders it before T's validation reads.
- If it is the same RMW (same warp), the first `__syncwarp()` orders U's CAS before T's validation directly.

Either way, U's CAS happens-before T's validation. T's validation then sees y:
- for a point read, by coherence on the head and L8 for later generations;
- for a scan, by L8 for the slot and by U's relaxed `owner` and `dstop` stores, which are ordered before U's CAS.

y is foreign and not aborted (U commits), and it is not x. `validatePoint` returns false because the newest
non-aborted foreign version is not `obs`. `scanBody` mode 1 flags y because it is not visible at `rts(T)`: U was
pending, or committed at `e(U) > rts(T)`, as otherwise T would have observed it, by Theorems 2 and 3. Either way T
aborts, contradicting the assumption that T committed.

So U's RMW is strictly later in mo(E). ∎

**Theorem 5 (serializability).** In SER mode, every edge T → U of the direct serialization graph satisfies
`ord(T) < ord(U)`. So the graph is acyclic and the history is serializable, with the version order of Theorem 1 as
the serialization's version order.
*Proof.* The edges are ww, wr and rw, with per-key version order equal to cts order and scans treated as reads of every
key of the vertex, as in the checker.
- **ww T → U and wr T → U** (U a writer): `e(T) ≤ rts(U) < e(U)` (Theorem 1, L5, L4).
- **wr T → U, U read-only:** `e(T) ≤ rts(U)` (L5), and `ord(U) = (rts(U), +∞)`.
- **rw T → U, T a writer:** by L10, T's RMW is strictly before U's in mo(E). Epochs are non-decreasing along mo(E), so
  `ord(T) < ord(U)`.
- **rw T → U, T read-only:** U's version y is not visible to T, otherwise T would have read y or something newer. So
  `e(U) > rts(T)`, and `ord(U)` lies in a later epoch than `(rts(T), +∞)`.

Read-only transactions have no outgoing ww or wr edges. ∎

*Why the read-only shortcut is sound.* Because every edge respects `ord`, the frontier snapshot at r is closed under
dependencies: it holds every committed writer with epoch ≤ r and nothing later. A transaction that reads exactly that
snapshot and writes nothing fits at `(r, +∞)` without validation (invariant I5).

## 6. Progress (not part of correctness)

- Operations are lock-free: a failed head CAS implies another link succeeded. Waits occur only for a generation
  grower. The grower is a single lane executing a bounded `allocBlock`, which can rely on Volta+ independent thread
  scheduling.
- Epoch registration is wait-free (one RMW).
- Aborts are no-wait: livelock under identical-edge contention is possible in principle. It is mitigated by
  randomized exponential backoff and bounded by `maxAttempts`; give-ups are reported, never silent.
- The advancer waits only for registered committers. A watchdog flags (4) and then invalidates (16) a run whose
  advancer is stuck, rather than publishing early (defect D9).

## 7. Lemma ↔ code ↔ test map

| lemma | code site (`src/gtxg.cuh`) | exercised by |
|---|---|---|
| L1 | `attempt`: three descriptor stores | every checked history |
| L2, L3 | `advancerLoop`, commit block (`__threadfence`, `__syncwarp`, `inflight` RMW) | C1/C5 on all 48 histories; defect D5 (livelock) / D9 (early publish) |
| L4, L10 | `registerEpoch` (`__syncwarp` before/after the RMW) | write-skew SER (0 cycles); `dbg & 64` restores the pre-fix code |
| L5 | `createVis`, `resolveTx`, read-only `desc := 1` | mut2 (dirty reads) and mut3 (ignore snapshot) rejected; defect D7 |
| L6, L7, Thm 1 | `walkGens(seal)`, `install` CAS loop and prefix re-walk | mut1 (no ww check) rejected: C3 + same-epoch writers; identical-edge histories |
| L8 | `allocBlock` release order, acq_rel reservation `fetch_add` | defect D8 (`dbg & 32` = relaxed reservation) |
| L9, Thm 3 | delete path `its := TAG\|self`, stamping | scans in all mixed histories; mut3 scan mismatches |
| Thm 5 | SER validation (`validatePoint`, `scanBody` mode 1) | write-skew probe: SI shows 16,000 back edges, SER 0; C5 on SER histories |

What the tests cannot show: the checker validates histories that actually occurred, so a missing hb edge that never
manifests on this GPU (the `__syncwarp` gap in L4/L10) is invisible to it. That is why the proof exists.

---------------------------------------------------------------------------------------------------------------------

## 8. Method 4: generation merging and block reuse (`Cfg::m4`)

M4 adds three mechanisms (`src/gtxg.cuh`: `mergeGens`, `reclaimerLoop`, `newBlock`, `setIts`/`loadIts`). Assumption A1
is dropped for delta slots, chain heads and block records; descriptors are still never reused.

- **Announce.** Each attempt's warp leader performs `a := frontier; ann[w] := a; fence.sc; rts := frontier`, so
  `a ≤ rts`. A warp's announcement is replaced only at its next attempt, and is set to `ANN_IDLE` when it exits.
- **Reclaimer.** A dedicated warp repeatedly performs:
  1. `tail := rTail` (acquire);
  2. `fr := frontier.fetch_add(0)`;
  3. `fence.sc` on every lane;
  4. `m := min(fr, min_w ann[w])`, published as `minAct`;
  5. it then frees ring entries below `tail` whose retire epoch is `< m`.
- **Merge.** Holding the per-vertex lock `cbusy[u]`, the grower's warp merges every generation older than a
  *holder* generation h into one new generation G*. The steps:
  1. **Seal** all heads of the old generations.
  2. **Count** the kept versions under the predicate below, with `m := minAct`.
  3. **Allocate** G*. This is the only fallible step; failure returns after step 1, which is benign by L6.
  4. **Bucket** the kept versions by G* chain (prefix sums).
  5. **Copy** generation by generation, newest first. A lane copies a chain newest-first. After writing a copy y of
     x, the lane runs `its` hand-off: `w := x.its; y.its := w; CAS(x.its, w → FWD|y)`, retried until it succeeds.
  6. **Link** each bucket as a chain.
  7. **Publish:** `__syncwarp`, then `fence.sc`, then `B[h].prevGen := G*` (release).
  8. **Retire** the old blocks at `r := frontier.fetch_add(0)`, read after the swing and a `fence.sc`.

**Keep predicate** `keep(x, m)`:
- keep a pending x;
- drop an aborted x;
- keep a committed DEL iff `cts > m`, or the merge is truncated (generations remain below the merged set);
- keep a committed INS iff its invalidation word, followed through forwarding, does not resolve to a committed
  deleter at an epoch ≤ m.

**L11 (what may be dropped).** Suppose m ≤ rts of every attempt that will ever read G*. Then replacing the old
generations by the kept versions, in their original per-key order, changes no decision of any such attempt:
reads, scans, no-op/effective decisions, conflict checks, or SER validation, apart from the conservative exception
noted at the end of the proof.

The kept set can only shrink between steps 2, 4 and 5, so bucket sizes are upper bounds and copies never overflow.
*Proof.*
- **Aborted versions** are invisible and skipped by every rule (L5).
- **A committed INS x invalidated by D with `e(D) ≤ m`.** By L9, D linked the version after x, and `e(D) ≤ m ≤ rts`,
  so D's version is visible to every such attempt. A reader stops at D's version or a newer one, never reaching x.
  A scanner would see x as invalidated. A writer finds a newer visible version first.
- **A committed DEL y with `e(y) ≤ m`, provided the merge is not truncated.** Every older version of the key is a
  committed version with a smaller epoch (Theorem 1). Each older INS among them is invalidated by a deleter with
  epoch ≤ `e(y)` ≤ m, so it is dropped as well.
  - *Not truncated* means every generation below the holder is in the merge. If `mergeGens` stops at its
    32-generation limit and leaves a remainder linked below G*, that remainder may hold an older INS of y's key. Chain
    walks do not consult `its`, so they would stop at that INS and read "present". Truncated merges therefore keep
    every committed DEL (`keepDel`).
  - The first M4 build lacked this rule. It was found by review (advisor, 2026-11-10), not by a test. Gate case F2
    forces truncation (`dbg 1024`: merge at most 2 generations), and mutation `dbg 1024|2048` drops DELs in truncated
    merges. After the drop, a walk that would have stopped at y finds no older version, so the key reads absent, which
  is exactly y's meaning. y is visible to every such attempt, so no conflict check would have aborted on it.
  - *The conservative exception:* a SER reader that observed y itself (`obs = y`) now fails `validatePoint` and aborts
    spuriously. That is safe, and its frequency is measured.
- **Monotonicity.**
  - Pending → aborted only drops more.
  - A version kept because its deleter was pending cannot become droppable later. If that deleter commits, it does so
    at an epoch > m: an epoch ≤ m ≤ the reclaimer's `fr` would have been published before `fr` was read (L3). ∎

**L12 (one consistent path; forwarding).** Every walk, scan and validation reads `B[g].prevGen` once per generation
step, with acquire. In a cooperative scan only the leader reads it and broadcasts it (`scanBody`, leader mode). So each
traversal sees either the old generations or G*, never both: there is no double counting and no gap. G*'s contents
happen-before any traversal that reads the swung pointer:
- copies and links by all lanes, then `__syncwarp`, then lane 0's `fence.sc`, then the release store, then the
  reader's acquire load.

For `its`:
- The hand-off CAS installs `FWD|y` only after `y.its` holds the value being replaced, and a forwarded word never
  changes again.
- `setIts` (deleter tags, lazy stamps) and `loadIts` (scans, keep, SER validation) follow forwarding links.

So an invalidation is never lost:
- A tag written to x *before* the hand-off is either copied into y, or makes the CAS fail, in which case it is
  re-copied.
- A tag attempted *after* the hand-off fails its CAS on x, follows FWD, and lands in y.

Creation visibility is unaffected. A copy keeps `owner`, and keeps `cts` if stamped. A pending copy resolves through
`desc` forever. Lazy stamps of `cts` go to the original only, which is harmless because stamps cache what `desc`
yields (L5).

G*'s non-empty heads are created sealed; empty buckets hold `NILD` unsealed. That is harmless because G* is never a
reservation generation (installs go only to the newest generation h), so nothing is ever linked into it. All
old generations are sealed (step 1) before anything is copied. Hence no version can be added to a generation after
it has been read for the copy (L6). G* versions precede every version in h and newer generations, so Theorem 1's
order is kept: the copy order is per-key newest-first, generation by generation, with `__syncwarp` between
generations ordering the bucket RMWs. ∎

**L13 (validation identity under copies).** In SER mode `validatePoint` accepts the newest non-aborted foreign version
y if `y = obs`, or if `owner(y) = owner(obs)` and `dstop(y) = dstop(obs)`.
*Proof.* A transaction W's versions of one key all become visible together (L5). A reader that observed one of them
observed W's newest one (Theorem 2). Two versions of W with equal `dstop` that are both the newest non-aborted
foreign version of the key at different times are therefore the same version, or a copy of it. `obs` remains
allocated during the attempt by L14. ∎

**L14 (announcement and reclamation safety).**
- **(a) Every attempt that reads G* has `rts ≥ m`.** Take an attempt X whose announcement the reclaimer's scan
  missed. Then X's `fence.sc` follows the reclaimer's in the SC order. The reclaimer's `fetch_add(0)` on `frontier` is
  a modification sequenced before its fence, so X's re-read of `frontier` after its own fence returns that value or
  a later one, and `rts(X) ≥ fr ≥ m`. If the scan saw the announcement, then `m ≤ a ≤ rts(X)`. Attempts that begin
  after m was computed read a frontier ≥ `fr`.
- **(b) A retired block is freed only after every attempt that might reference it has ended.** Suppose X still
  references an old generation, through a pointer read before the swing or a slot index such as `myD`, `sup` or
  `obs`. Then X announced before reading that pointer. If X read the pre-swing `prevGen` value, X's fence precedes
  the merger's post-swing fence in SC order (store–fence–fence–load). The merger's `fetch_add(0)` is after its fence,
  so `a(X) ≤ r` (RC11: `rf⁻¹` from a later modification would order the fences the other way).
  - X may instead hold its own slot in the old generation: linked, or reserved and later voided (`myD`, or the slot
    it is about to void). X obtained that slot through its acq_rel `fetch_add` on `vfill[u]`, after its fence. The
    merge is triggered by a later grower of u, whose own `vfill[u]` RMW is later in that RMW chain, and every RMW of
    the chain is acq_rel. So X's fence happens-before the merger's fence, and again `a(X) ≤ r`. A linked slot is
    covered even more directly: the merger's sealing RMW reads from X's linking CAS.
  - The reclaimer frees an entry only using an m computed after it observed the entry. The entry was reserved after
    the retire, so X's announcement store, ordered before X's fence and hence before the merger's fence, is visible
    to that scan. So `m ≤ a(X) ≤ r` while X is in that attempt, and the entry (`r < m` required) is not freed.
  - Freed slots are zeroed entirely (all 32 bytes) and heads reset before the free-list push (release). A pop
    (acquire) therefore hands out a block indistinguishable from fresh arena: owner 0 marks an unwritten slot.
  - Zeroing `cts` and `its` matters. A scanner may read a slot's `cts` before the new writer's `cts := 0` reaches it,
    because creation fields are relaxed. That is safe only if the stale value is 0, which makes the scanner fall back
    to the descriptor.
  - The first implementation zeroed only `owner` and `dstop`. The gate exposed it as a 10× increase in SER aborts
    under reuse, from stale committed epochs read for pending versions (defect D10).
- **(c) ABA.** Free-list heads carry a 32-bit tag incremented on every pop. Chain-head CAS ABA cannot arise, because
  a head is reused only after every attempt that could hold its old value has ended (b). ∎

**Consequence.** With L11–L14 the base proof carries over unchanged.
- Theorems 1–5 hold with G* in place of the generations it replaced.
- A1 is replaced by (b), which covers block reuse.
- C2, the observed writer, is checked against the owner recorded at read time (`OpResult::pad`), because a reclaimed
  slot can hold a different version in the final snapshot.

**What tests M4.** Gate section F forces merges and reuse with 2× growth and low thresholds on all adversarial
workloads, plus two races built for M4: a hub with cooperative scans and SER validation, and hot-edge churn. Section G
holds five mutation cases:
- copy `its` without the hand-off (`dbg 256`): rejected;
- drop at the frontier, ignoring announcements, in SI and SER (`dbg 512`, two cases): both rejected;
- drop DELs in truncated merges (`dbg 1024|2048`, added after review): rejected;
- per-lane generation lists in cooperative scans (`dbg 128`): **not observable** on this GPU (SIMT lockstep);
  informational only, so L8/L12's leader broadcast rests on the proof alone.

Of the four mutations registered before measurement, three are rejected, so P3 fails as registered.

**Coverage limit.** Sections F–H run with `coop = 1`, `dstconf = 1`, `coopScan = 1` and `prewalk = 0` only. M4
together with the other mode combinations (per-lane writers, source-hashed conflicts, per-lane scans, pre-walk) is
argued by the proof but not gated.

Section H runs arena exhaustion with reuse.

---------------------------------------------------------------------------------------------------------------------

## 9. Method 5: quiescent compaction (`Store::compact`)

M5 runs on the host thread between kernel launches, after `publishAll()`, with `Cfg::m4 = 0`. It computes the
graph visible at the frontier F, discards the whole version store, and rebuilds it as a bulk-loaded state of that
graph. Code: `qcVisible`, `kQcSize`, `Store::compact` in `src/gtxg.cuh`, with two kernel sets:
- `qcChunk = 1` (default, hybrid): `kQcChCount` classifies each vertex by the slots its chain holds. Vertices above
  `qcBigSlots` (4096) are split into 512-slot chunks (`kQcChEmit`, `kQcChScan`) and rebuilt by one thread block each
  (`kQcBuildBig`). Smaller vertices use one warp each (`kQcScan` with a skip mask, `kQcBuildSmall`).
- `qcChunk = 0` (first version): one warp per vertex (`kQcScan`, `kQcBuild`).

Assumptions: A2 and A3 as before. A4 is used in its quiescent-boundary form: no kernel of the store is running, and
the previous kernel has completed (stream order). A1 is weakened to **A1′**: slots, heads, blocks and descriptor
ids are never reused *within one kernel run*. Compaction reuses all of them, but only at a boundary.

**L15 (quiescent state).** When `compact` reads the store, no attempt is in flight. Every committed attempt T has
`e(T) ≤ F`, and every store issued by the previous kernel is visible to the compaction kernels.
*Proof.* The previous kernel has completed, so every attempt has finished. `attempt()` has no return path between
taking a txid (`warpAggInc(c.txTop)`) and the final descriptor store. Lanes give up only between attempts, never
inside one, so every txid below `descCap` holds its final value (L1). Ids at or above `descCap` were never given a
descriptor: such attempts abort as resource aborts without writing a version, and `qcCommittedLE` reads them as not
committed. An attempt
registers only in the epoch open at the time (L2), and that epoch is at most the open epoch e that `publishAll` reads.
`publishAll` sets `frontier := e` and opens e+1, so F = e bounds every registration. Kernel completion followed by a
later launch in the same stream orders all memory operations of the first kernel before the second. That covers the
relaxed creation fields (`cts`, `its`) and the `vfill` words. ∎

**L16 (live set = visible set at F).** The scan kernels count and gather exactly the edges (u, v) that a snapshot
read at F returns, each once.
*Proof.* By L15 a plain read of a delta sees its final state. `qcVisible` is the rule of Theorem 2 / L5 evaluated at
r = F with no own writes:
- a version is visible if it is an INS with a non-zero owner whose commit epoch is ≤ F (from the stamp `cts`, or
  from `desc`, which agree by L5);
- it must not be invalidated at F: `its` is 0, a pending tag whose owner did not commit at an epoch ≤ F, or a
  stamped epoch > F.

Reserved but never-written slots have owner 0 (zeroed arena, or zeroed by the previous compaction). Voided slots
carry the VOID opcode. Aborted and pending owners fail the commit test. The scan walks every generation of u through
`prevGen`, bounding the newest one by its fill and older ones by capacity, which is the set of slots
`reserveSlot` can ever have handed out. In the hybrid path each vertex is handled by exactly one of the two kernel
families: `kQcChCount` sets the skip mask (`cur[u] = ~0` for small vertices) and emits chunks only for big ones. The
chunks of a big vertex partition exactly the same slot ranges. Chunk positions come from a per-vertex atomic cursor,
so the destinations of u fill `tmp[toff[u], toff[u] + cnt[u])` in some order. By Theorem 1 (version order, I1/I2), at most one version of a key is visible
and not invalidated at any snapshot, so each live destination appears once, and their order inside u's range is irrelevant. The host
`Store::visibleEdges` uses the same rule. Gate section I compares the two directly every checked round, before and after compaction. ∎

**L17 (rebuild is a bulk-loaded state).** After `compact` returns true, the store equals a state produced by the bulk
loader on the edge set of L16, with one committed loader transaction (txid 1) at epoch 1 and frontier 1.
*Proof.* The used prefixes are reset: `H[0, hTop)` is set to NILD, `desc[0, txTop)` is zeroed, and the counters are
cleared. Delta slots are reset either by a memset of `D[0, dTop)` (first version) or by the build itself. In the
hybrid build every slot of `[0, dT)` belongs to exactly one rebuilt generation and is written in full: a live entry,
or an all-zero slack slot. The memset then covers only `D[dT, dTop)`. Slots beyond the old tops were never written
(bump allocation), so they are already in their initial state.

The build writes, for every live vertex u, one generation of capacity `pow2ceil(n + 1 + slack·n)` (at least
`minCap`, with head count `cap / chRatio`). Each live destination goes into one slot as a committed INS (owner 1,
`cts` 1, `its` 0), and each slot is linked into its hash chain with `atomicExch`. `vcur`/`vfill` are written for every
vertex: the new generation, or "no block" when u has no live edge.

Block records `B[nb, oldTop)` are *not* reset. They are unreachable: B is read only through `vcur` and `prevGen`
(M4's free lists are off), which reach only the nb new records. `newBlock` writes all eight fields of a record before
publishing its id, so a stale record is never read before being overwritten. Different slots of a vertex can race on a head, but `atomicExch` makes each link a
total order. Chain order among *distinct* keys is irrelevant to every lemma, because §2–§4 reason per key and each
key occurs once.

Then `desc[1] := COMMITTED(1)`, txTop := 2, `E := (2 << 32) | 0` and frontier := 1. This is the `bulk = 1` start state
covered in the configuration list. The fit test runs before any reset, so a `false` return leaves the store unchanged
(only `publishAll` has run, which is idempotent at a boundary). The sticky OOM flag is preserved. ∎

**Theorem 6 (correctness across compactions).** Let a long run be kernel runs K₀, K₁, … separated by boundaries, some of
which compact. The concatenated history satisfies SI (SER in SER mode) for the same checker conditions C1–C5, where
each run's start state is the visible state at the end of the previous run.
*Proof.* Within a run, A1′ is A1, so Theorems 1–5 hold for that run from its start state.
- At a non-compacting boundary, the next run starts from the state at F (L15).
- At a compacting boundary it starts from the bulk-loaded copy of that state (L16, L17).

Every attempt of run k+1 starts after every attempt of run k has finished. So the global order "all of run k, then
run k+1" is consistent with each run's serialization (or SI) order and with real time. Map run k+1's epochs to
F_k + (e − 1); the map is monotone, so snapshot containment and first-committer-wins carry over. No write-write
conflict spans runs, because no two attempts of different runs overlap. Txid reuse is invisible across runs, because
descriptors of run k are zeroed before run k+1 and no version of run k survives except as a loader version (owner 1). ∎

**What the history checker sees.** The per-round checks (`runLongRun`, `checkStoreRun`) use the visible set at the
round's start, taken *before* that round's compaction, as the start state. A reader in the next round observing a
rebuilt version reports owner 1 < base, which maps to the start state (−2). A pre-base DEL left by an earlier round
(non-compacting boundary) maps to "no writer" (−1), because the start state has no such edge.

**The F − 1 observation.** Mutation `dbg 16384` compacts at F − 1. It is not observable at a boundary, and that is
expected, not a gap. `publishAll` publishes the epoch that was open when the kernel ended. The in-kernel advancer
keeps closing epochs while work remains, so the last epoch normally has no committed writer, and visibility at F − 1
equals visibility at F. The gate therefore also runs F/2 (`dbg 32768`), which drops many committed epochs and is
rejected. This is a deviation from the mutation list registered in `design.md` (M5, Q3): F − 1 was registered, found
vacuous, kept as informational, and F/2 was added.

**Not covered.** Compaction with `m4 = 1` (refused at runtime), compaction during a kernel (not implemented: a run
that never returns to the host still grows without bound), and the mutations `dbg 4096|8192|16384|32768`.

**What tests M5.** Gate section I:
- four multi-round workloads (uniform, hub, identical-edge, Zipf with readers), each in three kernel variants:
  - `hyb`: the default hybrid kernels, all eight `ser × coop × dstconf` combinations, `coopScan` and slack 0/50
    alternating;
  - `chunk`: the long-run policy (`growShift 1`, slack 100) with `qcBigSlots = 8`, so nearly every vertex takes the
    chunk path, all eight combinations;
  - `legacy`: `qcChunk = 0`, the four `coop = dstconf` combinations;
- in every variant, compaction is forced every round, and every round is checked plus the direct visible-set
  comparison;
- a trigger test per variant with a small arena that must compact on its own and must never exhaust the arena;
- mutations, per variant: drop one live edge (`dbg 4096`), keep invalidated versions (`dbg 8192`), stale frontier
  F/2 (`dbg 32768`), all expected to be rejected; F − 1 (`dbg 16384`) is informational.

**Scope of the memory bound (not a correctness matter).** Compaction is triggered before a launch when the next
round's projected growth (margin × the largest growth seen so far) would not fit. A round that grows by more than
that projection can still exhaust the arena inside the kernel. Exhaustion is handled correctly (section D: resource
aborts, committed prefix checked), but the transactions given up are lost work.
