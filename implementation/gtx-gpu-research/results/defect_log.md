# Defect log — protocol defects found by the history checker / stress tests during development

Each entry: symptom (how it was detected), root cause, fix, and the evidence that the fix holds. Details and
counterexample histories: `audit/prototype_audit.md` (D5–D9). All were found **before** any benchmark in
`results/summary.md` was recorded; every benchmarked configuration passes the correctness gate afterwards.

| id | detected by | symptom | root cause | fix | evidence after fix |
|---|---|---|---|---|---|
| D5 | multi-rep stress (180 reps) + watchdog flag | 1 in ~30 kernels took 1.5–20 s instead of ~1 ms; flag = advancer | commit read `E`, incremented in-flight, re-read `E` and retried; advancer bumps `E` ~1/µs ⇒ committer starves | wait-free registration: one `fetch_add` on `(epoch<<32 \| count)`; advancer closes an epoch with one `exchange` and waits for exactly that many completions | 180/180 reps in 0.15–1.0 ms, max/median ≤ 1.5 |
| D6 | checker C5 (serialization graph) | 5 SER histories with 1–40,535 DSG back edges once read-only txns skipped validation | epoch fixed *after* read validation ⇒ rw edge T→U can run backwards in commit order ⇒ read-only anomaly | Silo order: register epoch before validation | 0 cycles in all SER histories (suite A, write-skew probe, check matrix) |
| D7 | reasoning during D6 fix (C1 risk) | read-only commit at cts=rts would make its voided slots "committed in the past" | a txn with no effective writes may own reserved-then-voided slots | read-only commit publishes ABORTED descriptor (owns no live delta) | suite A and check matrix PASS |
| D8 | forensic scan instrumentation | (model) stale `vcur` could skip a generation holding a committed delta | reservation `fetch_add` on `vfill` was relaxed: no happens-before with the grower's release of the generation | reservation RMW is acq_rel | memory-order argument (design §4); suite PASS |
| D9 | checker C1 + forensic decision codes | SER per-lane-scan runs: scans missed/added one committed edge; decision code "creator ACTIVE" for a writer committed below the reader's snapshot | harness watchdog broke out of the advancer's completion wait after 20 s and published the frontier early (these runs take ~40 s) | watchdog only flags; at 2× deadline the run is declared INVALID (flag 16) and publishing stops; watchdog also ends retries | 4/4 stress iterations PASS; suite A (48 histories) PASS |

### 2026-11 (proof work and Method 4)

D11 and D12 were found by the written proof (`design/proof.md`), not by tests. The checker cannot see them: on
this GPU the 32 lanes execute the affected instructions in lockstep, so the missing happens-before edges never
manifest. Both fixes measured ≤ 1–3% (`results/v2`); the gate passes 67/67 after each.

| id | detected by | symptom | root cause | fix | evidence after fix |
|---|---|---|---|---|---|
| D10 | M4 gate (section F/G), abort statistics | SER runs with block reuse aborted ~10× more than merge-only runs | the reclaimer zeroed only `owner`/`dstop` of freed slots. A scanner can read a reused slot's `cts` before the new writer's `cts := 0` reaches it (relaxed creation fields), and a stale nonzero `cts` decides visibility without the descriptor | zero all 32 bytes of every freed delta | gate A–H: all as expected (`results/v2/correctness_suite.txt`); proof L14 |
| D11 | proof (L4, L10) | latent: none observed | commit registration ordered lanes only with `__ballot_sync`/`__shfl_sync`, which the CUDA guide says imply no memory ordering. Needed: every lane's frontier load and head CASes happen-before the leader's registration RMW (`e > rts`; SER intra-warp rw edges), and the RMW happen-before every lane's validation reads | `__syncwarp()` before and after the registration RMW (`dbg 64` restores the old code) | gate 67/67; cost within noise (`results/v2/uncontended_gap.md` session) |
| D12 | advisor review of the proof (L8) | latent: none observed | in a warp-cooperative scan, each lane loaded `vcur`/`prevGen` itself. Only the scanning lane holds the frontier acquire, so on paper other lanes could see a stale generation list or stale delta contents. Under M4 a `prevGen` swing could also split lanes across two paths | the scanning lane reads the generation list and broadcasts it; `__syncwarp` before any lane reads slots (`dbg 128` restores per-lane loads) | gate 67/67. The `dbg 128` mutation is *not* detected by the checker (SIMT lockstep): recorded as a proof-only hazard |
| C2-M4 | M4 gate section F | every M4 history failed C2 "observed writer −1, expected X" with C1 passing | not an engine defect: a merge may drop a committed DEL at ≤ minActive (proof L11), so a reader of an absent key observes no version where the model's newest version is that DEL | checker accepts exactly that case under M4 (`allowDroppedDel`); every other identity mismatch still fails, and a wrong state still fails C1 | the three observable registered M4 mutations are still rejected, by C1 scan violations (918–8,449 per run in the final gate); the later truncated-merge mutation (`dbg 1024|2048`) is rejected too. Final gate: 4 of 5 section-G cases rejected, `dbg 128` informational |

Lesson recorded in the design (§5): a diagnostic mechanism must never trade safety for liveness; the checker found
that one within one iteration because it validates reads operation by operation instead of comparing final states.
