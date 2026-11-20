// Benchmark driver: one scenario x one system per process (a WDDM TDR cannot poison other runs).
// Prints one CSV row per repetition:
// RESULT,label,sys,rep,ms,commits,aborts,giveup,eff,noop,txn_per_s,eff_per_s,upd_p50_us,upd_p95_us,upd_p99_us,
//        ro_p50_us,ro_p99_us,bytes,ab_ww_pending,ab_ww_late,ab_chain_false,ab_ser_point,ab_ser_scan,ab_resource,
//        ab_lock,ab_stm_read,casfail,growths,resv_atomics,epochs,check,flag(1 oom 2 watchdog 3 chain 4 advancer)
#include <algorithm>
#include <cstring>
#include <map>
#include <string>
#include "baselines.cuh"
#include "harness.hpp"

static std::map<std::string, std::string> args;
static std::string A(const char* k, const char* d) { auto it = args.find(k); return it == args.end() ? d : it->second; }
static double AD(const char* k, double d) { auto it = args.find(k); return it == args.end() ? d : atof(it->second.c_str()); }

static void pct(std::vector<double>& v, double& p50, double& p95, double& p99) {
  if (v.empty()) { p50 = p95 = p99 = 0; return; }
  std::sort(v.begin(), v.end());
  auto at = [&](double q) { size_t i = (size_t)(q * (v.size() - 1)); return v[i]; };
  p50 = at(.5); p95 = at(.95); p99 = at(.99);
}

int main(int argc, char** argv) {
  for (int i = 1; i + 1 < argc; i += 2) args[argv[i] + 2] = argv[i + 1];
  WlParams p;
  p.V = (u32)AD("V", 1 << 20); p.N = (u32)AD("N", 1 << 18); p.K = (u32)AD("K", 1);
  p.pIns = AD("pins", 1); p.pDel = AD("pdel", 0); p.pRead = AD("pread", 0); p.pScan = AD("pscan", 0);
  p.roFrac = AD("ro", 0); p.roScan = AD("roscan", 0.1);
  p.src = A("src", "uniform"); p.hubFrac = AD("hub", 0); p.nHubs = (u32)AD("nhubs", 1); p.zipfS = AD("zipf", 1.0);
  p.hotEdges = (u32)AD("hot", 0); p.hotFrac = AD("hotfrac", 0); p.initEdges = (u32)AD("init", 0); p.seed = (u64)AD("seed", 1);
  p.graph = A("graph", ""); p.initFrac = AD("initfrac", 0.8); p.fifoDel = (int)AD("fifodel", 0);
  if (AD("rounds", 0)) p.N = (u32)(AD("rounds", 0) * AD("perround", 1 << 20));  // long run: the whole stream
  std::string sys = A("sys", "gtx"), label = A("label", "run");
  int reps = (int)AD("reps", 5), check = (int)AD("check", 0), ser = (int)AD("ser", 0);
  HostWorkload w = makeWorkload(p);
  std::vector<std::string> abn;

  auto emit = [&](int rep, float ms, const u32* st, const std::vector<TxRecord>& rec, size_t bytes, const char* chk) {
    std::vector<double> upd, ro;
    for (u32 t = 0; t < w.N(); t++) {
      const TxRecord& r = rec[t];
      if (!r.txid || r.tEnd < r.tBegin) continue;
      bool isRo = true;
      for (u32 j = w.off[t]; j < w.off[t + 1]; j++) if (w.ops[j].type == OP_INS || w.ops[j].type == OP_DEL) isRo = false;
      (isRo ? ro : upd).push_back((r.tEnd - r.tBegin) / 1000.0);
    }
    double a, b, c, d, e, f; pct(upd, a, b, c); pct(ro, d, e, f);
    double s = ms / 1000.0;
    printf("RESULT,%s,%s,%d,%.4f,%u,%u,%u,%u,%u,%.1f,%.1f,%.2f,%.2f,%.2f,%.2f,%.2f,%zu", label.c_str(), sys.c_str(), rep, ms,
           st[ST_COMMITS], st[ST_ABORTS], st[ST_GIVEUP], st[ST_EFFECTIVE], st[ST_NOOPS], st[ST_COMMITS] / s, st[ST_EFFECTIVE] / s,
           a, b, c, d, f, bytes);
    for (int i = 0; i < AB_NCAUSES; i++) printf(",%u", st[ST_ABORT_BASE + i]);
    printf(",%u,%u,%u,%u,%s,%u\n", st[ST_CAS_FAIL], st[ST_GROWTHS], st[ST_RESV_ATOMICS], st[ST_EPOCHS], chk, st[ST_N - 1]);
    fflush(stdout);
  };

  if (sys.rfind("gtx", 0) == 0) {
    gtxg::Cfg cfg; cfg.ser = ser;
    if (sys == "gtx-cons") { cfg.coop = 0; cfg.dstconf = 0; }       // conservative GTX port
    else if (sys == "gtx-coop-only") { cfg.coop = 1; cfg.dstconf = 0; }
    else if (sys == "gtx-dst-only") { cfg.coop = 0; cfg.dstconf = 1; }
    cfg.coopScan = (int)AD("coopscan", 1);
    cfg.chRatio = (u32)AD("chratio", 1); cfg.minCap = (u32)AD("mincap", 8);
    cfg.growShift = (u32)AD("growshift", 3); cfg.prewalk = (int)AD("prewalk", 0); cfg.dbg = (int)AD("dbg", 0);
    cfg.bulk = (int)AD("bulk", 0);
    cfg.m4 = (int)AD("m4", 0); cfg.mergeMin = (u32)AD("mergemin", 64);
    cfg.holdMin = (u32)AD("holdmin", 0); cfg.mergeOnOldGarbage = (int)AD("mergeoldgarb", 0);
    if (sys == "gtx-m4") cfg.m4 = 7;                 // Method 4 (merge + reuse), default layout otherwise
    if (sys == "gtx-gs1") cfg.growShift = 1;         // layout fallback: 2x growth, no M4
    cfg.qcSlackPct = (u32)AD("qcslack", 0);
    cfg.qcChunk = (u32)AD("qcchunk", 1); cfg.qcBigSlots = (u32)AD("qcbig", 4096);
    if (AD("rounds", 0)) {  // long-running stream (M5): one launch per round; gtx-qc compacts between launches
      LongRunCfg lr; lr.rounds = (u32)AD("rounds", 0); lr.perRound = (u32)AD("perround", 1 << 20);
      lr.qc = sys == "gtx-qc" || AD("qc", 0); lr.checkEvery = (int)AD("checkevery", 0); lr.margin = AD("margin", 1.5); lr.qcEvery = (u32)AD("qcevery", 0);
      u32 arena = (u32)AD("arena", 20000000);
      u32 descCap = (u32)AD("desccap", 20000000);
      double sumMs = 0, sumQc = 0; u64 commits = 0, eff = 0; size_t hw = 0; u32 lastRound = 0, nQc = 0; int oomRound = -1;
      std::vector<float> pauses;
      int bad = runLongRun(w, cfg, lr, arena, descCap, [&](const RoundOut& ro) {
        if (ro.oom && oomRound < 0) oomRound = (int)ro.round;
        hw = std::max(hw, ro.bytes); sumMs += ro.ms; sumQc += ro.qcMs; commits += ro.st[ST_COMMITS]; eff += ro.st[ST_EFFECTIVE];
        if (ro.compacted) { nQc++; pauses.push_back(ro.qcMs); }
        lastRound = ro.round;
        printf("ROUND,%s,%s,%u,%.4f,%.4f,%u,%u,%u,%u,%zu,%u,%u,%u,%u,%llu,%d,%s,%u\n", label.c_str(), sys.c_str(), ro.round, ro.ms, ro.qcMs,
               ro.st[ST_COMMITS], ro.st[ST_ABORTS], ro.st[ST_EFFECTIVE], ro.st[ST_ABORT_BASE + AB_RESOURCE], ro.bytes, ro.dTop, ro.hTop,
               ro.bTop, ro.txTop, (unsigned long long)ro.live, ro.compacted, ro.check < 0 ? "-" : ro.check ? "PASS" : "FAIL", ro.st[ST_N - 1]);
        if (!ro.fail.empty()) fprintf(stderr, "ROUND %u FAIL: %s\n", ro.round, ro.fail.c_str());
        fflush(stdout);
      });
      std::sort(pauses.begin(), pauses.end());
      double tot = (sumMs + sumQc) / 1000.0;
      printf("LONGRUN,%s,%s,rounds_done=%u,oom_round=%d,commits=%llu,eff=%llu,kernel_ms=%.1f,qc_ms=%.1f,txn_per_s_e2e=%.1f,eff_per_s_e2e=%.1f,"
             "highwater_MB=%.1f,compactions=%u,pause_p50_ms=%.2f,pause_max_ms=%.2f,checks=%s\n",
             label.c_str(), sys.c_str(), lastRound + 1, oomRound, (unsigned long long)commits, (unsigned long long)eff, sumMs, sumQc,
             commits / tot, eff / tot, hw / 1048576.0, nQc, pauses.empty() ? 0.0 : pauses[pauses.size() / 2],
             pauses.empty() ? 0.0 : pauses.back(), lr.checkEvery ? (bad ? "FAIL" : "PASS") : "-");
      return bad;
    }
    u32 arena = AD("arena", 0) ? (u32)AD("arena", 0) : gtxArenaFor(w, cfg.minCap);
    size_t descCap = (size_t)w.N() * 32 + w.initEdges.size() + (1 << 20); if (descCap > 100000000) descCap = 100000000;
    gtxg::Store S; S.init(w.V, arena, (u32)descCap, cfg);
    const u32 batch = (u32)AD("batch", 0);
    if (batch) {  // batch mode: one launch per `batch` transactions, frontier published between launches (GPMA-style)
      DevWl d; d.upload(w);
      for (int rep = -1; rep < reps; rep++) {
        S.c.cfg = cfg; S.reset();
        if (!w.initEdges.empty()) {
          if (cfg.bulk) S.bulkLoad(w.initEdges);
          else { HostWorkload lw = loaderWorkload(w); DevWl dl; dl.upload(lw); S.run(dl.off, dl.ops, dl.N, dl.res, dl.rec, nullptr); dl.release(); }
          S.publishAll();
        }
        CK(cudaMemset(d.rec, 0, (size_t)d.N * sizeof(TxRecord)));
        const u32 base = S.readCounter(S.c.txTop);  // first txid of the batched workload
        u32 tot[ST_N] = {0}, st[ST_N]; float ms = 0; std::vector<double> per;
        for (u32 s0 = 0; s0 < d.N; s0 += batch) {
          u32 n = d.N - s0 < batch ? d.N - s0 : batch;
          float m = S.run(d.off + s0, d.ops, n, d.res, d.rec + s0, st);
          S.publishAll();
          ms += m; per.push_back(m);
          for (int i = 0; i < ST_N - 1; i++) tot[i] += st[i];
          tot[ST_N - 1] |= st[ST_N - 1];
        }
        if (rep < 0) continue;
        std::vector<TxRecord> rec(d.N); CK(cudaMemcpy(rec.data(), d.rec, (size_t)d.N * sizeof(TxRecord), cudaMemcpyDeviceToHost));
        const char* chk = "-";
        if (check && rep == reps - 1) {
          std::vector<OpResult> res(d.nOps); CK(cudaMemcpy(res.data(), d.res, d.nOps * sizeof(OpResult), cudaMemcpyDeviceToHost));
          CheckReport cr = checkStoreRun(S, w, cfg, res, rec, base);
          chk = cr.ok ? "PASS" : "FAIL";
          if (!cr.ok) fprintf(stderr, "CHECK FAIL: %s\n", cr.first.c_str());
        }
        emit(rep, ms, tot, rec, S.bytesUsed(), chk);
        std::sort(per.begin(), per.end());
        fprintf(stderr, "BATCH batch=%u launches=%zu p50_ms=%.4f p99_ms=%.4f\n", batch, per.size(), per[per.size() / 2], per[(size_t)(0.99 * (per.size() - 1))]);
      }
      d.release(); S.release();
      return 0;
    }
    for (int rep = -1; rep < reps; rep++) {
      bool doCheck = check && rep == reps - 1;
      RunOut o = runGtx(w, cfg, doCheck, &S);
      if (rep < 0) continue;  // warm-up
      if (AD("prof", 0)) { double tot = 0; for (int i = 0; i < 6; i++) tot += o.stats[24 + i]; const char* nm[] = {"begin", "oploop", "install", "validate", "commit", "stamp"}; fprintf(stderr, "PROF"); for (int i = 0; i < 6; i++) fprintf(stderr, " %s=%.1f%%", nm[i], 100.0 * o.stats[24 + i] / (tot - o.stats[26])); fprintf(stderr, "\n"); }
      emit(rep, o.ms, o.stats, o.rec, o.bytes, doCheck ? (o.rep.ok ? "PASS" : "FAIL") : "-");
      if (doCheck && !o.rep.ok) fprintf(stderr, "CHECK FAIL: %s\n", o.rep.first.c_str());
    }
    if (AD("membreak", 0)) printMemBreak(label.c_str(), memBreakdown(S));
    if (cfg.m4) {
      u32 m[gtxg::M4_N]; S.m4Stats(m);
      fprintf(stderr, "M4 trunc=%u merges=%u gensMerged=%u kept=%u linked=%u retired=%u freed=%u reused=%u ringFull=%u overflow=%u holds=%u lockBusy=%u\n",
              m[gtxg::M4_TRUNC],
              m[gtxg::M4_MERGES], m[gtxg::M4_GENS_MERGED], m[gtxg::M4_KEPT], m[gtxg::M4_LINKED], m[gtxg::M4_RETIRED], m[gtxg::M4_FREED],
              m[gtxg::M4_REUSED], m[gtxg::M4_RING_FULL], m[gtxg::M4_OVERFLOW], m[gtxg::M4_HOLDS], m[gtxg::M4_LOCK_BUSY]);
    }
    S.release();
  } else {
    int mode = sys == "2pl" ? bl::M_2PL : (sys == "nontx" ? bl::M_NONTX : bl::M_STM);
    int nodeg = sys == "stm-nodeg";
    bl::Store S; S.init(w);
    DevWl d; d.upload(w);
    for (int rep = -1; rep < reps; rep++) {
      bool doCheck = check && rep == reps - 1 && mode != bl::M_NONTX;
      S.reset();
      CK(cudaMemset(d.rec, 0, d.N * sizeof(TxRecord)));
      u32 st[ST_N];
      float ms = S.run(mode, d.off, d.ops, d.N, d.res, d.rec, st, doCheck ? 1 : 0, nodeg, 4000, (int)AD("blcoop", 0));
      std::vector<TxRecord> rec(d.N); CK(cudaMemcpy(rec.data(), d.rec, d.N * sizeof(TxRecord), cudaMemcpyDeviceToHost));
      if (rep < 0) continue;
      const char* chk = "-";
      if (doCheck) {
        std::vector<OpResult> res(d.nOps); CK(cudaMemcpy(res.data(), d.res, d.nOps * sizeof(OpResult), cudaMemcpyDeviceToHost));
        CheckInput ci; ci.w = &w; ci.res = &res; ci.rec = &rec; ci.initial = w.initEdges; ci.ser = true; ci.checkObs = false;
        ci.haveFinal = true; S.finalEdges(ci.finalEdges);
        CheckReport cr = checkHistory(ci);
        chk = cr.ok ? "PASS" : "FAIL";
        if (!cr.ok) fprintf(stderr, "CHECK FAIL: %s\n", cr.first.c_str());
      }
      emit(rep, ms, st, rec, S.bytes, chk);
    }
    d.release(); S.release();
  }
  return 0;
}
