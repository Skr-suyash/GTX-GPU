// Shared host harness helpers: device workload buffers, GTX runner with optional checking.
#pragma once
#include <map>
#include <set>
#include <string>
#include <vector>
#include "checker.hpp"
#include "gtxg.cuh"
#include "workload.hpp"

struct DevWl {
  u32* off = nullptr; Op* ops = nullptr; OpResult* res = nullptr; TxRecord* rec = nullptr; u32 N = 0; size_t nOps = 0;
  void upload(const HostWorkload& w) {
    N = w.N(); nOps = w.ops.size();
    CK(cudaMalloc(&off, (N + 1) * 4)); CK(cudaMalloc(&ops, (nOps ? nOps : 1) * sizeof(Op)));
    CK(cudaMalloc(&res, (nOps ? nOps : 1) * sizeof(OpResult))); CK(cudaMalloc(&rec, (N ? N : 1) * sizeof(TxRecord)));
    CK(cudaMemcpy(off, w.off.data(), (N + 1) * 4, cudaMemcpyHostToDevice));
    if (nOps) CK(cudaMemcpy(ops, w.ops.data(), nOps * sizeof(Op), cudaMemcpyHostToDevice));
    CK(cudaMemset(res, 0, (nOps ? nOps : 1) * sizeof(OpResult))); CK(cudaMemset(rec, 0, (N ? N : 1) * sizeof(TxRecord)));
  }
  void release() { cudaFree(off); cudaFree(ops); cudaFree(res); cudaFree(rec); off = nullptr; }
};

struct RunOut {
  float ms = 0; u32 stats[ST_N] = {0};
  std::vector<OpResult> res; std::vector<TxRecord> rec;
  CheckReport rep; bool checked = false; size_t bytes = 0;
  u32 m4[gtxg::M4_N] = {0};
};

inline const char* abName(int i) {
  static const char* n[] = {"ww_pending", "ww_late", "chain_false", "ser_point", "ser_scan", "resource", "lock", "stm_read"};
  return n[i];
}

// Classify every byte of the GTX store after a run (host snapshot, frontier F = all published).
// Delta slots are classified per reachable generation; "orphan" = arena slots not reachable from any vertex.
struct MemBreak {
  u64 unwritten = 0, reservedEmpty = 0, voided = 0, aborted = 0, pending = 0, liveIns = 0, deadIns = 0, del = 0, orphan = 0;
  u64 blocks = 0, heads = 0, descs = 0, vertexArrays = 0, gens = 0, vertsWithBlocks = 0, maxGens = 0;
  // non-newest generations: entirely droppable (no slot a snapshot >= F still needs) vs. holding >= 1 needed slot
  u64 deadOldGens = 0, deadOldBytes = 0, liveOldGens = 0, liveOldBytes = 0, liveOldKeep = 0;
  u64 slotBytes() const { return (unwritten + reservedEmpty + voided + aborted + pending + liveIns + deadIns + del + orphan) * sizeof(gtxg::Delta); }
  u64 total() const { return slotBytes() + blocks + heads + descs + vertexArrays; }
};
inline MemBreak memBreakdown(gtxg::Store& S) {
  S.publishAll();
  auto s = S.snapshot();
  u64 F = S.frontier();
  u32 t[4]; CK(cudaMemcpy(t, S.c.bTop, 16, cudaMemcpyDeviceToHost));
  MemBreak m;
  m.blocks = (u64)t[0] * sizeof(gtxg::Block); m.heads = (u64)t[2] * 4; m.descs = (u64)t[3] * 8; m.vertexArrays = (u64)S.V * 12;
  auto descOf = [&](u32 o) -> u64 { return o < s.desc.size() ? s.desc[o] : 0; };
  auto committedLE = [&](u32 o) { u64 d = descOf(o); return (d & 2) && (d >> 2) <= F; };
  u64 reach = 0;
  for (u32 u = 0; u < S.V; u++) {
    u32 g = s.vcur[u]; u64 ng = 0;
    if (g < gtxg::PENDB) m.vertsWithBlocks++;
    while (g < gtxg::PENDB) {
      const gtxg::Block& b = s.B[g]; ng++;
      u32 f = ((u32)(s.vfill[u] >> 32) == g) ? (u32)s.vfill[u] : b.cap;
      u32 n = f < b.cap ? f : b.cap;
      m.unwritten += b.cap - n; reach += b.cap;
      u64 keep = 0;
      for (u32 i = 0; i < n; i++) {
        const gtxg::Delta& d = s.D[b.base + i];
        u32 op = d.dstop >> 30;
        if (!d.owner) { m.reservedEmpty++; continue; }
        if (op == gtxg::OPB_VOID) { m.voided++; continue; }
        u64 ds = descOf(d.owner);
        bool committed = d.cts ? true : (ds & 2) != 0;
        if (!committed) { (ds == 1 ? m.aborted : m.pending)++; if (ds != 1) keep++; continue; }
        u64 cts = d.cts ? d.cts : (ds >> 2);
        if (op == gtxg::OPB_DEL) { m.del++; if (cts > F) keep++; continue; }
        u64 its = gtxg::Store::hostIts(s, d);
        bool inv = its ? ((its & gtxg::TAGBIT) ? committedLE((u32)its) : its <= F) : false;
        (inv ? m.deadIns : m.liveIns)++;
        if (!inv) keep++;
      }
      if (ng > 1) {  // not the newest generation of u
        u64 bytes = (u64)b.cap * sizeof(gtxg::Delta) + (u64)b.nch * 4 + sizeof(gtxg::Block);
        if (keep) { m.liveOldGens++; m.liveOldBytes += bytes; m.liveOldKeep += keep; } else { m.deadOldGens++; m.deadOldBytes += bytes; }
      }
      g = b.prevGen;
    }
    m.gens += ng; if (ng > m.maxGens) m.maxGens = ng;
  }
  u64 dTop = t[1] < S.dCap ? t[1] : S.dCap;
  m.orphan = dTop > reach ? dTop - reach : 0;
  return m;
}
inline void printMemBreak(const char* label, const MemBreak& m) {
  auto mb = [](u64 b) { return b / 1048576.0; };
  const u64 D = sizeof(gtxg::Delta);
  printf("MEM,%s,total_MB=%.1f,slots_MB=%.1f,unwritten_MB=%.1f,void_MB=%.1f,aborted_MB=%.1f,pending_MB=%.1f,reservedEmpty_MB=%.1f,"
         "liveIns_MB=%.1f,deadIns_MB=%.1f,del_MB=%.1f,orphan_MB=%.1f,blocks_MB=%.1f,heads_MB=%.1f,desc_MB=%.1f,vtx_MB=%.1f,"
         "liveEdges=%llu,gens=%llu,maxGens=%llu,vertsWithBlocks=%llu,"
         "deadOldGens=%llu,deadOld_MB=%.1f,liveOldGens=%llu,liveOld_MB=%.1f,liveOldKeepSlots=%llu\n",
         label, mb(m.total()), mb(m.slotBytes()), mb(m.unwritten * D), mb(m.voided * D), mb(m.aborted * D), mb(m.pending * D),
         mb(m.reservedEmpty * D), mb(m.liveIns * D), mb(m.deadIns * D), mb(m.del * D), mb(m.orphan * D), mb(m.blocks), mb(m.heads),
         mb(m.descs), mb(m.vertexArrays), m.liveIns, m.gens, m.maxGens, m.vertsWithBlocks,
         m.deadOldGens, mb(m.deadOldBytes), m.liveOldGens, mb(m.liveOldBytes), m.liveOldKeep);
  fflush(stdout);
}

// History check of a finished store (used by bench batch mode, where one workload spans several launches).
// base = first txid of the checked workload (everything below it is the initial graph / loader).
inline CheckReport checkStoreRun(gtxg::Store& S, const HostWorkload& w, const gtxg::Cfg& cfg, const std::vector<OpResult>& res,
                                 const std::vector<TxRecord>& rec, u32 base) {
  S.publishAll();
  auto snap = S.snapshot();
  u64 F = S.frontier();
  CheckInput ci; ci.w = &w; ci.res = &res; ci.rec = &rec; ci.initial = w.initEdges; ci.ser = cfg.ser; ci.checkObs = true;
  std::unordered_map<u32, long long> txidToTxn;
  for (u32 i = 0; i < w.N(); i++) if (rec[i].txid) txidToTxn[rec[i].txid] = i;
  auto byOwner = [&](u32 owner) -> long long {
    if (owner < base) return -2;
    auto it = txidToTxn.find(owner);
    return it == txidToTxn.end() ? -3 : it->second;
  };
  // A version written before this run is either an INS of the start state (-2) or, in multi-round runs, a DEL from an
  // earlier round: the start state has no such edge, so its writer is 'none' (-1). Single runs only have loader INS.
  ci.obsWriter = [&](u32 obs) -> long long {
    if (obs == gtxg::NILD) return -1;
    if (obs >= snap.D.size()) return -3;
    const gtxg::Delta& d = snap.D[obs];
    if (d.owner < base && (d.dstop >> 30) == gtxg::OPB_DEL) return -1;
    return byOwner(d.owner);
  };
  ci.allowDroppedDel = (cfg.m4 & 2) != 0;
  if (cfg.m4) ci.obsWriterOp = [&](u32 j) -> long long { return res[j].obs == gtxg::NILD ? -1 : res[j].pad ? byOwner(res[j].pad) : -3; };
  ci.haveFinal = true;
  gtxg::Store::visibleEdges(snap, F, ci.finalEdges);
  return checkHistory(ci);
}

// ---- Long-running streams (M5): the workload is cut into rounds of `perRound` transactions, one launch each, with the
// frontier published between launches. With qc, the store is compacted before a launch whenever its largest
// per-round growth so far (x margin) would not fit in any arena (slots, heads, blocks, descriptors).
// Checked rounds are history-checked from the visible graph at the start of the round, taken BEFORE any compaction,
// so a compaction that changes the graph fails the next check; with check, every compaction is also compared directly
// (visible set before == after).
struct LongRunCfg { u32 rounds = 10, perRound = 1 << 20; int qc = 0; int checkEvery = 0; double margin = 1.5; int stopOnOom = 1; u32 qcEvery = 0; };  // qcEvery: also force a compaction every k rounds (gate)
struct RoundOut {
  u32 round = 0; float ms = 0, qcMs = 0; u32 st[ST_N] = {0}; size_t bytes = 0;
  u32 dTop = 0, hTop = 0, bTop = 0, txTop = 0; u64 live = 0; int compacted = 0, check = -1, oom = 0; std::string fail;
};
inline HostWorkload sliceWorkload(const HostWorkload& w, u32 t0, u32 t1) {
  HostWorkload s; s.V = w.V; s.off.push_back(0);
  u32 b = w.off[t0];
  for (u32 t = t0; t < t1; t++) s.off.push_back(w.off[t + 1] - b);
  s.ops.assign(w.ops.begin() + b, w.ops.begin() + w.off[t1]);
  return s;
}
template <class F>
inline int runLongRun(const HostWorkload& w, gtxg::Cfg cfg, const LongRunCfg& lr, u32 arena, u32 descCap, F onRound) {
  gtxg::Store S; S.init(w.V, arena, descCap, cfg);
  if (!w.initEdges.empty()) { S.bulkLoad(w.initEdges); S.publishAll(); }
  u32 gD = 0, gH = 0, gB = 0, gT = 0;  // largest per-round growth seen
  int bad = 0;
  for (u32 r = 0; r < lr.rounds; r++) {
    u32 t0 = r * lr.perRound, t1 = t0 + lr.perRound;
    if (t0 >= w.N()) break;
    if (t1 > w.N()) t1 = w.N();
    RoundOut ro; ro.round = r;
    HostWorkload ws = sliceWorkload(w, t0, t1);
    bool doCheck = lr.checkEvery && (r % lr.checkEvery == 0 || r + 1 == lr.rounds);
    if (doCheck) { S.publishAll(); auto sn = S.snapshot(); gtxg::Store::visibleEdges(sn, S.frontier(), ws.initEdges); }
    u32 t[4]; CK(cudaMemcpy(t, S.c.bTop, 16, cudaMemcpyDeviceToHost));
    auto wontFit = [&](u32 top, u32 g, u32 cap) { return (double)top + lr.margin * g > (double)cap; };
    bool force = lr.qc && lr.qcEvery && r > 0 && r % lr.qcEvery == 0;
    if (force || lr.qc && (wontFit(t[1], gD, S.dCap) || wontFit(t[2], gH, S.hCap) || wontFit(t[0], gB, S.bCap) || wontFit(t[3], gT, S.descCap))) {
      auto q = S.compact();
      if (!q.ok) { ro.fail = "live graph does not fit"; ro.check = 0; onRound(ro); return 1; }
      ro.compacted = 1; ro.qcMs = q.ms; ro.live = q.live;
      if (doCheck) {  // direct comparison: the compaction must not change the visible graph
        auto sn = S.snapshot(); std::vector<std::pair<u32, u32>> after;
        gtxg::Store::visibleEdges(sn, S.frontier(), after);
        auto a = ws.initEdges; std::sort(a.begin(), a.end()); std::sort(after.begin(), after.end());
        if (a != after) { ro.fail = "compaction changed the visible graph"; ro.check = 0; bad = 1; }
      }
      CK(cudaMemcpy(t, S.c.bTop, 16, cudaMemcpyDeviceToHost));
    }
    const u32 base = S.readCounter(S.c.txTop);
    DevWl d; d.upload(ws);
    ro.ms = S.run(d.off, d.ops, d.N, d.res, d.rec, ro.st);
    S.publishAll();
    u32 t2[4]; CK(cudaMemcpy(t2, S.c.bTop, 16, cudaMemcpyDeviceToHost));
    auto grow = [](u32 a, u32 b) { return b > a ? b - a : 0u; };
    gB = std::max(gB, grow(t[0], t2[0])); gD = std::max(gD, grow(t[1], t2[1]));
    gH = std::max(gH, grow(t[2], t2[2])); gT = std::max(gT, grow(t[3], t2[3]));
    ro.bTop = t2[0]; ro.dTop = t2[1]; ro.hTop = t2[2]; ro.txTop = t2[3];
    ro.bytes = S.bytesUsed() + S.qcBytes();
    if (doCheck) {
      std::vector<OpResult> res(d.nOps); std::vector<TxRecord> rec(d.N);
      CK(cudaMemcpy(res.data(), d.res, d.nOps * sizeof(OpResult), cudaMemcpyDeviceToHost));
      CK(cudaMemcpy(rec.data(), d.rec, (size_t)d.N * sizeof(TxRecord), cudaMemcpyDeviceToHost));
      CheckReport cr = checkStoreRun(S, ws, cfg, res, rec, base);
      bool direct = ro.check != 0;  // -1 = nothing compared, 0 = the direct comparison failed
      ro.check = cr.ok && direct ? 1 : 0;
      if (!cr.ok) { ro.fail += (ro.fail.empty() ? "" : "; ") + std::string("history checker: ") + cr.first; bad = 1; }
      else if (!direct) ro.fail += "; history checker: PASS";
    }
    d.release();
    // exhaustion = the arena flag, or txids past the descriptor array (AB_RESOURCE alone also counts cause-less aborts)
    ro.oom = (ro.st[ST_N - 1] & 1) || ro.txTop > S.descCap;
    onRound(ro);
    if (ro.oom && lr.stopOnOom) break;
  }
  S.release();
  return bad;
}

// Upper bound of delta slots needed (generous; growth doubles blocks => <= ~4x live + slack per vertex).
inline u32 gtxArenaFor(const HostWorkload& w, u32 minCap) {
  size_t writes = w.initEdges.size();
  for (auto& o : w.ops) if (o.type == OP_INS || o.type == OP_DEL) writes++;
  size_t cap = writes * 6 + (size_t)w.V * minCap * 2 + (1 << 20);
  if (cap > 60000000) cap = 60000000;  // 60M * 32B = 1.9 GB
  return (u32)cap;
}

// Load w.initEdges, then run w. If check, validate with the history checker.
inline RunOut runGtx(const HostWorkload& w, gtxg::Cfg cfg, bool check, gtxg::Store* reuse = nullptr, u32 arena = 0) {
  RunOut out;
  gtxg::Store local;
  gtxg::Store& S = reuse ? *reuse : local;
  if (!reuse) {
    u32 dcap = arena ? arena : gtxArenaFor(w, cfg.minCap);
    size_t descCap = (size_t)w.N() * 32 + w.initEdges.size() + (1 << 20);
    if (descCap > 100000000) descCap = 100000000;
    S.init(w.V, dcap, (u32)descCap, cfg);
  } else { S.c.cfg = cfg; S.reset(); }
  if (!w.initEdges.empty() && cfg.bulk) {
    S.bulkLoad(w.initEdges);
  } else if (!w.initEdges.empty()) {
    HostWorkload lw = loaderWorkload(w);
    DevWl dl; dl.upload(lw);
    gtxg::Cfg lc = cfg; lc.ser = 0; lc.mut = 0; S.c.cfg = lc;
    S.run(dl.off, dl.ops, dl.N, dl.res, dl.rec, nullptr);
    dl.release();
    S.c.cfg = cfg;
    S.publishAll();
  }
  DevWl d; d.upload(w);
  u32* dbgBuf = nullptr; u32* dbgTop = nullptr; const u32 dbgCap = (u32)((w.ops.size() + 1) * 3072ull);
  if (getenv("GTX_FORENSIC")) {
    CK(cudaMalloc(&dbgBuf, (size_t)dbgCap * 4)); CK(cudaMalloc(&dbgTop, 4)); CK(cudaMemset(dbgTop, 0, 4));
    S.c.dbgBuf = dbgBuf; S.c.dbgTop = dbgTop; S.c.dbgCap = dbgCap;
  }
  out.ms = S.run(d.off, d.ops, d.N, d.res, d.rec, out.stats);
  S.c.dbgBuf = nullptr; S.c.dbgTop = nullptr; S.c.dbgCap = 0;
  std::vector<u32> dbgHost;
  if (dbgBuf) {
    u32 top = dbgCap;
    dbgHost.resize(top); if (top) CK(cudaMemcpy(dbgHost.data(), dbgBuf, (size_t)top * 4, cudaMemcpyDeviceToHost));
    cudaFree(dbgBuf); cudaFree(dbgTop);
  }
  out.bytes = S.bytesUsed();
  if (cfg.m4) S.m4Stats(out.m4);
  out.res.resize(d.nOps); out.rec.resize(d.N);
  if (d.nOps) CK(cudaMemcpy(out.res.data(), d.res, d.nOps * sizeof(OpResult), cudaMemcpyDeviceToHost));
  if (d.N) CK(cudaMemcpy(out.rec.data(), d.rec, d.N * sizeof(TxRecord), cudaMemcpyDeviceToHost));
  if (check) {
    S.publishAll();
    auto snap = S.snapshot();
    u64 F = S.frontier();
    CheckInput ci; ci.w = &w; ci.res = &out.res; ci.rec = &out.rec; ci.initial = w.initEdges; ci.ser = cfg.ser;
    std::unordered_map<u32, long long> txidToTxn;
    for (u32 i = 0; i < d.N; i++) if (out.rec[i].txid) txidToTxn[out.rec[i].txid] = i;
    u32 base = S.txidBaseOfRun;
    ci.checkObs = true;
    ci.obsWriter = [&](u32 obs) -> long long {
      if (obs == gtxg::NILD) return -1;
      if (obs >= snap.D.size()) return -3;
      u32 owner = snap.D[obs].owner;
      if (owner < base) return -2;
      auto it = txidToTxn.find(owner);
      return it == txidToTxn.end() ? -3 : it->second;
    };
    ci.allowDroppedDel = (cfg.m4 & 2) != 0;
    if (cfg.m4) ci.obsWriterOp = [&](u32 j) -> long long {
      if (out.res[j].obs == gtxg::NILD) return -1;
      u32 owner = out.res[j].pad;  // writer recorded at read time
      if (!owner) return -3;
      if (owner < base) return -2;
      auto it = txidToTxn.find(owner);
      return it == txidToTxn.end() ? -3 : it->second;
    };
    ci.haveFinal = true;
    gtxg::Store::visibleEdges(snap, F, ci.finalEdges);
    out.rep = checkHistory(ci);
    out.checked = true;
    if (out.rep.badScanTxn >= 0 && getenv("GTX_FORENSIC")) {
      const TxRecord& tr = out.rec[out.rep.badScanTxn];
      u32 u = out.rep.badScanU;
      fprintf(stderr, "FORENSIC scan txn=%lld op=%u vertex=%u self=%u rts=%llu cts=%llu attempts=%u frontierFinal=%llu\n",
              out.rep.badScanTxn, out.rep.badScanOp, u, tr.txid, (unsigned long long)tr.rts, (unsigned long long)tr.cts, tr.attempts, (unsigned long long)F);
      fprintf(stderr, "  txn ops:");
      for (u32 j = w.off[out.rep.badScanTxn]; j < w.off[out.rep.badScanTxn + 1]; j++) fprintf(stderr, " %u(%u,%u)->%u", w.ops[j].type, w.ops[j].u, w.ops[j].v, out.res[j].r);
      fprintf(stderr, "\n  expected(snapshot, not own):");
      for (u32 v : out.rep.badExpect) fprintf(stderr, " %u", v);
      fprintf(stderr, "\n  own:");
      for (auto& o : out.rep.badOwn) fprintf(stderr, " %u:%d", o.first, (int)o.second);
      fprintf(stderr, "\n");
      auto who = [&](u32 txid) -> std::string {
        char b[160];
        if (txid < base) { snprintf(b, sizeof b, "loader"); return b; }
        auto it = txidToTxn.find(txid);
        u64 d = txid < snap.desc.size() ? snap.desc[txid] : 0;
        if (it == txidToTxn.end()) snprintf(b, sizeof b, "attempt(tx%u desc=%llu)", txid, (unsigned long long)d);
        else { const TxRecord& r = out.rec[it->second]; snprintf(b, sizeof b, "T%lld(tx%u rts=%llu cts=%llu desc=%llu)", it->second, txid, (unsigned long long)r.rts, (unsigned long long)r.cts, (unsigned long long)d); }
        return b;
      };
      // Recompute visibility at (self, rts) from final descriptors; diff against the model.
      u32 self = tr.txid; u64 rts = tr.rts;
      auto commitLE = [&](u32 txid) { if (txid == self) return true; if (txid >= snap.desc.size()) return false; u64 d = snap.desc[txid]; return (d & 2) && (d >> 2) <= rts; };
      std::map<u32, int> devVis; std::map<u32, std::vector<u32>> hist;
      for (u32 g2 = snap.vcur[u]; g2 < gtxg::PENDB; g2 = snap.B[g2].prevGen) {
        const gtxg::Block& b = snap.B[g2];
        u32 f = ((u32)(snap.vfill[u] >> 32) == g2) ? (u32)snap.vfill[u] : b.cap; u32 n = f < b.cap ? f : b.cap;
        for (u32 i = 0; i < n; i++) {
          const gtxg::Delta& d = snap.D[b.base + i];
          if (!d.owner) continue;
          u32 dst = d.dstop & 0x3FFFFFFFu; hist[dst].push_back(b.base + i);
          if ((d.dstop >> 30) != 1) continue;
          bool cv = d.cts ? (d.cts <= rts) || d.owner == self : commitLE(d.owner);
          bool inv = d.its ? ((d.its & gtxg::TAGBIT) ? commitLE((u32)d.its) : d.its <= rts) : false;
          if (cv && !inv) devVis[dst]++;
        }
      }
      std::map<u32, int> model;
      for (u32 v : out.rep.badExpect) model[v] = 1;
      for (auto& o : out.rep.badOwn) model[o.first] = o.second ? 1 : 0;
      for (auto it = model.begin(); it != model.end();) { if (!it->second) it = model.erase(it); else ++it; }
      fprintf(stderr, "  device-visible-at-rts(final descs)=%zu model=%zu\n", devVis.size(), model.size());
      std::set<u32> diff;
      for (auto& kv : devVis) if (!model.count(kv.first) || kv.second != 1) diff.insert(kv.first);
      for (auto& kv : model) if (!devVis.count(kv.first)) diff.insert(kv.first);
      for (u32 dst : diff) {
        fprintf(stderr, "  DIFF dst=%u device=%d model=%d history:\n", dst, devVis.count(dst) ? devVis[dst] : 0, model.count(dst) ? 1 : 0);
        for (u32 idx : hist[dst]) {
          const gtxg::Delta& d = snap.D[idx];
          u32 op = d.dstop >> 30;
          std::string its = "-";
          if (d.its) { if (d.its & gtxg::TAGBIT) its = "by " + who((u32)d.its); else its = "@" + std::to_string(d.its); }
          fprintf(stderr, "    [%u] %s owner=%s cts=%llu its=%s prev=%u\n", idx, op == 1 ? "INS" : op == 2 ? "DEL" : "VOID",
                  who(d.owner).c_str(), (unsigned long long)d.cts, its.c_str(), d.prev);
        }
      }
      auto printHist = [&](u32 dst) {
        u32 skipped = 0;
        for (u32 idx : hist[dst]) {
          const gtxg::Delta& d = snap.D[idx]; u32 op = d.dstop >> 30; std::string its = "-";
          bool abortedAttempt = d.owner >= base && !txidToTxn.count(d.owner);
          if (abortedAttempt || op == 3) { skipped++; continue; }
          if (d.its) { if (d.its & gtxg::TAGBIT) its = "by " + who((u32)d.its); else its = "@" + std::to_string(d.its); }
          fprintf(stderr, "    [%u] %s owner=%s cts=%llu its=%s prev=%u\n", idx, op == 1 ? "INS" : op == 2 ? "DEL" : "VOID",
                  who(d.owner).c_str(), (unsigned long long)d.cts, its.c_str(), d.prev);
        }
      };
      {  // what did the scan actually count?
        const OpResult& sr = out.res[w.off[out.rep.badScanTxn] + out.rep.badScanOp];
        if (sr.pad != 0xFFFFFFFFu && (size_t)sr.pad + 3072 <= dbgHost.size()) {
          std::map<u32, u32> counted;  // dst -> delta idx
          for (u32 k = 0; k < sr.r && k < 1024; k++) { u32 idx = dbgHost[sr.pad + k]; counted[snap.D[idx].dstop & 0x3FFFFFFFu] = idx; }
          for (auto& kv : counted) if (!model.count(kv.first)) { fprintf(stderr, "  EXTRA counted dst=%u via [%u]:\n", kv.first, kv.second); printHist(kv.first); }
          for (auto& kv : model) if (!counted.count(kv.first)) { fprintf(stderr, "  MISSING dst=%u:\n", kv.first); printHist(kv.first);
            u32 g0 = dbgHost[sr.pad + 3048];
            for (u32 idx : hist[kv.first]) if (g0 < snap.B.size() && idx >= snap.B[g0].base && idx < snap.B[g0].base + 2024) fprintf(stderr, "    scan code for [%u] = %u\n", idx, dbgHost[sr.pad + 1024 + idx - snap.B[g0].base]); }
          fprintf(stderr, "  scan visited gens:");
          for (u32 q = 0; q < 12; q++) { u32 gg = dbgHost[sr.pad + 3048 + 2 * q]; if (gg == 0xFFFFFFFFu) break; fprintf(stderr, " g%u(n=%u)", gg, dbgHost[sr.pad + 3049 + 2 * q]); }
          fprintf(stderr, "\n  final gen chain:");
          for (u32 g2 = snap.vcur[u]; g2 < gtxg::PENDB; g2 = snap.B[g2].prevGen) fprintf(stderr, " g%u[base=%u cap=%u]", g2, snap.B[g2].base, snap.B[g2].cap);
          fprintf(stderr, "\n");
        } else fprintf(stderr, "  (no per-scan record: coop scan or overflow)\n");
      }
      u32 g = gtxg::PENDB;  // full block dump disabled
      while (g < gtxg::PENDB) {
        const gtxg::Block& b = snap.B[g];
        u32 f = ((u32)(snap.vfill[u] >> 32) == g) ? (u32)snap.vfill[u] : b.cap; u32 n = f < b.cap ? f : b.cap;
        fprintf(stderr, "  gen %u base=%u cap=%u used=%u prev=%u\n", g, b.base, b.cap, n, b.prevGen);
        for (u32 i = 0; i < n; i++) {
          const gtxg::Delta& d = snap.D[b.base + i];
          if (!d.owner) continue;
          u32 op = d.dstop >> 30;
          std::string its = "-";
          if (d.its) { if (d.its & gtxg::TAGBIT) its = "by " + who((u32)d.its); else its = "@" + std::to_string(d.its); }
          fprintf(stderr, "    [%u] %s dst=%u owner=%s cts=%llu its=%s\n", b.base + i, op == 1 ? "INS" : op == 2 ? "DEL" : "VOID",
                  d.dstop & 0x3FFFFFFFu, who(d.owner).c_str(), (unsigned long long)d.cts, its.c_str());
        }
        g = b.prevGen;
      }
    }
  }
  d.release();
  if (!reuse) S.release();
  return out;
}
