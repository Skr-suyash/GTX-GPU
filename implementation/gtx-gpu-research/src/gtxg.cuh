// GTX-GPU: a GPU adaptation of GTX (Zhou et al., VLDB 2024/2025) for atomic multi-edge
// transactions with concurrent readers.
//
// Retained from GTX: versioned edge deltas (creation / invalidation stamps), per-vertex edge-delta
// blocks, destination-hashed delta chains used for write-write conflict detection, transaction
// descriptors resolved lazily by readers, group commit, post-commit lazy timestamp stamping.
//
// GPU-specific changes (each switchable for ablation, see Cfg):
//  * coop    : cooperative (warp-aggregated) delta reservation -- one fetch_add per (warp, block)
//  * dstconf : destination-precise conflict detection with validate-then-CAS on the SAME observed
//              chain head (prefix re-walk on CAS failure). dstconf=0 = GTX chain-granularity rule.
//  * epochs  : commit groups -- txns register in the open epoch with one fetch_add on (epoch,count), a single
//              advancer publishes a read frontier F only after every epoch <= F is fully published.
//  * block generations : a full block is never copied under writers; a new generation (2x) is
//              linked in front and older generations' chain heads are sealed lazily by writers.
//
// Descriptor word: 0 ACTIVE, 1 ABORTED, (e<<2)|2 COMMITTED at epoch e.
#pragma once
#include <chrono>
#include <cstring>
#include <thrust/execution_policy.h>
#include <thrust/scan.h>
#include "common.cuh"

namespace gtxg {

constexpr u32 NILD = 0x7FFFFFFFu;   // null delta index
constexpr u32 SEAL = 0x80000000u;   // chain-head sealed bit (older generation: no more installs)
constexpr u32 NONEB = 0xFFFFFFFFu;  // vertex has no block yet
constexpr u32 PENDB = 0xFFFFFFFEu;  // first block being created
constexpr u32 OPB_INS = 1, OPB_DEL = 2, OPB_VOID = 3;
constexpr u64 TAGBIT = 1ull << 63;
constexpr int MAXOPS = 32;
constexpr u32 SCANV = 0xFFFFFFFFu;  // read-set marker for scan entries

struct Delta { u32 dstop; u32 prev; u32 owner; u32 pad; u64 cts; u64 its; };
struct Block { u32 base, cap, nch, chBase, fill, prevGen, vtx, pad; };

struct Cfg {
  int coop = 1;       // cooperative warp-aggregated reservation
  int dstconf = 1;    // destination-precise conflicts (0 = GTX chain granularity)
  int ser = 0;        // serializable validation (0 = snapshot isolation)
  int stamp = 1;      // lazy post-commit stamping
  int coopScan = 1;   // warp-cooperative adjacency scans
  int mut = 0;        // checker-sensitivity mutations: 1 no ww check, 2 dirty reads, 3 ignore snapshot
  u32 minCap = 8;
  u32 chRatio = 1;    // chain heads per block slot divisor (1 = one head per slot)
  u32 maxAttempts = 4000;
  u32 advanceNs = 0;
  u32 growShift = 3;  // new generation capacity = old capacity << growShift (8x)
  int prewalk = 0;    // optimistic read-only pre-walk before reserving a slot
  int dbg = 0;        // profiling ablations: 1 skip install walk/CAS, 2 skip result writes, 4 skip commit
                      //   8 scan ignores fill, 16 SER late registration, 32 relaxed reservation, 64 no __syncwarp at registration
  int bulk = 0;       // host bulk loader for the initial graph (first generation sized from the initial degree)
  int m4 = 0;         // Method 4: 1 announce + reclaimer only, 3 + generation merging, 7 + block reuse (see design/m4)
  u32 mergeMin = 64;  // M4: minimum total slots below the filled generation before a merge is worth it
  // M4 revision knobs (defaults = M4 as pre-registered): hold-size only generations with cap >= holdMin; trigger a
  // merge on the garbage of the generations that would be merged (sum of their counters >= half their capacity)
  // instead of on the filled generation's garbage.
  u32 holdMin = 0;
  int mergeOnOldGarbage = 0;
  // M5 quiescent compaction (Store::compact, design §7 M5, proof §9): extra headroom per vertex, in percent of its
  // live degree. dbg mutations: 4096 drop one live edge on every 61st vertex, 8192 keep invalidated versions,
  // 16384 compact at frontier - 1, 32768 compact at frontier / 2.
  u32 qcSlackPct = 0;
  // M5 kernels: 1 = load-balanced (fixed 512-slot chunks, slot-parallel rebuild), 0 = one warp per vertex (first version).
  u32 qcChunk = 1;
  u32 qcBigSlots = 4096;  // hybrid threshold: vertices scanning more slots than this are chunked (gate forces 8)
};

struct Ctx {
  u32 V;
  u32* vcur;       // current generation, read by walkers/scanners (published before vfill)
  u64* vfill;      // writers' reservation word: (generation << 32) | slots reserved
  Block* B; u32* bTop; u32 bCap;
  Delta* D; u32* dTop; u32 dCap;
  u32* H; u32* hTop; u32 hCap;
  u64* desc; u32* txTop; u32 descCap;
  u64* E; u64* frontier; u32* inflight; u32* stop; u32* oom;
  const u32* off; const Op* ops; u32 N; u32* nextTxn;
  OpResult* res; TxRecord* rec;
  u32* stats; u32* doneWarps; u32 nWorkWarps;
  u32* dbgBuf = nullptr; u32* dbgTop = nullptr; u32 dbgCap = 0;  // forensic: counted delta ids per per-lane scan
  u64 watchdogNs;  // per-warp wall-clock limit; on expiry *oom = 2 and remaining work gives up
  Cfg cfg;
  // ---- Method 4 (generation merging + block reuse); see design/m4.md and design/proof.md section 8
  u64* ann = nullptr; u32 nAnn = 0;  // per-warp announced frontier value for the current attempt (ANN_IDLE when idle)
  u64* minAct = nullptr;             // cached lower bound on every active/future snapshot, published by the reclaimer
  u32* cbusy = nullptr;              // per-vertex merge lock
  u64* retire = nullptr; u32* rTail = nullptr; u32* rHead = nullptr; u32 rCap = 0;  // retire ring: (r << 32) | block
  u64* freeHead = nullptr;           // per size class (log2 cap): tagged Treiber stack (tag << 32 | block), next in prevGen
  u32* m4stats = nullptr;            // see M4_* below
};

constexpr u64 ANN_IDLE = ~0ull;
constexpr u64 FWDBIT = 1ull << 62;   // its word: "this version was copied; its authoritative its lives at idx"
constexpr u64 RING_EMPTY = ~0ull;
constexpr u32 NOBLK = 0xFFFFFFFFu;
enum M4Stat { M4_MERGES = 0, M4_GENS_MERGED, M4_KEPT, M4_LINKED, M4_RETIRED, M4_FREED, M4_REUSED, M4_RING_FULL,
              M4_OVERFLOW, M4_HOLDS, M4_LOCK_BUSY, M4_TRUNC, M4_N = 16 };

template <class T> __device__ __forceinline__ cuda::atomic_ref<T, cuda::thread_scope_device> AR(T& x) {
  return cuda::atomic_ref<T, cuda::thread_scope_device>(x);
}
#define ACQ cuda::memory_order_acquire
#define REL cuda::memory_order_release
#define RLX cuda::memory_order_relaxed
#define SEQ cuda::memory_order_seq_cst
#define ACQREL cuda::memory_order_acq_rel

enum Vis { V_SELF = 0, V_VIS = 1, V_LATE = 2, V_ACTIVE = 3, V_ABORTED = 4 };

__device__ __forceinline__ int resolveTx(const Ctx& c, u32 owner, u32 self, u64 rts) {
  if (owner == self) return V_SELF;
  u64 d = AR(c.desc[owner]).load(ACQ);
  if (d & 2) return ((d >> 2) <= rts || c.cfg.mut == 3) ? V_VIS : V_LATE;
  if (d == 1) return V_ABORTED;
  return c.cfg.mut == 2 ? V_VIS : V_ACTIVE;
}

__device__ __forceinline__ int createVis(const Ctx& c, Delta* d, u32 owner, u32 self, u64 rts) {
  if (owner == self) return V_SELF;
  u64 cts = AR(d->cts).load(RLX);
  if (cts) return (cts <= rts || c.cfg.mut == 3) ? V_VIS : V_LATE;
  return resolveTx(c, owner, self, rts);
}

// Read the authoritative invalidation word of a version: follow M4 forwarding (copy -> copy ...).
// A forwarded word is never changed again, and the copy's word was initialised before the forwarding CAS (release),
// so following with acquire loads yields the current value (proof L12).
__device__ __forceinline__ u64 loadIts(const Ctx& c, Delta* d) {
  u64 its = AR(d->its).load(ACQ);
  while (its & FWDBIT) its = AR(c.D[(u32)its].its).load(ACQ);
  return its;
}

// Install `val` into the invalidation word of version x (following forwarding); returns where it landed.
// expectTag != 0: only replace that exact tag (lazy stamping); otherwise replace any non-forwarded value.
__device__ __forceinline__ u32 setIts(const Ctx& c, u32 x, u64 val, u64 expectTag) {
  for (;;) {
    u64 w = AR(c.D[x].its).load(ACQ);
    if (w & FWDBIT) { x = (u32)w; continue; }
    if (expectTag && w != expectTag) return x;  // nothing to stamp
    if (AR(c.D[x].its).compare_exchange_strong(w, val, ACQREL, ACQ)) return x;
  }
}

// Is a visible INS delta invalidated for (self, rts)?
__device__ __forceinline__ bool invalidated(const Ctx& c, Delta* d, u32 self, u64 rts) {
  u64 its = c.cfg.m4 ? loadIts(c, d) : AR(d->its).load(ACQ);
  if (!its) return false;
  if (its & TAGBIT) { int k = resolveTx(c, (u32)its, self, rts); return k == V_SELF || k == V_VIS; }
  return its <= rts || c.cfg.mut == 3;
}

struct WalkOut { u32 cur; int present; int cause; };

// Walk one chain newest-first from idx to stop (exclusive).
// writer: first-updater-wins rules; reader: first visible version.  Returns 0 none, 1 found, 2 abort.
__device__ int walkChain(const Ctx& c, u32 idx, u32 stop, u32 v, u32 self, u64 rts, bool writer,
                         bool& chainChecked, WalkOut& o) {
  u32 steps = 0;
  while (idx != NILD && idx != stop) {
    if (++steps > (1u << 24)) { atomicOr(c.oom, 8u); o.cause = AB_RESOURCE; return 2; }  // corrupt chain guard
    Delta* d = &c.D[idx];
    u32 owner = AR(d->owner).load(ACQ);
    u32 dstop = AR(d->dstop).load(RLX), dst = dstop & 0x3FFFFFFFu, op = dstop >> 30;
    u32 nxt = AR(d->prev).load(RLX);
    if (op == OPB_VOID) { idx = nxt; continue; }
    int k = createVis(c, d, owner, self, rts);
    if (writer && !chainChecked && !c.cfg.dstconf && k != V_ABORTED) {
      chainChecked = true;  // GTX rule: the chain's newest live delta must be visible (or ours)
      if ((k == V_ACTIVE || k == V_LATE) && c.cfg.mut != 1) {
        o.cause = (dst == v) ? (k == V_ACTIVE ? AB_WW_PENDING : AB_WW_LATE) : AB_CHAIN_FALSE;
        return 2;
      }
    }
    if (dst == v) {
      if (writer) {
        if (k == V_ACTIVE || k == V_LATE) {
          if (c.cfg.mut != 1) { o.cause = (k == V_ACTIVE) ? AB_WW_PENDING : AB_WW_LATE; return 2; }
        } else if (k != V_ABORTED) { o.cur = idx; o.present = (op == OPB_INS); return 1; }
      } else if (k == V_SELF || k == V_VIS) { o.cur = idx; o.present = (op == OPB_INS); return 1; }
    }
    idx = nxt;
  }
  return 0;
}

__device__ __forceinline__ u32 headSlot(const Block* b, u32 v) { return b->chBase + (mix32(v) & (b->nch - 1)); }

// prevGen is immutable without M4; with M4 a merge swings it (release), so readers acquire it.
__device__ __forceinline__ u32 loadPrevGen(const Ctx& c, Block* b) { return c.cfg.m4 ? AR(b->prevGen).load(ACQ) : b->prevGen; }

// Walk all generations of u newest-first starting at generation g with top-generation head h0.
// seal: seal older generations' heads before walking them (required for writers).
__device__ int walkGens(const Ctx& c, u32 g, u32 h0, u32 v, u32 self, u64 rts, bool writer, bool seal, WalkOut& o) {
  bool cc = false;
  int r = walkChain(c, h0 & NILD, NILD, v, self, rts, writer, cc, o);
  if (r) return r;
  u32 pg = loadPrevGen(c, &c.B[g]);
  while (pg < PENDB) {
    Block* b = &c.B[pg];
    u32 hs = headSlot(b, v);
    u32 h = AR(c.H[hs]).load(ACQ);
    if (seal && !(h & SEAL)) h = AR(c.H[hs]).fetch_or(SEAL, ACQREL) | SEAL;
    bool cc2 = true;
    r = walkChain(c, h & NILD, NILD, v, self, rts, writer, cc2, o);
    if (r) return r;
    pg = loadPrevGen(c, b);
  }
  return 0;
}

// Read-only walk from the vertex's current generation.
__device__ int walkFromCurrent(const Ctx& c, u32 u, u32 v, u32 self, u64 rts, bool writer, WalkOut& o) {
  o.cur = NILD; o.present = 0; o.cause = -1;
  u32 g = AR(c.vcur[u]).load(ACQ);
  if (g >= PENDB) return 0;
  u32 h0 = AR(c.H[headSlot(&c.B[g], v)]).load(ACQ);
  return walkGens(c, g, h0, v, self, rts, writer, false, o);
}

// Serializable validation of a point observation: newest non-aborted foreign version must be obs.
__device__ bool validatePoint(const Ctx& c, u32 u, u32 v, u32 obs, u32 self) {
  u32 g = AR(c.vcur[u]).load(ACQ);
  while (g < PENDB) {
    Block* b = &c.B[g];
    u32 idx = AR(c.H[headSlot(b, v)]).load(ACQ) & NILD;
    while (idx != NILD) {
      Delta* d = &c.D[idx];
      u32 owner = AR(d->owner).load(ACQ);
      u32 dstop = AR(d->dstop).load(RLX);
      if ((dstop & 0x3FFFFFFFu) == v && (dstop >> 30) != OPB_VOID && owner != self) {
        bool aborted = (AR(d->cts).load(RLX) == 0) && AR(c.desc[owner]).load(ACQ) == 1;
        if (!aborted) {
          if (idx == obs) return true;
          // M4: a merge may have copied the observed version. A transaction's newest version of a key is unique, so
          // (owner, dstop) identifies it (proof L13). obs stays allocated while this attempt is announced (EBR).
          return c.cfg.m4 && obs != NILD && AR(c.D[obs].owner).load(RLX) == owner && AR(c.D[obs].dstop).load(RLX) == dstop;
        }
      }
      idx = AR(d->prev).load(RLX);
    }
    g = loadPrevGen(c, b);
  }
  return obs == NILD;
}

// Scan of vertex u for (self, rts). mode 0: count visible neighbours. mode 1: serializable validation.
// Per-lane body over slot range [lo, n) stepping by `step`.
// leader >= 0 (warp-cooperative scan; all 32 lanes call): only the leader -- the lane whose transaction scans, and
// whose frontier acquire makes every visible creator's writes happen-before -- reads the generation list (vcur,
// vfill, block, prevGen) and broadcasts it; __syncwarp then extends its happens-before edges to every lane before
// any lane reads a slot. All lanes therefore walk ONE generation path (proof L8', required once M4 swings prevGen).
__device__ __forceinline__ void scanBody(const Ctx& c, u32 u, u32 self, u64 rts, int mode, u32 lo, u32 step,
                                         u32& cnt, u32& hx, bool& bad, u32* dbgOut = nullptr, u32 dbgMax = 0, int leader = -1) {
  const bool coop = leader >= 0, mine = !coop || (int)(threadIdx.x & 31) == leader;
  u32 g = mine ? AR(c.vcur[u]).load(ACQ) : 0;
  if (coop) g = __shfl_sync(FULLMASK, g, leader);
  u32 ngen = 0;
  while (g < PENDB) {
    u32 n = 0, base = 0, pg = NONEB;
    if (mine) {
      Block* b = &c.B[g];
      u64 w = AR(c.vfill[u]).load(RLX);
      u32 f = ((u32)(w >> 32) == g && !(c.cfg.dbg & 8)) ? (u32)w : b->cap;  // older generations are full (or sealed)
      n = f < b->cap ? f : b->cap; base = b->base; pg = loadPrevGen(c, b);
    }
    if (coop) { n = __shfl_sync(FULLMASK, n, leader); base = __shfl_sync(FULLMASK, base, leader); pg = __shfl_sync(FULLMASK, pg, leader); __syncwarp(); }
    if (dbgOut && ngen < 12) { dbgOut[dbgMax - 24 + 2 * ngen] = g; dbgOut[dbgMax - 23 + 2 * ngen] = n; ngen++; }
    for (u32 i = lo; i < n; i += step) {
      Delta* d = &c.D[base + i];
      u32 owner = AR(d->owner).load(ACQ);
      const bool rec = dbgOut && ngen == 1 && i < 2024;
      if (!owner) { if (rec) dbgOut[1024 + i] = 1; continue; }
      u32 dstop = AR(d->dstop).load(RLX), op = dstop >> 30;
      if (op == OPB_VOID) { if (rec) dbgOut[1024 + i] = 2; continue; }
      int k = createVis(c, d, owner, self, rts);
      if (rec) dbgOut[1024 + i] = 10 + k + (op == OPB_INS ? 0 : 50) + ((k == V_VIS && op == OPB_INS && invalidated(c, d, self, rts)) ? 100 : 0);
      if (mode == 0) {
        if (op == OPB_INS && (k == V_SELF || k == V_VIS) && !invalidated(c, d, self, rts)) {
          if (dbgOut && cnt < 1024) dbgOut[cnt] = base + i;
          cnt++; hx ^= mix32(dstop & 0x3FFFFFFFu);
        }
      } else {
        if (k == V_SELF || k == V_ABORTED) continue;
        if (k == V_VIS) {
          u64 its = c.cfg.m4 ? loadIts(c, d) : AR(d->its).load(ACQ);
          if (its) {
            if (its & TAGBIT) {
              u32 t = (u32)its;
              if (t != self) { int kk = resolveTx(c, t, self, rts); if (kk == V_ACTIVE || kk == V_LATE) bad = true; }
            } else if (its > rts) bad = true;
          }
        } else bad = true;  // pending or committed after snapshot: phantom / concurrent change
      }
    }
    g = pg;
  }
  if (dbgOut && ngen < 12) dbgOut[dbgMax - 24 + 2 * ngen] = 0xFFFFFFFFu;
}

__device__ __forceinline__ u32 log2u(u32 x) { return 31 - __clz(x); }

// Allocate a block record with `cap` slots (power of two) and cap/chRatio heads. With M4 reuse, a block of the same
// size class is popped from the free list (its slots were zeroed and heads reset by the reclaimer before the push);
// otherwise bump-allocated. Returns NOBLK on exhaustion (sets oom flag 1). The record's prevGen/vtx/fill are set here.
__device__ u32 newBlock(const Ctx& c, u32 cap, u32 prevGen, u32 u, u32 kind) {
  u32 nch = cap / c.cfg.chRatio; if (nch < 1) nch = 1;
  if ((c.cfg.m4 & 4) && c.freeHead) {
    u64* fh = &c.freeHead[log2u(cap)];
    for (;;) {
      u64 h = AR(*fh).load(ACQ);
      u32 bid = (u32)h;
      if (bid == NOBLK) break;
      u32 nx = AR(c.B[bid].prevGen).load(RLX);
      if (AR(*fh).compare_exchange_strong(h, (((h >> 32) + 1) << 32) | nx, ACQREL, ACQ)) {
        Block* b = &c.B[bid];  // base/cap/nch/chBase of the class are kept in the record
        b->fill = 0; b->vtx = u; b->pad = kind; AR(b->prevGen).store(prevGen, RLX);
        atomicAdd(&c.m4stats[M4_REUSED], 1u);
        return bid;
      }
    }
  }
  u32 base = atomicAdd(c.dTop, cap), chb = atomicAdd(c.hTop, nch), bid = atomicAdd(c.bTop, 1);
  if ((u64)base + cap > c.dCap || (u64)chb + nch > c.hCap || bid >= c.bCap) { atomicOr(c.oom, 1u); return NOBLK; }
  Block nb; nb.base = base; nb.cap = cap; nb.nch = nch; nb.chBase = chb; nb.fill = 0; nb.prevGen = prevGen; nb.vtx = u; nb.pad = kind;
  c.B[bid] = nb;
  return bid;
}

// Grow vertex u past generation `old` (unique grower). M4 hold-sizing: a generation whose estimated garbage
// (voided slots + aborted linked deltas + 2 per committed delete, counted in Block::fill) is at least half its
// capacity is replaced by one of the SAME size, so a hot vertex full of aborted attempts stops growing geometrically.
__device__ void allocBlock(const Ctx& c, u32 u, u32 old, u32& nGrow) {
  u32 cap;
  if (old >= PENDB) cap = c.cfg.minCap;
  else {
    cap = c.B[old].cap << c.cfg.growShift;
    if ((c.cfg.m4 & 2) && c.B[old].cap >= c.cfg.holdMin && 2u * AR(c.B[old].fill).load(RLX) >= c.B[old].cap) { cap = c.B[old].cap; atomicAdd(&c.m4stats[M4_HOLDS], 1u); }
  }
  u32 bid = newBlock(c, cap, old, u, 0);
  if (bid == NOBLK) return;
  __threadfence();
  AR(c.vcur[u]).store(bid, REL);                  // readers first ...
  AR(c.vfill[u]).store((u64)bid << 32, REL);      // ... then open the generation to writers
  nGrow++;
}

enum InstallRes { IN_EFF = 0, IN_NOOP = 1, IN_ABORT = 2, IN_RESEAL = 3 };

__device__ int install(const Ctx& c, const Op& op, u32 self, u64 rts, u32 g, u32 slot, WalkOut& o, u32& nCasFail, u32& nVoid) {
  Block* b = &c.B[g];
  u32 hs = headSlot(b, op.v);
  Delta* d = &c.D[slot];
  o.cur = NILD; o.present = 0; o.cause = -1;
  u32 h0 = AR(c.H[hs]).load(ACQ);
  int r = 0;
  bool reseal = (h0 & SEAL) != 0;
  if (!reseal) r = walkGens(c, g, h0, op.v, self, rts, true, true, o);
  bool eff = false;
  if (!reseal && r != 2) { bool present = (r == 1) && o.present; eff = (op.type == OP_INS) ? !present : present; }
  if (!eff) {
    d->dstop = (OPB_VOID << 30) | op.v; d->prev = NILD;
    AR(d->owner).store(self, RLX); nVoid++;
    return reseal ? IN_RESEAL : (r == 2 ? IN_ABORT : IN_NOOP);
  }
  d->dstop = ((op.type == OP_INS ? OPB_INS : OPB_DEL) << 30) | op.v;
  d->prev = h0 & NILD; d->cts = 0; d->its = 0;
  // Relaxed: chain walkers see contents through the head CAS (release sequence); scanners only use a
  // delta once it is visible, which is established by the owner's commit release / frontier acquire.
  AR(d->owner).store(self, RLX);
  for (;;) {
    u32 exp = h0;
    if (AR(c.H[hs]).compare_exchange_strong(exp, slot, ACQREL, ACQ)) return IN_EFF;
    nCasFail++;
    bool bad = (exp & SEAL) != 0;
    int rr = 0;
    if (!bad) {
      bool cc = false; WalkOut o2; o2.cause = -1;
      rr = walkChain(c, exp & NILD, h0 & NILD, op.v, self, rts, true, cc, o2);  // only the new prefix
      if (rr == 2) o.cause = o2.cause; else if (rr == 1) o.cause = AB_WW_LATE;
    }
    if (bad || rr) {
      d->dstop = (OPB_VOID << 30) | op.v; nVoid++;
      return bad ? IN_RESEAL : IN_ABORT;
    }
    d->prev = exp & NILD;
    h0 = exp;
  }
}

// ================================================================================================================
// Method 4: generation merging (copy what a snapshot >= m can still need, drop the rest) and block reuse (EBR).
// ================================================================================================================

// Keep predicate for a linked version x, given m <= rts of every active or future attempt (proof L11):
// drop aborted versions, committed DELs at <= m, and committed INS invalidated by a deleter committed at <= m.
// keepDel: a committed DEL at <= m may be dropped only if EVERY older version of its key is inside the merge
// (older INS versions are then dropped too). When generations remain below the merged set (truncated merge), an older
// INS there would be reached by chain walks, which do not consult its -- so DELs are kept (proof L11, truncation).
__device__ __forceinline__ bool keepVersion(const Ctx& c, Delta* x, u64 m, bool keepDel = false) {
  u32 owner = AR(x->owner).load(ACQ);
  u64 cts = AR(x->cts).load(RLX);
  if (!cts) {
    u64 d = AR(c.desc[owner]).load(ACQ);
    if (d == 1) return false;           // aborted
    if (!(d & 2)) return true;          // pending: keep (resolves through desc later)
    cts = d >> 2;
  }
  u32 op = AR(x->dstop).load(RLX) >> 30;
  if (op == OPB_DEL) return keepDel || cts > m;
  u64 its = loadIts(c, x);
  if (!its) return true;
  if (its & TAGBIT) { u64 d = AR(c.desc[(u32)its]).load(ACQ); return !((d & 2) && (d >> 2) <= m); }
  return its > m;
}

// Warp-collective (all 32 lanes, uniform arguments): merge every generation older than `holder` into one new
// generation G* and swing B[holder].prevGen to it. The caller holds cbusy[u]. Steps (proof section 8):
//  1 seal every head of the old generations   2 count kept (K)   3 allocate G* (only fallible step; nothing is
//  modified before it except benign seals)    4 bucket counts per G* chain, exclusive prefix sum
//  5 copy kept versions generation by generation (newest first), forwarding each original's its   6 link buckets
//  7 publish the record, swing prevGen (release)   8 retire the old generations at r = frontier (RMW read)
__device__ void mergeGens(const Ctx& c, u32 u, u32 holder) {
  const u32 lane = threadIdx.x & 31;
  u32 og[32]; u32 ng = 0, rest = NONEB;
  const u32 maxG = (c.cfg.dbg & 1024) ? 2u : 32u;  // dbg 1024: force truncated merges (gate section F)
  { u32 g = loadPrevGen(c, &c.B[holder]);  // stable: only a merge swings prevGen and we hold the vertex lock
    while (g < PENDB && ng < maxG) { og[ng++] = g; g = loadPrevGen(c, &c.B[g]); }
    rest = g; }
  if (ng == 0) return;
  const bool keepDel = rest < PENDB && !(c.cfg.dbg & 2048);  // dbg 2048: mutation -- drop DELs even when truncated
  if (rest < PENDB && lane == 0) atomicAdd(&c.m4stats[M4_TRUNC], 1u);
  // 1. seal
  for (u32 j = 0; j < ng; j++) { Block* b = &c.B[og[j]]; for (u32 i = lane; i < b->nch; i += 32) AR(c.H[b->chBase + i]).fetch_or(SEAL, ACQREL); }
  __syncwarp();
  u64 m = 0; if (lane == 0) m = AR(*c.minAct).load(ACQ);
  m = __shfl_sync(FULLMASK, m, 0);
  if (c.cfg.dbg & 512) m = AR(*c.frontier).load(ACQ);  // mutation: ignore announcements
  // 2. count
  u32 K = 0, linked = 0;
  for (u32 j = 0; j < ng; j++) {
    Block* b = &c.B[og[j]];
    for (u32 h = lane; h < b->nch; h += 32)
      for (u32 x = AR(c.H[b->chBase + h]).load(ACQ) & NILD; x != NILD; x = AR(c.D[x].prev).load(RLX)) { linked++; K += keepVersion(c, &c.D[x], m, keepDel); }
  }
  K = __reduce_add_sync(FULLMASK, K); linked = __reduce_add_sync(FULLMASK, linked);
  // 3. allocate G* (K == 0: nothing survives; prevGen becomes the rest of the list)
  u32 gs = NOBLK, cap = 0, nch = 0, base = 0, chb = 0;
  if (K) {
    cap = c.cfg.minCap; while (cap < K) cap <<= 1;
    if (lane == 0) gs = newBlock(c, cap, rest, u, 1);
    gs = __shfl_sync(FULLMASK, gs, 0);
    if (gs == NOBLK) return;                 // exhaustion: abandon (only seals happened -- benign)
    Block* b = &c.B[gs]; nch = b->nch; base = b->base; chb = b->chBase;
    for (u32 i = lane; i < nch; i += 32) AR(c.H[chb + i]).store(0u, RLX);
    __syncwarp();
    // 4. bucket counts (kept set can only shrink between passes: pending -> aborted; proof L11)
    for (u32 j = 0; j < ng; j++) {
      Block* ob = &c.B[og[j]];
      for (u32 h = lane; h < ob->nch; h += 32)
        for (u32 x = AR(c.H[ob->chBase + h]).load(ACQ) & NILD; x != NILD; x = AR(c.D[x].prev).load(RLX))
          if (keepVersion(c, &c.D[x], m, keepDel)) atomicAdd(&c.H[chb + (mix32(AR(c.D[x].dstop).load(RLX) & 0x3FFFFFFFu) & (nch - 1))], 1u);
    }
    __syncwarp();
    { u32 carry = 0;  // exclusive prefix sum over the bucket counts
      for (u32 i0 = 0; i0 < nch; i0 += 32) {
        u32 i = i0 + lane, v = i < nch ? AR(c.H[chb + i]).load(RLX) : 0, s = v;
        for (u32 o = 1; o < 32; o <<= 1) { u32 t = __shfl_up_sync(FULLMASK, s, o); if (lane >= o) s += t; }
        if (i < nch) AR(c.H[chb + i]).store(carry + s - v, RLX);
        carry += __shfl_sync(FULLMASK, s, 31);
      } }
    __syncwarp();
    // 5. copy, newest generation first; one lane walks a chain newest-first, so per-key order is preserved
    for (u32 j = 0; j < ng; j++) {
      Block* ob = &c.B[og[j]];
      for (u32 h = lane; h < ob->nch; h += 32)
        for (u32 x = AR(c.H[ob->chBase + h]).load(ACQ) & NILD; x != NILD; x = AR(c.D[x].prev).load(RLX)) {
          Delta* d = &c.D[x];
          if (!keepVersion(c, d, m, keepDel)) continue;
          u32 dstop = AR(d->dstop).load(RLX);
          u32 pos = atomicAdd(&c.H[chb + (mix32(dstop & 0x3FFFFFFFu) & (nch - 1))], 1u);
          if (pos >= cap) { atomicOr(c.oom, 32u); atomicAdd(&c.m4stats[M4_OVERFLOW], 1u); continue; }  // impossible (L11): run INVALID
          Delta* y = &c.D[base + pos];
          AR(y->dstop).store(dstop, RLX); AR(y->prev).store(NILD, RLX); AR(y->cts).store(AR(d->cts).load(RLX), RLX);
          if (c.cfg.dbg & 256) AR(y->its).store(AR(d->its).load(ACQ), RLX);  // mutation: copy its without hand-off
          else for (;;) {  // hand-off: after the CAS every update of x's its goes to y (setIts follows FWD)
            u64 w = AR(d->its).load(ACQ);
            AR(y->its).store(w, RLX);
            if (AR(d->its).compare_exchange_strong(w, FWDBIT | (u64)(base + pos), ACQREL, ACQ)) break;
          }
          AR(y->owner).store(AR(d->owner).load(RLX), RLX);
        }
      __syncwarp();  // all of generation j before j+1 (per-key order across generations)
    }
    // 6. link: buckets are contiguous and filled from their start (holes only at bucket ends, owner == 0)
    for (u32 i = lane; i < nch; i += 32) AR(c.H[chb + i]).store(NILD, RLX);
    __syncwarp();
    for (u32 s = lane; s < cap; s += 32) {
      Delta* y = &c.D[base + s];
      u32 ow = AR(y->owner).load(RLX);
      if (!ow) continue;
      u32 ch = mix32(AR(y->dstop).load(RLX) & 0x3FFFFFFFu) & (nch - 1);
      u32 nx = NILD;
      if (s + 1 < cap && AR(c.D[base + s + 1].owner).load(RLX) && (mix32(AR(c.D[base + s + 1].dstop).load(RLX) & 0x3FFFFFFFu) & (nch - 1)) == ch) nx = base + s + 1;
      AR(y->prev).store(nx, RLX);
      bool first = s == 0 || !AR(c.D[base + s - 1].owner).load(RLX) || (mix32(AR(c.D[base + s - 1].dstop).load(RLX) & 0x3FFFFFFFu) & (nch - 1)) != ch;
      if (first) AR(c.H[chb + ch]).store((base + s) | SEAL, RLX);  // G* never takes installs
    }
  }
  // 7. publish: every lane's G* writes -> __syncwarp -> lane 0 SC fence -> release swing (proof L12)
  __syncwarp();
  if (lane == 0) {
    cuda::atomic_thread_fence(SEQ, cuda::thread_scope_device);
    AR(c.B[holder].prevGen).store(K ? gs : rest, REL);
    cuda::atomic_thread_fence(SEQ, cuda::thread_scope_device);
    atomicAdd(&c.m4stats[M4_MERGES], 1u); atomicAdd(&c.m4stats[M4_GENS_MERGED], ng);
    atomicAdd(&c.m4stats[M4_KEPT], K); atomicAdd(&c.m4stats[M4_LINKED], linked);
    // 8. retire: r is read with an RMW after the swing and the SC fence (proof L14)
    if (c.cfg.m4 & 4) {
      u64 r = AR(*c.frontier).fetch_add(0ull, ACQREL);
      for (u32 j = 0; j < ng; j++) {
        u32 t = AR(*c.rTail).load(RLX); bool got = false;
        while (t - AR(*c.rHead).load(ACQ) < c.rCap)  // reserve a ring slot only if one is free (never over-reserve)
          if (AR(*c.rTail).compare_exchange_weak(t, t + 1, ACQREL, RLX)) { got = true; break; }
        if (!got) { atomicAdd(&c.m4stats[M4_RING_FULL], 1u); continue; }  // ring full: this block leaks (counted)
        AR(c.retire[t % c.rCap]).store((r << 32) | og[j], REL);
        atomicAdd(&c.m4stats[M4_RETIRED], 1u);
      }
    }
  }
  __syncwarp();
}

// Reclaimer warp (M4): publishes minAct = min(frontier, announced snapshots) and frees retired blocks whose retire
// epoch is below it. Ordering (proof L14): observe the ring tail, RMW-read the frontier, SC fence, scan announcements.
__device__ void reclaimerLoop(const Ctx& c) {
  const u32 lane = threadIdx.x & 31;
  while (!AR(*c.stop).load(ACQ)) {
    u32 tail = 0; u64 fr = 0;
    if (lane == 0) { tail = AR(*c.rTail).load(ACQ); fr = AR(*c.frontier).fetch_add(0ull, ACQREL); }
    tail = __shfl_sync(FULLMASK, tail, 0); fr = __shfl_sync(FULLMASK, fr, 0);
    __syncwarp();
    cuda::atomic_thread_fence(SEQ, cuda::thread_scope_device);
    u64 m = fr;
    for (u32 i = lane; i < c.nAnn; i += 32) { u64 a = AR(c.ann[i]).load(ACQ); if (a < m) m = a; }
    for (u32 o = 16; o; o >>= 1) { u64 t = __shfl_xor_sync(FULLMASK, m, o); if (t < m) m = t; }
    if (lane == 0) AR(*c.minAct).store(m, REL);
    if (c.cfg.m4 & 4) {  // free retired blocks in ring order while their retire epoch < m
      u32 head = AR(*c.rHead).load(RLX);
      while (head != tail) {
        u64 e = AR(c.retire[head % c.rCap]).load(ACQ);
        if (e == RING_EMPTY || (e >> 32) >= m) break;  // not yet written, or still protected
        u32 bid = (u32)e; Block* b = &c.B[bid];
        // Zero the WHOLE delta: a scanner can read a reused slot's cts/its before the new writer's cts := 0 is visible
        // to it; a stale nonzero cts would decide visibility without the descriptor (found by the gate: SER aborts x10).
        for (u32 s = lane; s < b->cap; s += 32) {
          Delta* z = &c.D[b->base + s];
          AR(z->owner).store(0u, RLX); AR(z->dstop).store(0u, RLX); AR(z->prev).store(0u, RLX);
          AR(z->cts).store(0ull, RLX); AR(z->its).store(0ull, RLX);
        }
        for (u32 i = lane; i < b->nch; i += 32) AR(c.H[b->chBase + i]).store(NILD, RLX);
        __syncwarp();
        if (lane == 0) {
          cuda::atomic_thread_fence(SEQ, cuda::thread_scope_device);
          AR(c.retire[head % c.rCap]).store(RING_EMPTY, RLX);
          u64* fh = &c.freeHead[log2u(b->cap)];
          for (;;) {
            u64 h = AR(*fh).load(ACQ);
            AR(b->prevGen).store((u32)h, RLX);
            if (AR(*fh).compare_exchange_strong(h, (h & 0xFFFFFFFF00000000ull) | bid, ACQREL, ACQ)) break;
          }
          atomicAdd(&c.m4stats[M4_FREED], 1u);
          AR(*c.rHead).store(head + 1, REL);
        }
        head++;
        __syncwarp();
      }
    }
    __nanosleep(2000);
  }
}

__device__ void advancerLoop(const Ctx& c) {
  u32 n = 0;
  const u64 deadline = gtimer() + c.watchdogNs;
  // *E = (epoch << 32) | committers registered in that epoch.  Closing epoch e is one exchange that
  // atomically opens e+1 and returns how many committers registered in e; the frontier is published
  // once exactly that many have signalled completion on done[e & 1].  Committers never retry.
  while (!AR(*c.stop).load(ACQ)) {
    u64 e = AR(*c.E).load(RLX) >> 32;
    u64 old = AR(*c.E).exchange((e + 1) << 32, ACQREL);
    u32 reg = (u32)old;
    // Never publish early: on the deadline only raise the diagnostic flag and keep waiting (publishing
    // a frontier past unfinished committers breaks snapshot reads -- found by the checker).
    bool flagged = false, dead = false;
    while (AR(c.inflight[e & 1]).load(ACQ) != reg) {
      u64 now = gtimer();
      if (!flagged && now > deadline) { atomicOr(c.oom, 4u); flagged = true; }
      if (now > deadline + c.watchdogNs) {  // run is INVALID (flag 16): record the stuck epoch and stop publishing
        c.nextTxn[2] = (u32)e; c.nextTxn[3] = reg; c.nextTxn[4] = AR(c.inflight[e & 1]).load(ACQ);
        atomicOr(c.oom, 16u); dead = true; break;
      }
    }
    if (dead) break;
    AR(c.inflight[e & 1]).store(0u, RLX);  // no one can register in e any more; e+2 reuses the slot
    AR(*c.frontier).store(e, REL);
    n++;
    if (c.cfg.advanceNs) __nanosleep(c.cfg.advanceNs);
  }
  atomicAdd(&c.stats[ST_EPOCHS], n);
}

struct LaneStats { u32 commits, eff, noops, slots, voided, grows, casFail, resv, giveup; u32 ab[AB_NCAUSES]; u64 prof[6]; };
// prof: 0 begin, 1 op loop, 2 install (inside 1), 3 validation, 4 commit, 5 stamping  (SM cycles)

// One attempt of each active lane's transaction. Warp-collective: every lane of the warp calls it.
// Returns true if this lane committed.
__device__ bool attempt(const Ctx& c, bool act, u32 cur, u64& rtsO, u64& ctsO, u32& selfO, int& causeO, LaneStats& st) {
  const u32 lane = threadIdx.x & 31;
  u64 pc0 = clock64();
  u32 self = warpAggInc(c.txTop, act);
  bool alive = act;
  int cause = -1;
  if (act && self >= c.descCap) { alive = false; cause = AB_RESOURCE; }
  u64 rts;
  if (c.cfg.m4) {
    // M4 announce (proof L14): ann := a (frontier), SC fence, rts := frontier re-read (>= a). If the reclaimer's
    // scan misses this announcement, its own RMW-read of the frontier precedes our re-read, so rts >= minAct.
    u64 r0 = 0;
    if (lane == 0) {
      const u32 gw = (blockIdx.x * blockDim.x + threadIdx.x) >> 5;
      u64 a = AR(*c.frontier).load(RLX);
      AR(c.ann[gw]).store(a, RLX);
      cuda::atomic_thread_fence(SEQ, cuda::thread_scope_device);
      r0 = AR(*c.frontier).load(ACQ);
    }
    r0 = __shfl_sync(FULLMASK, r0, 0);
    __syncwarp();  // lane 0's acquire happens-before every lane's reads in this attempt
    rts = act ? r0 : 0;
  } else rts = act ? AR(*c.frontier).load(ACQ) : 0;
  u32 b0 = act ? c.off[cur] : 0, K = act ? c.off[cur + 1] - b0 : 0;
  u32 maxK = __reduce_max_sync(FULLMASK, K);
  u32 nMy = 0, nSup = 0, nRd = 0, nEff = 0, nNoop = 0;
  u32 myD[MAXOPS], sup[MAXOPS], rdU[MAXOPS], rdV[MAXOPS], rdO[MAXOPS];
  u32 myG[MAXOPS];  // M4: block of each own delta (bit 31: it is a DEL) for garbage accounting
  bool doMerge = false; u32 mergeU = 0, mergeH = 0;
  auto obsOwner = [&](u32 x) -> u32 { return (c.cfg.m4 && x != NILD) ? AR(c.D[x].owner).load(RLX) : 0; };

  u64 pc1 = clock64(); st.prof[0] += pc1 - pc0;
  for (u32 j = 0; j < maxK; j++) {
    bool has = alive && j < K;
    Op op; op.type = OP_NOP; op.u = 0; op.v = 0;
    if (has) op = c.ops[b0 + j];

    // ---- adjacency scans
    bool sc = has && op.type == OP_SCAN;
    if (c.cfg.coopScan) {
      u32 m = __ballot_sync(FULLMASK, sc);
      while (m) {
        u32 L = __ffs(m) - 1; m &= m - 1;
        u32 su = __shfl_sync(FULLMASK, op.u, L), ss = __shfl_sync(FULLMASK, self, L);
        u64 sr = __shfl_sync(FULLMASK, rts, L);
        u32 cnt = 0, hx = 0; bool bad = false;
        scanBody(c, su, ss, sr, 0, lane, 32, cnt, hx, bad, nullptr, 0, (c.cfg.dbg & 128) ? -1 : (int)L);
        cnt = __reduce_add_sync(FULLMASK, cnt);
        hx = __reduce_xor_sync(FULLMASK, hx);
        if (lane == L) { OpResult rr; rr.r = cnt; rr.aux = hx; rr.obs = NILD; rr.pad = 0; c.res[b0 + j] = rr; }
      }
    } else if (sc) {
      u32 cnt = 0, hx = 0; bool bad = false;
      u32 doff = 0xFFFFFFFFu; u32* dout = nullptr;
      if (c.dbgBuf) { doff = (b0 + j) * 3072u; if ((u64)doff + 3072 <= c.dbgCap) dout = c.dbgBuf + doff; else doff = 0xFFFFFFFFu; }
      scanBody(c, op.u, self, rts, 0, 0, 1, cnt, hx, bad, dout, 3072);
      OpResult rr; rr.r = cnt; rr.aux = hx; rr.obs = NILD; rr.pad = doff; c.res[b0 + j] = rr;
    }
    if (sc && c.cfg.ser) { rdU[nRd] = op.u; rdV[nRd] = SCANV; rdO[nRd] = NILD; nRd++; }

    // ---- point reads
    if (has && op.type == OP_READ) {
      WalkOut o; walkFromCurrent(c, op.u, op.v, self, rts, false, o);
      OpResult rr; rr.r = o.present; rr.aux = 0; rr.obs = o.cur; rr.pad = obsOwner(o.cur); c.res[b0 + j] = rr;
      if (c.cfg.ser && (o.cur == NILD || c.D[o.cur].owner != self)) { rdU[nRd] = op.u; rdV[nRd] = op.v; rdO[nRd] = o.cur; nRd++; }
    }

    // ---- writes: optimistic pre-walk (no sealing) filters no-ops and certain conflicts
    bool wr = has && (op.type == OP_INS || op.type == OP_DEL);
    bool needSlot = false;
    if (wr) {
      WalkOut o; int r = 1; o.cur = NILD; o.present = (op.type == OP_DEL); o.cause = -1;
      if (c.cfg.prewalk) r = walkFromCurrent(c, op.u, op.v, self, rts, true, o);
      if (r == 2) { alive = false; cause = o.cause; }
      else {
        bool present = (r == 1) && o.present;
        bool eff = (op.type == OP_INS) ? !present : present;
        if (eff) needSlot = true;
        else {
          OpResult rr; rr.r = 0; rr.aux = 0; rr.obs = o.cur; rr.pad = obsOwner(o.cur); c.res[b0 + j] = rr; nNoop++;
          if (c.cfg.ser && (o.cur == NILD || c.D[o.cur].owner != self)) { rdU[nRd] = op.u; rdV[nRd] = op.v; rdO[nRd] = o.cur; nRd++; }
        }
      }
    }

    // ---- reservation + install (collective loop)
    while (__any_sync(FULLMASK, needSlot)) {
      // One fetch_add on the fused (generation, fill) word per (warp, vertex) group returns both the
      // generation and a contiguous slot range. The lane whose slot equals the capacity (or slot 0 of the
      // "no block" generation) is the unique grower; lanes past the capacity wait for the new generation.
      u32 key = needSlot ? op.u : (0xF0000000u | lane);
      u32 grp = c.cfg.coop ? __match_any_sync(FULLMASK, key) : (1u << lane);
      u32 leader = __ffs(grp) - 1, cnt = __popc(grp), rank = __popc(grp & lanemask_lt());
      u64 wv = 0;
      // ACQREL, not relaxed: the reservation must synchronize with the grower's release of the new
      // generation (vcur is stored before vfill), so that everything this txn later publishes carries a
      // happens-before edge to the generation link. With RLX a scanner whose snapshot covers our commit
      // could still load a stale vcur and skip the generation holding our delta (found by the checker).
      if (needSlot && lane == leader) { wv = (c.cfg.dbg & 32) ? AR(c.vfill[op.u]).fetch_add((u64)cnt, RLX) : AR(c.vfill[op.u]).fetch_add((u64)cnt, ACQREL); st.resv++; }
      if (c.cfg.coop) wv = __shfl_sync(FULLMASK, wv, leader);
      u32 g = (u32)(wv >> 32), slot = NILD;
      bool ready = false;
      if (needSlot) {
        u32 s = (u32)wv + rank;
        if (g == NONEB) { if (s == 0) allocBlock(c, op.u, NONEB, st.grows); }
        else {
          Block* bk = &c.B[g];
          if (s < bk->cap) { slot = bk->base + s; ready = true; }
          else if (s == bk->cap) {
            allocBlock(c, op.u, g, st.grows);
            // M4 trigger: the filled generation is garbage-heavy and at least two generations (>= mergeMin slots)
            // lie below it -> this warp merges them (after the install step, warp-collectively).
            if ((c.cfg.m4 & 2) && (c.cfg.mergeOnOldGarbage || 2u * AR(bk->fill).load(RLX) >= bk->cap)) {
              u32 tot = 0, n = 0, garb = 0;
              for (u32 x = loadPrevGen(c, bk); x < PENDB && n < 33; x = loadPrevGen(c, &c.B[x])) { tot += c.B[x].cap; garb += AR(c.B[x].fill).load(RLX); n++; }
              if (n >= 2 && tot >= c.cfg.mergeMin && (!c.cfg.mergeOnOldGarbage || 2u * garb >= tot)) {
                if (atomicCAS(&c.cbusy[op.u], 0u, 1u) == 0u) { doMerge = true; mergeU = op.u; mergeH = g; }
                else atomicAdd(&c.m4stats[M4_LOCK_BUSY], 1u);
              }
            }
          }
        }
        if (!ready && AR(*c.oom).load(RLX)) { needSlot = false; alive = false; cause = AB_RESOURCE; }
      }
      bool voidedHere = false;
      if (slot != NILD) {
        st.slots++;
        WalkOut o;
        u64 pi0 = clock64();
        int ir;
        if (c.cfg.dbg & 1) { Delta* dd = &c.D[slot]; dd->dstop = (OPB_INS << 30) | op.v; dd->prev = NILD; AR(dd->owner).store(self, RLX); o.cur = NILD; ir = IN_EFF; }
        else ir = install(c, op, self, rts, g, slot, o, st.casFail, st.voided);
        st.prof[2] += clock64() - pi0;
        voidedHere = ir != IN_EFF;
        if (ir == IN_EFF) {
          needSlot = false; nEff++;
          myG[nMy] = g | (op.type == OP_DEL ? 0x80000000u : 0u);
          myD[nMy++] = slot;
          u32 oo = obsOwner(o.cur);
          if (op.type == OP_DEL) {
            if (c.cfg.m4) sup[nSup++] = setIts(c, o.cur, TAGBIT | self, 0);  // follows M4 forwarding
            else { AR(c.D[o.cur].its).store(TAGBIT | self, RLX); sup[nSup++] = o.cur; }
          }
          if (!(c.cfg.dbg & 2)) { OpResult rr; rr.r = 1; rr.aux = 0; rr.obs = o.cur; rr.pad = oo; c.res[b0 + j] = rr; }
        } else if (ir == IN_NOOP) {
          needSlot = false; nNoop++;
          OpResult rr; rr.r = 0; rr.aux = 0; rr.obs = o.cur; rr.pad = obsOwner(o.cur); c.res[b0 + j] = rr;
          if (c.cfg.ser && (o.cur == NILD || c.D[o.cur].owner != self)) { rdU[nRd] = op.u; rdV[nRd] = op.v; rdO[nRd] = o.cur; nRd++; }
        } else if (ir == IN_ABORT) { needSlot = false; alive = false; cause = o.cause; }
      } else if (needSlot) {
        __nanosleep(64);  // waiting for a new generation
      }
      if (c.cfg.m4 & 2) {
        // garbage accounting: voided slots, one RMW per (warp, block)
        u32 vk = voidedHere ? g : (0xF0000000u | lane);
        u32 vg = __match_any_sync(FULLMASK, vk);
        if (voidedHere && lane == __ffs(vg) - 1) atomicAdd(&c.B[g].fill, (u32)__popc(vg));
        // pending merges (warp-collective; the grower holds cbusy[mergeU])
        u32 mm = __ballot_sync(FULLMASK, doMerge);
        while (mm) {
          u32 L = __ffs(mm) - 1; mm &= mm - 1;
          u32 mu = __shfl_sync(FULLMASK, mergeU, L), mh = __shfl_sync(FULLMASK, mergeH, L);
          mergeGens(c, mu, mh);
          if (lane == L) AR(c.cbusy[mu]).store(0u, REL);
        }
        doMerge = false;
      }
    }
  }

  u64 pc2 = clock64(); st.prof[1] += pc2 - pc1;
  // ---- commit epoch + serializable validation (writes are already "locked" by pending deltas)
  // Writers register in the open epoch with one fetch_add on (epoch, count).  In serializable mode the
  // epoch is fixed BEFORE read validation (Silo order): any writer U that overwrites something T read
  // installs after T's validation, hence registers after T, so cts(U) >= cts(T) and every dependency
  // edge is non-decreasing in cts.  That makes the frontier snapshot a dependency-closed prefix, which
  // is why transactions without effective writes commit at cts = rts with no validation/registration.
  const bool early = c.cfg.ser != 0 && !(c.cfg.dbg & 16);
  u64 e = 0;
  u32 reg = 0, regLeader = 0;
  // __syncwarp (not ballot/shfl, which carry no memory ordering) makes every lane's earlier actions -- its
  // frontier load (=> e > rts) and its head CASes (=> later registrants' validation sees them) -- happen-before
  // the leader's registration RMW, and the RMW happen-before every lane's validation reads (proof, design/proof.md L6).
  auto registerEpoch = [&](bool want) {
    reg = __ballot_sync(FULLMASK, want);
    if (reg) {
      regLeader = __ffs(reg) - 1;
      if (!(c.cfg.dbg & 64)) __syncwarp();
      if (lane == regLeader) e = AR(*c.E).fetch_add((u64)__popc(reg), ACQREL) >> 32;  // wait-free
      if (!(c.cfg.dbg & 64)) __syncwarp();
      e = __shfl_sync(FULLMASK, e, regLeader);
    }
  };
  if (early) registerEpoch(alive && nMy > 0);
  bool needVal = early && alive && nMy > 0;
  if (c.cfg.ser) {
    for (u32 r = 0; r < nRd && needVal; r++)
      if (rdV[r] != SCANV && !validatePoint(c, rdU[r], rdV[r], rdO[r], self)) { alive = false; needVal = false; cause = AB_SER_POINT; }
    u32 maxR = __reduce_max_sync(FULLMASK, needVal ? nRd : 0);
    for (u32 r = 0; r < maxR; r++) {
      bool isScan = needVal && alive && r < nRd && rdV[r] == SCANV;
      if (c.cfg.coopScan) {
        u32 m = __ballot_sync(FULLMASK, isScan);
        while (m) {
          u32 L = __ffs(m) - 1; m &= m - 1;
          u32 su = __shfl_sync(FULLMASK, isScan ? rdU[r] : 0, L), ss = __shfl_sync(FULLMASK, self, L);
          u64 sr = __shfl_sync(FULLMASK, rts, L);
          u32 cnt = 0, hx = 0; bool bad = false;
          scanBody(c, su, ss, sr, 1, lane, 32, cnt, hx, bad, nullptr, 0, (c.cfg.dbg & 128) ? -1 : (int)L);
          bool anyBad = __any_sync(FULLMASK, bad);
          if (lane == L && anyBad) { alive = false; cause = AB_SER_SCAN; }
        }
      } else if (isScan) {
        u32 cnt = 0, hx = 0; bool bad = false;
        scanBody(c, rdU[r], self, rts, 1, 0, 1, cnt, hx, bad);
        if (bad) { alive = false; cause = AB_SER_SCAN; }
      }
    }
  }
  u64 pc3 = clock64(); st.prof[3] += pc3 - pc2;
  if (!early) registerEpoch(alive && nMy > 0);
  // Read-only commit: serializes at rts and owns no live deltas. Its descriptor must NOT read as
  // COMMITTED(rts): that would make its voided reservation slots "committed in the past" for concurrent
  // scanners (which may still read a pre-void opcode). ABORTED keeps every slot it touched invisible.
  if (alive && nMy == 0) { e = rts; AR(c.desc[self]).store(1ull, RLX); }
  if (reg) {
    __threadfence();  // release pattern: all txn writes ordered before the descriptor publication
    if ((reg >> lane) & 1) AR(c.desc[self]).store(alive ? ((e << 2) | 2) : 1ull, RLX);
    __syncwarp();
    if (lane == regLeader) { __threadfence(); AR(c.inflight[e & 1]).fetch_add((u32)__popc(reg), RLX); }  // done
  }
  if (act && !alive && self < c.descCap) AR(c.desc[self]).store(1ull, REL);
  u64 pc4 = clock64(); st.prof[4] += pc4 - pc3;
  if (alive && c.cfg.stamp) {
    for (u32 i = 0; i < nMy; i++) AR(c.D[myD[i]].cts).store(e, RLX);  // a merged copy keeps cts 0 and resolves via desc
    if (c.cfg.m4) for (u32 i = 0; i < nSup; i++) setIts(c, sup[i], e, TAGBIT | self);
    else for (u32 i = 0; i < nSup; i++) AR(c.D[sup[i]].its).store(e, RLX);
  }
  if ((c.cfg.m4 & 2) && act) {  // garbage accounting: aborted linked deltas; a committed DEL makes ~2 versions dead
    for (u32 i = 0; i < nMy; i++)
      if (!alive) atomicAdd(&c.B[myG[i] & 0x7FFFFFFFu].fill, 1u);
      else if (myG[i] & 0x80000000u) atomicAdd(&c.B[myG[i] & 0x7FFFFFFFu].fill, 2u);
  }
  st.prof[5] += clock64() - pc4;
  if (alive) { st.commits++; st.eff += nEff; st.noops += nNoop; }
  else if (act) st.ab[cause < 0 ? AB_RESOURCE : cause]++;
  rtsO = rts; ctsO = e; selfO = self; causeO = cause;
  return alive;
}

__global__ void kRun(Ctx c) {
  const u32 lane = threadIdx.x & 31;
  const u32 gw = (blockIdx.x * blockDim.x + threadIdx.x) >> 5;
  if (gw == 0) { if (lane == 0) advancerLoop(c); return; }
  if (c.cfg.m4 && gw == 1) { reclaimerLoop(c); return; }  // dedicated warp: never delays the advancer
  LaneStats st; memset(&st, 0, sizeof(st));
  u32 cur = 0xFFFFFFFFu, attempts = 0, backoff = 0, rng = mix32(gw * 32 + lane + 12345);
  bool exhausted = false;
  u64 tBegin = 0;
  const u64 deadline = gtimer() + c.watchdogNs;
  for (;;) {
    bool need = (cur == 0xFFFFFFFFu) && !exhausted;
    u32 idx = warpAggInc(c.nextTxn, need);
    if (need) { if (idx < c.N) { cur = idx; attempts = 0; backoff = 0; tBegin = gtimer(); } else exhausted = true; }
    if (__all_sync(FULLMASK, cur == 0xFFFFFFFFu)) break;
    if (c.watchdogNs && lane == 0 && gtimer() > deadline) atomicOr(c.oom, 2u);
    bool act = (cur != 0xFFFFFFFFu) && backoff == 0;
    if (cur != 0xFFFFFFFFu && backoff) backoff--;
    if (__all_sync(FULLMASK, !act)) { __nanosleep(100); continue; }
    u64 rts, cts; u32 self; int cause;
    bool ok = attempt(c, act, cur, rts, cts, self, cause, st);
    if (act) {
      attempts++;
      if (ok) {
        TxRecord r; r.rts = rts; r.cts = cts; r.txid = self; r.attempts = attempts; r.tBegin = tBegin; r.tEnd = gtimer();
        c.rec[cur] = r; cur = 0xFFFFFFFFu;
      } else if (attempts >= c.cfg.maxAttempts || cause == AB_RESOURCE || (AR(*c.oom).load(RLX) & 2u)) {
        TxRecord r; r.rts = 0; r.cts = 0; r.txid = 0; r.attempts = attempts; r.tBegin = tBegin; r.tEnd = gtimer();
        c.rec[cur] = r; cur = 0xFFFFFFFFu; st.giveup++;
      } else {
        rng = mix32(rng + attempts);
        u32 sh = attempts < 8 ? attempts : 8;
        backoff = rng & ((1u << sh) - 1);
      }
    }
  }
  // flush stats
  u32 vals[ST_N]; for (int i = 0; i < ST_N; i++) vals[i] = 0;
  vals[ST_COMMITS] = st.commits; vals[ST_EFFECTIVE] = st.eff; vals[ST_NOOPS] = st.noops; vals[ST_SLOTS] = st.slots;
  vals[ST_VOIDED] = st.voided; vals[ST_GROWTHS] = st.grows; vals[ST_CAS_FAIL] = st.casFail; vals[ST_GIVEUP] = st.giveup;
  vals[ST_RESV_ATOMICS] = st.resv;
  for (int i = 0; i < 6; i++) vals[24 + i] = (u32)(st.prof[i] >> 10);  // kilocycles, summed over lanes
  u32 ab = 0; for (int i = 0; i < AB_NCAUSES; i++) { vals[ST_ABORT_BASE + i] = st.ab[i]; ab += st.ab[i]; }
  vals[ST_ABORTS] = ab;
  for (int i = 0; i < ST_N; i++) { u32 s = __reduce_add_sync(FULLMASK, vals[i]); if (lane == 0 && s) atomicAdd(&c.stats[i], s); }
  if (c.cfg.m4 && lane == 0) AR(c.ann[gw]).store(ANN_IDLE, REL);  // holds no references any more
  if (lane == 0) { u32 d = atomicAdd(c.doneWarps, 1); if (d + 1 == c.nWorkWarps) AR(*c.stop).store(1u, REL); }
}

__global__ void kFill64(u64* p, u32 n, u64 v) { for (u32 i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += gridDim.x * blockDim.x) p[i] = v; }
__global__ void kFill(u32* p, u32 n, u32 v) { for (u32 i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += gridDim.x * blockDim.x) p[i] = v; }

// ------------------------------------------------------------------------------------------------
// Host wrapper
// ---- M5: quiescent compaction (design §7 M5, proof §9) ----
// Runs only between kernel launches, after publishAll(): no attempt is active and every committed version has an
// epoch <= F. Plain loads suffice (the kernel boundary orders all memory). M4 must be off (no forwarding words).
// Visibility at F is the host rule of Store::visibleEdges, so "live" here is exactly what a scan at F returns.
__device__ __forceinline__ bool qcCommittedLE(const Ctx& c, u32 o, u64 F) {
  u64 ds = o < c.descCap ? c.desc[o] : 0;
  return (ds & 2) && (ds >> 2) <= F;
}
__device__ __forceinline__ bool qcVisible(const Ctx& c, const Delta& d, u64 F) {
  if (!d.owner || (d.dstop >> 30) != OPB_INS) return false;
  if (!(d.cts ? d.cts <= F : qcCommittedLE(c, d.owner, F))) return false;
  if (c.cfg.dbg & 8192) return true;  // mutation: keep invalidated versions
  if (!d.its) return true;
  return (d.its & TAGBIT) ? !qcCommittedLE(c, (u32)d.its, F) : d.its > F;
}
__host__ __device__ __forceinline__ u32 qcCap(u32 n, const Cfg& cfg) {
  u64 need = (u64)n + 1 + (u64)n * cfg.qcSlackPct / 100;
  if (need < cfg.minCap) need = cfg.minCap;
  u32 cap = 1; while (cap < need) cap <<= 1;
  return cap;
}
// gather = 0: cnt[u] = live versions of u.  gather = 1: write their destinations to tmp[toff[u] ...].
// skip != nullptr (hybrid): only vertices with skip[u] == ~0 (small) are handled here; big ones go to the chunk kernels.
__global__ void kQcScan(Ctx c, u64 F, u32* cnt, const u32* toff, u32* tmp, int gather, const u32* skip = nullptr) {
  const u32 lane = threadIdx.x & 31, lt = (1u << lane) - 1;
  const u32 gw = (blockIdx.x * blockDim.x + threadIdx.x) >> 5, nw = (gridDim.x * blockDim.x) >> 5;
  for (u32 u = gw; u < c.V; u += nw) {
    if (skip && skip[u] != 0xFFFFFFFFu) continue;
    const bool dropOne = (c.cfg.dbg & 4096) && (u % 61 == 0);  // mutation: lose the first live edge
    const u32 out = gather ? toff[u] : 0;
    const u64 vf = c.vfill[u];
    u32 n = 0;
    for (u32 g = c.vcur[u]; g < PENDB; g = c.B[g].prevGen) {
      const Block b = c.B[g];
      u32 f = ((u32)(vf >> 32) == g) ? (u32)vf : b.cap; if (f > b.cap) f = b.cap;
      for (u32 i0 = 0; i0 < f; i0 += 32) {
        const u32 i = i0 + lane;
        bool vis = false; u32 dst = 0;
        if (i < f) { const Delta d = c.D[b.base + i]; vis = qcVisible(c, d, F); dst = d.dstop & 0x3FFFFFFFu; }
        const u32 m = __ballot_sync(FULLMASK, vis);
        if (gather && vis) {
          u32 pos = n + __popc(m & lt);
          if (!(dropOne && pos == 0)) tmp[out + pos - (dropOne ? 1 : 0)] = dst;
        }
        n += __popc(m);
      }
    }
    if (dropOne && n) n--;
    if (!gather && lane == 0) cnt[u] = n;
  }
}
__global__ void kQcSize(u32 V, Cfg cfg, u32* cnt, u32* capA, u32* nchA, u32* bA, const u32* cur) {
  for (u32 u = blockIdx.x * blockDim.x + threadIdx.x; u < V; u += gridDim.x * blockDim.x) {
    if (cfg.qcChunk && (cfg.dbg & 4096) && u % 61 == 0 && cnt[u] && cur[u] != 0xFFFFFFFFu) cnt[u]--;  // mutation, big vertex
    u32 n = cnt[u], cap = n ? qcCap(n, cfg) : 0, nch = n ? (cap / cfg.chRatio ? cap / cfg.chRatio : 1) : 0;
    capA[u] = cap; nchA[u] = nch; bA[u] = n ? 1 : 0;
  }
}
// Rebuild after reset (heads are NILD, vertices have no block): one generation per live vertex, every version a
// committed INS of the loader txid 1 at epoch 1. Chain order is irrelevant: each destination occurs once.
__global__ void kQcBuild(Ctx c, const u32* cnt, const u32* toff, const u32* capOff, const u32* nchOff, const u32* bidOff,
                         const u32* tmp) {
  const u32 lane = threadIdx.x & 31;
  const u32 gw = (blockIdx.x * blockDim.x + threadIdx.x) >> 5, nw = (gridDim.x * blockDim.x) >> 5;
  for (u32 u = gw; u < c.V; u += nw) {
    const u32 n = cnt[u];
    if (!n) continue;
    const u32 cap = qcCap(n, c.cfg), nch = cap / c.cfg.chRatio ? cap / c.cfg.chRatio : 1;
    const u32 base = capOff[u], chb = nchOff[u], bid = bidOff[u], t0 = toff[u];
    for (u32 j = lane; j < n; j += 32) {
      const u32 v = tmp[t0 + j], s = base + j;
      Delta& d = c.D[s];
      d.dstop = (OPB_INS << 30) | v; d.owner = 1; d.pad = 0; d.cts = 1; d.its = 0;
      d.prev = atomicExch(&c.H[chb + (mix32(v) & (nch - 1))], s);
    }
    if (lane == 0) {
      Block nb; nb.base = base; nb.cap = cap; nb.nch = nch; nb.chBase = chb; nb.fill = 0; nb.prevGen = NONEB; nb.vtx = u; nb.pad = 0;
      c.B[bid] = nb; c.vcur[u] = bid; c.vfill[u] = ((u64)bid << 32) | n;
    }
  }
}

// ---- M5 load-balanced kernels (qcChunk = 1): work is split into fixed chunks of QC_CH slots of one generation, so a
// hub vertex is spread over many warps. Positions within a vertex come from a per-vertex atomic cursor: order is
// irrelevant because each live destination occurs once (proof L16).
constexpr u32 QC_CH = 512, QC_ST = QC_CH / 32;
__device__ __forceinline__ u32 qcGenFill(const Ctx& c, u32 g, u64 vf) {
  const u32 cap = c.B[g].cap; u32 f = ((u32)(vf >> 32) == g) ? (u32)vf : cap;
  return f < cap ? f : cap;
}
// thread per vertex: chunk count of its chain; also clears cnt/cur
__global__ void kQcChCount(Ctx c, u32* chN, u32* cnt, u32* cur, u32* big, u32* nBig) {
  for (u32 u = blockIdx.x * blockDim.x + threadIdx.x; u < c.V; u += gridDim.x * blockDim.x) {
    const u64 vf = c.vfill[u]; u32 n = 0, tot = 0;
    for (u32 g = c.vcur[u]; g < PENDB; g = c.B[g].prevGen) { const u32 f = qcGenFill(c, g, vf); tot += f; n += (f + QC_CH - 1) / QC_CH; }
    if (tot <= c.cfg.qcBigSlots) { chN[u] = 0; cur[u] = 0xFFFFFFFFu; continue; }  // small: legacy warp-per-vertex kernels
    chN[u] = n; cnt[u] = 0; cur[u] = 0; big[atomicAdd(nBig, 1u)] = u;
  }
}
__global__ void kQcChEmit(Ctx c, const u32* chOff, const u32* cur, uint4* ch) {
  for (u32 u = blockIdx.x * blockDim.x + threadIdx.x; u < c.V; u += gridDim.x * blockDim.x) {
    if (cur[u] == 0xFFFFFFFFu) continue;
    const u64 vf = c.vfill[u]; u32 k = chOff[u];
    for (u32 g = c.vcur[u]; g < PENDB; g = c.B[g].prevGen) {
      const u32 f = qcGenFill(c, g, vf), base = c.B[g].base;
      for (u32 i0 = 0; i0 < f; i0 += QC_CH) ch[k++] = make_uint4(base + i0, f - i0 < QC_CH ? f - i0 : QC_CH, u, 0);
    }
  }
}
// warp per chunk. gather = 0: cnt[u] += live slots. gather = 1: write destinations to tmp[toff[u] + cursor].
__global__ void kQcChScan(Ctx c, u64 F, const uint4* ch, u32 nCh, u32* cnt, u32* cur, const u32* toff, u32* tmp, int gather) {
  const u32 lane = threadIdx.x & 31, lt = (1u << lane) - 1;
  const u32 gw = (blockIdx.x * blockDim.x + threadIdx.x) >> 5, nw = (gridDim.x * blockDim.x) >> 5;
  for (u32 k = gw; k < nCh; k += nw) {
    const uint4 q = ch[k];  // x = first slot, y = length, z = vertex
    u32 m[QC_ST], dst[QC_ST], tot = 0;
#pragma unroll
    for (u32 s = 0; s < QC_ST; s++) {
      const u32 i = s * 32 + lane; bool vis = false; dst[s] = 0;
      if (i < q.y) { const Delta d = c.D[q.x + i]; vis = qcVisible(c, d, F); dst[s] = d.dstop & 0x3FFFFFFFu; }
      m[s] = __ballot_sync(FULLMASK, vis); tot += __popc(m[s]);
    }
    if (!tot) continue;
    if (!gather) { if (lane == 0) atomicAdd(&cnt[q.z], tot); continue; }
    u32 b = 0; if (lane == 0) b = atomicAdd(&cur[q.z], tot);
    b = __shfl_sync(FULLMASK, b, 0);
    const bool dropOne = (c.cfg.dbg & 4096) && (q.z % 61 == 0);  // mutation: lose one live edge
    const u32 out = toff[q.z];
#pragma unroll
    for (u32 s = 0; s < QC_ST; s++) {
      if ((m[s] >> lane) & 1) {
        const u32 pos = b + __popc(m[s] & lt);
        if (!dropOne) tmp[out + pos]= dst[s]; else if (pos) tmp[out + pos - 1] = dst[s];
      }
      b += __popc(m[s]);
    }
  }
}
// thread per vertex, after reset: block record and vertex words (vertices without live edges get no block)
__global__ void kQcBlocks(Ctx c, const u32* cnt, const u32* capOff, const u32* nchOff, const u32* bidOff) {
  for (u32 u = blockIdx.x * blockDim.x + threadIdx.x; u < c.V; u += gridDim.x * blockDim.x) {
    const u32 n = cnt[u];
    if (!n) { c.vcur[u] = NONEB; c.vfill[u] = (u64)NONEB << 32; continue; }
    const u32 cap = qcCap(n, c.cfg), nch = cap / c.cfg.chRatio ? cap / c.cfg.chRatio : 1, bid = bidOff[u];
    Block nb; nb.base = capOff[u]; nb.cap = cap; nb.nch = nch; nb.chBase = nchOff[u]; nb.fill = 0; nb.prevGen = NONEB; nb.vtx = u; nb.pad = 0;
    c.B[bid] = nb; c.vcur[u] = bid; c.vfill[u] = ((u64)bid << 32) | n;
  }
}
__device__ __forceinline__ void qcPut(const Ctx& c, u32 s, u32 j, u32 n, u32 nch, u32 chb, const u32* src) {
  Delta d; d.pad = 0; d.its = 0;
  if (j < n) {
    const u32 v = src[j];
    d.dstop = (OPB_INS << 30) | v; d.owner = 1; d.cts = 1;
    d.prev = atomicExch(&c.H[chb + (mix32(v) & (nch - 1))], s);
  } else { d.dstop = 0; d.owner = 0; d.cts = 0; d.prev = 0; }  // slack slot: fresh-arena state
  c.D[s] = d;
}
// small vertices: one warp each, all cap slots written (live ones + zeroed slack)
__global__ void kQcBuildSmall(Ctx c, const u32* cnt, const u32* toff, const u32* capOff, const u32* nchOff, const u32* tmp, const u32* cur) {
  const u32 lane = threadIdx.x & 31;
  const u32 gw = (blockIdx.x * blockDim.x + threadIdx.x) >> 5, nw = (gridDim.x * blockDim.x) >> 5;
  for (u32 u = gw; u < c.V; u += nw) {
    const u32 n = cnt[u];
    if (!n || cur[u] != 0xFFFFFFFFu) continue;
    const u32 cap = qcCap(n, c.cfg), nch = cap / c.cfg.chRatio ? cap / c.cfg.chRatio : 1;
    for (u32 j = lane; j < cap; j += 32) qcPut(c, capOff[u] + j, j, n, nch, nchOff[u], tmp + toff[u]);
  }
}
// big vertices: one thread block each
__global__ void kQcBuildBig(Ctx c, const u32* big, u32 nBig, const u32* cnt, const u32* toff, const u32* capOff, const u32* nchOff, const u32* tmp) {
  for (u32 k = blockIdx.x; k < nBig; k += gridDim.x) {
    const u32 u = big[k], n = cnt[u];
    if (!n) continue;
    const u32 cap = qcCap(n, c.cfg), nch = cap / c.cfg.chRatio ? cap / c.cfg.chRatio : 1;
    for (u32 j = threadIdx.x; j < cap; j += blockDim.x) qcPut(c, capOff[u] + j, j, n, nch, nchOff[u], tmp + toff[u]);
  }
}

struct Store {
  Ctx c{};
  u32 *dStats = nullptr;
  u32 V, dCap, hCap, bCap, descCap;
  int gridBlocks = 0, blockThreads = 128;
  u32 txidBaseOfRun = 1;
  // M5 buffers (allocated on first compaction, kept): 5 per-vertex arrays + 4 B per live edge
  u32 *qcCnt = nullptr, *qcToff = nullptr, *qcCapA = nullptr, *qcNchA = nullptr, *qcBA = nullptr, *qcTmp = nullptr;
  size_t qcTmpCap = 0;
  u32 *qcChN = nullptr, *qcCur = nullptr, *qcBig = nullptr; uint4* qcCh = nullptr; size_t qcChCap = 0;
  size_t qcBytes() const { return (qcCnt ? (size_t)V * 20 : 0) + qcTmpCap * 4 + (qcChN ? (size_t)V * 12 + 4 : 0) + qcChCap * 16; }

  void init(u32 V_, u32 dCap_, u32 descCap_, Cfg cfg) {
    V = V_; dCap = dCap_; hCap = dCap_ + 1024; bCap = V_ * 24 + 1024; descCap = descCap_;
    c.V = V; c.cfg = cfg; c.watchdogNs = 20ull * 1000000000ull;
    CK(cudaMalloc(&c.vcur, (size_t)V * 4));
    CK(cudaMalloc(&c.vfill, (size_t)V * 8));
    CK(cudaMalloc(&c.B, (size_t)bCap * sizeof(Block)));
    CK(cudaMalloc(&c.D, (size_t)dCap * sizeof(Delta)));
    CK(cudaMalloc(&c.H, (size_t)hCap * 4));
    CK(cudaMalloc(&c.desc, (size_t)descCap * 8));
    u32* ctrs; CK(cudaMalloc(&ctrs, 64 * 4)); // counters block (>= 4KB-safe staging not needed: D2D read below)
    c.bTop = ctrs + 0; c.dTop = ctrs + 1; c.hTop = ctrs + 2; c.txTop = ctrs + 3; c.inflight = ctrs + 4;
    c.stop = ctrs + 6; c.oom = ctrs + 7; c.nextTxn = ctrs + 8; c.doneWarps = ctrs + 9;
    u64* e64; CK(cudaMalloc(&e64, 4 * 8)); c.E = e64; c.frontier = e64 + 1; c.minAct = e64 + 2;
    CK(cudaMalloc(&dStats, ST_N * 4)); c.stats = dStats;
    c.bCap = bCap; c.dCap = dCap; c.hCap = hCap; c.descCap = descCap;
    // M4 structures (small; allocated unconditionally so a Store can switch m4 between runs)
    c.rTail = ctrs + 20; c.rHead = ctrs + 21; c.rCap = 1u << 20;
    CK(cudaMalloc(&c.cbusy, (size_t)V * 4)); CK(cudaMalloc(&c.retire, (size_t)c.rCap * 8));
    CK(cudaMalloc(&c.freeHead, 32 * 8)); CK(cudaMalloc(&c.m4stats, M4_N * 4));
    int dev; CK(cudaGetDevice(&dev)); cudaDeviceProp p; CK(cudaGetDeviceProperties(&p, dev));
    int perSM = 0; CK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&perSM, kRun, blockThreads, 0));
    gridBlocks = p.multiProcessorCount * (perSM > 0 ? perSM : 1);
    c.nAnn = (u32)gridBlocks * (blockThreads / 32); CK(cudaMalloc(&c.ann, (size_t)c.nAnn * 8));
    reset();
  }
  void release() {
    cudaFree(c.vcur); cudaFree(c.vfill); cudaFree(c.B); cudaFree(c.D); cudaFree(c.H); cudaFree(c.desc); cudaFree(c.bTop); cudaFree(c.E); cudaFree(dStats);
    cudaFree(c.cbusy); cudaFree(c.retire); cudaFree(c.freeHead); cudaFree(c.m4stats); cudaFree(c.ann);
    if (qcCnt) { cudaFree(qcCnt); cudaFree(qcToff); cudaFree(qcCapA); cudaFree(qcNchA); cudaFree(qcBA); }
    if (qcTmp) cudaFree(qcTmp);
    if (qcChN) { cudaFree(qcChN); cudaFree(qcCur); cudaFree(qcBig); }
    if (qcCh) cudaFree(qcCh);
    qcCnt = qcTmp = qcChN = qcCur = qcBig = nullptr; qcCh = nullptr; qcTmpCap = qcChCap = 0;
  }
  void m4Stats(u32* out) { CK(cudaMemcpy(out, c.m4stats, M4_N * 4, cudaMemcpyDeviceToHost)); }
  void reset() {
    CK(cudaMemset(c.vcur, 0xFF, (size_t)V * 4));
    kFill64<<<1024, 256>>>(c.vfill, V, (u64)NONEB << 32); CK(cudaGetLastError());
    CK(cudaMemset(c.D, 0, (size_t)dCap * sizeof(Delta)));
    kFill<<<1024, 256>>>(c.H, hCap, NILD); CK(cudaGetLastError());
    CK(cudaMemset(c.desc, 0, (size_t)descCap * 8));
    CK(cudaMemset(c.bTop, 0, 64 * 4));
    u32 one = 1; CK(cudaMemcpy(c.txTop, &one, 4, cudaMemcpyHostToDevice));  // txid 0 invalid
    u64 ef[3] = {2ull << 32, 1, 0}; CK(cudaMemcpy(c.E, ef, 24, cudaMemcpyHostToDevice));  // epoch 2 open, frontier 1, minAct 0
    CK(cudaMemset(c.cbusy, 0, (size_t)V * 4)); CK(cudaMemset(c.retire, 0xFF, (size_t)c.rCap * 8));
    CK(cudaMemset(c.freeHead, 0xFF, 32 * 8)); CK(cudaMemset(c.m4stats, 0, M4_N * 4));
    CK(cudaMemset(c.ann, 0xFF, (size_t)c.nAnn * 8));
    CK(cudaDeviceSynchronize());
  }
  // Host bulk load (quiescent, after reset): one generation per vertex with cap = max(minCap, pow2ceil(deg + 1)),
  // every initial edge an INS version committed by loader txid 1 at epoch 1 (= the initial frontier).
  // Equivalent to the state after loading the edges with single-insert transactions and stamping, except for layout.
  void bulkLoad(const std::vector<std::pair<u32, u32>>& edges) {
    std::vector<u32> deg(V, 0);
    for (auto& e : edges) deg[e.first]++;
    std::vector<Block> hb; std::vector<u32> hvcur(V, 0xFFFFFFFFu); std::vector<u64> hvfill(V, (u64)NONEB << 32);
    std::vector<u32> base(V), chb(V), nchv(V), fill(V, 0);
    u64 dT = 0, hT = 0;
    for (u32 u = 0; u < V; u++) {
      if (!deg[u]) continue;
      u32 need = deg[u] + 1 > c.cfg.minCap ? deg[u] + 1 : c.cfg.minCap, cap = 1; while (cap < need) cap <<= 1;
      u32 nch = cap / c.cfg.chRatio; if (nch < 1) nch = 1;
      Block b; b.base = (u32)dT; b.cap = cap; b.nch = nch; b.chBase = (u32)hT; b.fill = 0; b.prevGen = NONEB; b.vtx = u; b.pad = 0;
      base[u] = b.base; chb[u] = b.chBase; nchv[u] = nch;
      hvcur[u] = (u32)hb.size(); hvfill[u] = ((u64)hb.size() << 32) | deg[u];
      hb.push_back(b); dT += cap; hT += nch;
    }
    if (dT > dCap || hT > hCap || hb.size() > bCap) { fprintf(stderr, "bulkLoad: arena too small (need %llu slots)\n", (unsigned long long)dT); exit(2); }
    std::vector<Delta> hd(dT); std::vector<u32> hh(hT, NILD);
    memset(hd.data(), 0, hd.size() * sizeof(Delta));
    for (auto& e : edges) {
      u32 u = e.first, s = base[u] + fill[u]++;
      u32 hs = chb[u] + (mix32(e.second) & (nchv[u] - 1));
      Delta& d = hd[s]; d.dstop = (OPB_INS << 30) | e.second; d.prev = hh[hs]; d.owner = 1; d.pad = 0; d.cts = 1; d.its = 0;
      hh[hs] = s;
    }
    if (!hb.empty()) CK(cudaMemcpy(c.B, hb.data(), hb.size() * sizeof(Block), cudaMemcpyHostToDevice));
    if (dT) CK(cudaMemcpy(c.D, hd.data(), dT * sizeof(Delta), cudaMemcpyHostToDevice));
    if (hT) CK(cudaMemcpy(c.H, hh.data(), hT * 4, cudaMemcpyHostToDevice));
    CK(cudaMemcpy(c.vcur, hvcur.data(), (size_t)V * 4, cudaMemcpyHostToDevice));
    CK(cudaMemcpy(c.vfill, hvfill.data(), (size_t)V * 8, cudaMemcpyHostToDevice));
    u64 committed1 = (1ull << 2) | 2; CK(cudaMemcpy(c.desc + 1, &committed1, 8, cudaMemcpyHostToDevice));
    u32 tops[4] = {(u32)hb.size(), (u32)dT, (u32)hT, 2}; CK(cudaMemcpy(c.bTop, tops, 16, cudaMemcpyHostToDevice));
    CK(cudaDeviceSynchronize());
  }

  // Publish everything committed so far (host-side frontier advance between runs).
  void publishAll() {
    u64 ef[2]; CK(cudaMemcpy(ef, c.E, 16, cudaMemcpyDeviceToHost));
    u64 e = ef[0] >> 32;  // kernel finished: every registration in e has completed
    u64 nf[2] = {(e + 1) << 32, e}; CK(cudaMemcpy(c.E, nf, 16, cudaMemcpyHostToDevice));
    CK(cudaMemset(c.inflight, 0, 8));
  }
  u64 frontier() { u64 ef[2]; CK(cudaMemcpy(ef, c.E, 16, cudaMemcpyDeviceToHost)); return ef[1]; }

  // M5: compact at a launch boundary (quiescent). Afterwards the store is exactly the bulk-loaded state of the graph
  // visible at F: versions, blocks, heads, descriptors, txids and epochs all restart. Returns false (store untouched)
  // if the live graph does not fit the arena. Requires cfg.m4 == 0.
  struct QcOut { bool ok = false; float ms = 0; u64 live = 0; u32 dBefore = 0, dAfter = 0, txBefore = 0, blocks = 0; };
  QcOut compact() {
    QcOut q;
    if (c.cfg.m4) { fprintf(stderr, "compact: requires m4 = 0\n"); exit(2); }
    publishAll();
    cudaEvent_t a, b; CK(cudaEventCreate(&a)); CK(cudaEventCreate(&b)); CK(cudaEventRecord(a));
    u64 F = frontier();
    if (c.cfg.dbg & 16384) F -= 1;  // mutation: compact one epoch too early (normally not observable, see gate I)
    if (c.cfg.dbg & 32768) F /= 2;  // mutation: compact at a stale frontier
    u32 tops[4]; CK(cudaMemcpy(tops, c.bTop, 16, cudaMemcpyDeviceToHost));
    q.dBefore = tops[1] < dCap ? tops[1] : dCap; q.txBefore = tops[3];
    if (!qcCnt) {
      CK(cudaMalloc(&qcCnt, (size_t)V * 4)); CK(cudaMalloc(&qcToff, (size_t)V * 4)); CK(cudaMalloc(&qcCapA, (size_t)V * 4));
      CK(cudaMalloc(&qcNchA, (size_t)V * 4)); CK(cudaMalloc(&qcBA, (size_t)V * 4));
    }
    const int TB = 256, GB = gridBlocks * 4;
    CK(cudaDeviceSynchronize()); auto qt0 = std::chrono::steady_clock::now();
    u32 nCh = 0, nBig = 0;
    if (c.cfg.qcChunk) {
      if (!qcChN) { CK(cudaMalloc(&qcChN, (size_t)V * 4)); CK(cudaMalloc(&qcCur, (size_t)V * 4)); CK(cudaMalloc(&qcBig, (size_t)V * 4 + 4)); }
      CK(cudaMemset(qcBig + V, 0, 4));
      kQcChCount<<<GB, TB>>>(c, qcChN, qcCnt, qcCur, qcBig, qcBig + V); CK(cudaGetLastError());
      CK(cudaMemcpy(&nBig, qcBig + V, 4, cudaMemcpyDeviceToHost));
      u32 lastCh, offCh; CK(cudaMemcpy(&lastCh, qcChN + V - 1, 4, cudaMemcpyDeviceToHost));
      thrust::exclusive_scan(thrust::device, qcChN, qcChN + V, qcChN);
      CK(cudaMemcpy(&offCh, qcChN + V - 1, 4, cudaMemcpyDeviceToHost)); nCh = offCh + lastCh;
      if (nCh > qcChCap || !qcCh) { if (qcCh) cudaFree(qcCh); qcChCap = nCh + nCh / 4 + 1024; CK(cudaMalloc(&qcCh, qcChCap * 16)); }
      kQcChEmit<<<GB, TB>>>(c, qcChN, qcCur, qcCh); CK(cudaGetLastError());
      kQcScan<<<GB, TB>>>(c, F, qcCnt, nullptr, nullptr, 0, qcCur); CK(cudaGetLastError());
      if (nCh) { kQcChScan<<<GB, TB>>>(c, F, qcCh, nCh, qcCnt, qcCur, nullptr, nullptr, 0); CK(cudaGetLastError()); }
    } else {
      kQcScan<<<GB, TB>>>(c, F, qcCnt, nullptr, nullptr, 0); CK(cudaGetLastError());
    }
    if (getenv("GTX_QCPROF")) { CK(cudaDeviceSynchronize()); auto t1 = std::chrono::steady_clock::now(); fprintf(stderr, "QCPROF %s %.3f ms\n", "scan1", std::chrono::duration<double, std::milli>(t1 - qt0).count()); qt0 = t1; }
    kQcSize<<<GB, TB>>>(V, c.cfg, qcCnt, qcCapA, qcNchA, qcBA, qcCur); CK(cudaGetLastError());
    u32 lastCnt, lastCap, lastNch, lastB;
    CK(cudaMemcpy(&lastCnt, qcCnt + V - 1, 4, cudaMemcpyDeviceToHost)); CK(cudaMemcpy(&lastCap, qcCapA + V - 1, 4, cudaMemcpyDeviceToHost));
    CK(cudaMemcpy(&lastNch, qcNchA + V - 1, 4, cudaMemcpyDeviceToHost)); CK(cudaMemcpy(&lastB, qcBA + V - 1, 4, cudaMemcpyDeviceToHost));
    thrust::exclusive_scan(thrust::device, qcCnt, qcCnt + V, qcToff);
    thrust::exclusive_scan(thrust::device, qcCapA, qcCapA + V, qcCapA);
    thrust::exclusive_scan(thrust::device, qcNchA, qcNchA + V, qcNchA);
    thrust::exclusive_scan(thrust::device, qcBA, qcBA + V, qcBA);
    if (getenv("GTX_QCPROF")) { CK(cudaDeviceSynchronize()); auto t1 = std::chrono::steady_clock::now(); fprintf(stderr, "QCPROF %s %.3f ms\n", "size+scans", std::chrono::duration<double, std::milli>(t1 - qt0).count()); qt0 = t1; }
    u32 offs[4];
    CK(cudaMemcpy(&offs[0], qcToff + V - 1, 4, cudaMemcpyDeviceToHost)); CK(cudaMemcpy(&offs[1], qcCapA + V - 1, 4, cudaMemcpyDeviceToHost));
    CK(cudaMemcpy(&offs[2], qcNchA + V - 1, 4, cudaMemcpyDeviceToHost)); CK(cudaMemcpy(&offs[3], qcBA + V - 1, 4, cudaMemcpyDeviceToHost));
    const u64 live = (u64)offs[0] + lastCnt, dT = (u64)offs[1] + lastCap, hT = (u64)offs[2] + lastNch, nb = (u64)offs[3] + lastB;
    if (dT > dCap || hT > hCap || nb > bCap) {
      CK(cudaEventDestroy(a)); CK(cudaEventDestroy(b));
      fprintf(stderr, "compact: live graph does not fit (%llu slots, arena %u)\n", (unsigned long long)dT, dCap);
      return q;
    }
    if (live > qcTmpCap) {
      if (qcTmp) cudaFree(qcTmp);
      qcTmpCap = live + live / 4 + 1024; CK(cudaMalloc(&qcTmp, qcTmpCap * 4));
    }
    if (c.cfg.qcChunk) {
      kQcScan<<<GB, TB>>>(c, F, qcCnt, qcToff, qcTmp, 1, qcCur); CK(cudaGetLastError());
      if (nCh) { kQcChScan<<<GB, TB>>>(c, F, qcCh, nCh, qcCnt, qcCur, qcToff, qcTmp, 1); CK(cudaGetLastError()); }
    }
    else { kQcScan<<<GB, TB>>>(c, F, qcCnt, qcToff, qcTmp, 1); CK(cudaGetLastError()); }
    if (getenv("GTX_QCPROF")) { CK(cudaDeviceSynchronize()); auto t1 = std::chrono::steady_clock::now(); fprintf(stderr, "QCPROF %s %.3f ms\n", "gather", std::chrono::duration<double, std::milli>(t1 - qt0).count()); qt0 = t1; }
    // reset only what was used, preserving the sticky oom flag
    u32 oomFlag = readCounter(c.oom);
    u32 hUsed = tops[2] < hCap ? tops[2] : hCap, txUsed = tops[3] < descCap ? tops[3] : descCap;
    if (c.cfg.qcChunk) {  // vcur/vfill are written for every vertex by kQcBlocks, D[0, dT) by kQcBuildSlots
      if (q.dBefore > dT) CK(cudaMemset(c.D + dT, 0, (size_t)(q.dBefore - dT) * sizeof(Delta)));
    } else {
      CK(cudaMemset(c.vcur, 0xFF, (size_t)V * 4));
      kFill64<<<1024, 256>>>(c.vfill, V, (u64)NONEB << 32); CK(cudaGetLastError());
      CK(cudaMemset(c.D, 0, (size_t)q.dBefore * sizeof(Delta)));
    }
    kFill<<<1024, 256>>>(c.H, hUsed, NILD); CK(cudaGetLastError());
    CK(cudaMemset(c.desc, 0, (size_t)txUsed * 8));
    CK(cudaMemset(c.bTop, 0, 64 * 4));
    if (getenv("GTX_QCPROF")) { CK(cudaDeviceSynchronize()); auto t1 = std::chrono::steady_clock::now(); fprintf(stderr, "QCPROF %s %.3f ms\n", "reset", std::chrono::duration<double, std::milli>(t1 - qt0).count()); qt0 = t1; }
    if (c.cfg.qcChunk) {
      kQcBlocks<<<GB, TB>>>(c, qcCnt, qcCapA, qcNchA, qcBA); CK(cudaGetLastError());
      kQcBuildSmall<<<GB, TB>>>(c, qcCnt, qcToff, qcCapA, qcNchA, qcTmp, qcCur); CK(cudaGetLastError());
      if (nBig) { kQcBuildBig<<<nBig < 4096 ? nBig : 4096, 1024>>>(c, qcBig, nBig, qcCnt, qcToff, qcCapA, qcNchA, qcTmp); CK(cudaGetLastError()); }
    } else { kQcBuild<<<GB, TB>>>(c, qcCnt, qcToff, qcCapA, qcNchA, qcBA, qcTmp); CK(cudaGetLastError()); }
    if (getenv("GTX_QCPROF")) { CK(cudaDeviceSynchronize()); auto t1 = std::chrono::steady_clock::now(); fprintf(stderr, "QCPROF %s %.3f ms\n", "build", std::chrono::duration<double, std::milli>(t1 - qt0).count()); qt0 = t1; }
    u64 committed1 = (1ull << 2) | 2; CK(cudaMemcpy(c.desc + 1, &committed1, 8, cudaMemcpyHostToDevice));
    u32 nt[4] = {(u32)nb, (u32)dT, (u32)hT, 2}; CK(cudaMemcpy(c.bTop, nt, 16, cudaMemcpyHostToDevice));
    CK(cudaMemcpy(c.oom, &oomFlag, 4, cudaMemcpyHostToDevice));
    u64 ef[3] = {2ull << 32, 1, 0}; CK(cudaMemcpy(c.E, ef, 24, cudaMemcpyHostToDevice));  // epoch 2 open, frontier 1
    CK(cudaEventRecord(b)); CK(cudaEventSynchronize(b));
    CK(cudaEventElapsedTime(&q.ms, a, b)); CK(cudaEventDestroy(a)); CK(cudaEventDestroy(b));
    q.ok = true; q.live = live; q.dAfter = (u32)dT; q.blocks = (u32)nb;
    return q;
  }
  u32 readCounter(u32* p) { u32 v; CK(cudaMemcpy(&v, p, 4, cudaMemcpyDeviceToHost)); return v; }

  // Run a device-resident workload; returns kernel ms.
  float run(const u32* dOff, const Op* dOps, u32 N, OpResult* dRes, TxRecord* dRec, u32* hStats) {
    c.off = dOff; c.ops = dOps; c.N = N; c.res = dRes; c.rec = dRec;
    CK(cudaMemset(c.nextTxn, 0, 4)); CK(cudaMemset(c.doneWarps, 0, 4)); CK(cudaMemset(c.stop, 0, 4));
    CK(cudaMemset(c.inflight, 0, 8)); CK(cudaMemset(dStats, 0, ST_N * 4));
    CK(cudaMemset(c.ann, 0xFF, (size_t)c.nAnn * 8));  // every warp idle until it announces
    txidBaseOfRun = readCounter(c.txTop);
    int warpsPerBlock = blockThreads / 32;
    const u32 svc = c.cfg.m4 ? 2 : 1;  // service warps: advancer (+ reclaimer)
    u32 needWarps = (N + 31) / 32 + svc;
    int blocks = gridBlocks;
    if ((u32)blocks * warpsPerBlock > needWarps) blocks = (needWarps + warpsPerBlock - 1) / warpsPerBlock;
    if (blocks < 1) blocks = 1;
    if ((u32)blocks * warpsPerBlock <= svc) blocks = (svc + warpsPerBlock) / warpsPerBlock;
    c.nWorkWarps = blocks * warpsPerBlock - svc;
    cudaEvent_t a, b; CK(cudaEventCreate(&a)); CK(cudaEventCreate(&b));
    CK(cudaEventRecord(a));
    kRun<<<blocks, blockThreads>>>(c);
    CK(cudaEventRecord(b)); CK(cudaEventSynchronize(b)); CK(cudaGetLastError());
    float ms = 0; CK(cudaEventElapsedTime(&ms, a, b));
    CK(cudaEventDestroy(a)); CK(cudaEventDestroy(b));
    if (hStats) { CK(cudaMemcpy(hStats, dStats, ST_N * 4, cudaMemcpyDeviceToHost)); hStats[ST_N - 1] = readCounter(c.oom); }
    { u32 fl = readCounter(c.oom); if (fl & 16) { u32 dg[3]; CK(cudaMemcpy(dg, c.nextTxn + 2, 12, cudaMemcpyDeviceToHost)); fprintf(stderr, "ADVANCER STUCK: epoch=%u registered=%u done=%u (run INVALID)\n", dg[0], dg[1], dg[2]); } }
    return ms;
  }

  size_t bytesUsed() {
    u32 t[4]; CK(cudaMemcpy(t, c.bTop, 16, cudaMemcpyDeviceToHost));
    return (size_t)t[0] * sizeof(Block) + (size_t)t[1] * sizeof(Delta) + (size_t)t[2] * 4 + (size_t)V * 12 + (size_t)t[3] * 8;
  }

  // Host snapshot of storage for checking.
  struct Snap { std::vector<u32> vcur; std::vector<u64> vfill; std::vector<Block> B; std::vector<Delta> D; std::vector<u64> desc; };
  Snap snapshot() {
    Snap s; u32 t[4]; CK(cudaMemcpy(t, c.bTop, 16, cudaMemcpyDeviceToHost));
    u32 nb = t[0] < bCap ? t[0] : bCap, nd = t[1] < dCap ? t[1] : dCap, nt = t[3] < descCap ? t[3] : descCap;
    s.vcur.resize(V); s.B.resize(nb); s.D.resize(nd); s.desc.resize(nt);
    CK(cudaMemcpy(s.vcur.data(), c.vcur, (size_t)V * 4, cudaMemcpyDeviceToHost));
    s.vfill.resize(V); CK(cudaMemcpy(s.vfill.data(), c.vfill, (size_t)V * 8, cudaMemcpyDeviceToHost));
    if (nb) CK(cudaMemcpy(s.B.data(), c.B, (size_t)nb * sizeof(Block), cudaMemcpyDeviceToHost));
    if (nd) CK(cudaMemcpy(s.D.data(), c.D, (size_t)nd * sizeof(Delta), cudaMemcpyDeviceToHost));
    if (nt) CK(cudaMemcpy(s.desc.data(), c.desc, (size_t)nt * 8, cudaMemcpyDeviceToHost));
    return s;
  }

  static u64 hostIts(const Snap& s, const Delta& d) {  // follow M4 forwarding
    u64 its = d.its; u32 hops = 0;
    while ((its & FWDBIT) && (u32)its < s.D.size() && hops++ < 64) its = s.D[(u32)its].its;
    return its;
  }
  // Visible edge set at snapshot F (host re-implementation of the scan visibility rule).
  static void visibleEdges(const Snap& s, u64 F, std::vector<std::pair<u32, u32>>& out) {
    auto committedLE = [&](u32 owner) { if (owner >= s.desc.size()) return false; u64 d = s.desc[owner]; return (d & 2) && (d >> 2) <= F; };
    for (u32 u = 0; u < s.vcur.size(); u++) {
      u32 g = s.vcur[u];
      while (g < PENDB) {
        const Block& b = s.B[g];
        u32 f = ((u32)(s.vfill[u] >> 32) == g) ? (u32)s.vfill[u] : b.cap;
        u32 n = f < b.cap ? f : b.cap;
        for (u32 i = 0; i < n; i++) {
          const Delta& d = s.D[b.base + i];
          if (!d.owner || (d.dstop >> 30) != OPB_INS) continue;
          bool cv = d.cts ? d.cts <= F : committedLE(d.owner);
          if (!cv) continue;
          bool inv = false;
          u64 its = hostIts(s, d);
          if (its) inv = (its & TAGBIT) ? committedLE((u32)its) : its <= F;
          if (!inv) out.push_back({u, d.dstop & 0x3FFFFFFFu});
        }
        g = b.prevGen;
      }
    }
  }
};

}  // namespace gtxg