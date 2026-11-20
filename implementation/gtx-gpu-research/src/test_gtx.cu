// Correctness suite for GTX-GPU (experiment step 1 of the protocol).
//  A. adversarial randomized histories, SI and SER, all ablation switches -> checker must PASS
//  B. write-skew probe: SI must exhibit DSG cycles (anomaly allowed), SER must not
//  C. mutation tests: deliberately broken protocols -> checker must FAIL (sensitivity)
//  D. resource exhaustion: committed prefix still checks clean
#include <cstring>
#include <string>
#include "harness.hpp"

static int failures = 0;

static void report(const char* name, const gtxg::Cfg& cfg, const RunOut& o, bool expectPass) {
  long long ab = o.stats[ST_ABORTS];
  bool pass = o.rep.ok;
  bool good = (pass == expectPass);
  if (!good) failures++;
  printf("%-26s coop=%d dst=%d ser=%d cscan=%d mut=%d | commits=%u aborts=%lld giveup=%u eff=%u noop=%u "
         "casfail=%u grow=%u void=%u | DSGcyc=%lld | checker=%s %s %s\n",
         name, cfg.coop, cfg.dstconf, cfg.ser, cfg.coopScan, cfg.mut, o.stats[ST_COMMITS], ab, o.stats[ST_GIVEUP],
         o.stats[ST_EFFECTIVE], o.stats[ST_NOOPS], o.stats[ST_CAS_FAIL], o.stats[ST_GROWTHS], o.stats[ST_VOIDED],
         o.rep.cycleTxns, pass ? "PASS" : "FAIL", good ? "[as expected]" : "[UNEXPECTED]",
         pass ? "" : o.rep.first.c_str());
  fflush(stdout);
}

static HostWorkload writeSkew(u32 pairs, u32 reps) {
  // For vertex p: A = {READ(p,2), INS(p,1)}, B = {READ(p,1), INS(p,2)} -- under SI both may commit.
  HostWorkload w; w.V = pairs + 3; w.off.push_back(0);
  for (u32 r = 0; r < reps; r++)
    for (u32 p = 3; p < pairs + 3; p++) {
      u32 a = 1 + 2 * r, b = 2 + 2 * r;
      a %= w.V; b %= w.V;
      w.ops.push_back({OP_READ, p, b}); w.ops.push_back({OP_INS, p, a}); w.off.push_back((u32)w.ops.size());
      w.ops.push_back({OP_READ, p, a}); w.ops.push_back({OP_INS, p, b}); w.off.push_back((u32)w.ops.size());
    }
  return w;
}

int main(int argc, char** argv) {
  int quick = argc > 1 && !strcmp(argv[1], "quick");
  const char* only = argc > 2 ? argv[2] : nullptr;  // run only cases whose name contains this
  struct Case { const char* name; WlParams p; };
  std::vector<Case> cases;
  { WlParams p; p.V = 256; p.N = 20000; p.K = 4; p.pIns = .4; p.pDel = .3; p.pRead = .2; p.pScan = .1; p.initEdges = 2000; p.seed = 11; cases.push_back({"mixed-uniform-V256", p}); }
  { WlParams p; p.V = 1024; p.N = 20000; p.K = 4; p.src = "hub"; p.hubFrac = .5; p.pIns = .5; p.pDel = .3; p.pRead = .1; p.pScan = .1; p.initEdges = 3000; p.seed = 12; cases.push_back({"hub50-mixed", p}); }
  { WlParams p; p.V = 512; p.N = 20000; p.K = 2; p.hotEdges = 8; p.hotFrac = .8; p.pIns = .5; p.pDel = .5; p.seed = 13; cases.push_back({"identical-edge-8", p}); }
  { WlParams p; p.V = 64; p.N = 10000; p.K = 8; p.pIns = .45; p.pDel = .45; p.pRead = .05; p.pScan = .05; p.initEdges = 500; p.seed = 14; cases.push_back({"churn-V64-K8", p}); }
  { WlParams p; p.V = 2048; p.N = 20000; p.K = 4; p.src = "zipf"; p.zipfS = 1.1; p.pIns = .6; p.pDel = .2; p.pRead = .1; p.pScan = .1; p.roFrac = .5; p.roScan = .3; p.initEdges = 8000; p.seed = 15; cases.push_back({"zipf-readers50", p}); }
  { WlParams p; p.V = 4096; p.N = 30000; p.K = 32; p.src = "hub"; p.hubFrac = .3; p.pIns = .7; p.pDel = .2; p.pRead = .1; p.seed = 16; cases.push_back({"hub30-K32", p}); }

  printf("== A. randomized adversarial histories (expect PASS) ==\n");
  for (auto& cs : cases) {
    if (only && !strstr(cs.name, only)) continue;
    HostWorkload w = makeWorkload(cs.p);
    for (int ser = 0; ser <= 1; ser++)
      for (int coop = 0; coop <= 1; coop++)
        for (int dst = 0; dst <= 1; dst++) {
          if (quick && (coop != dst)) continue;
          gtxg::Cfg cfg; cfg.ser = ser; cfg.coop = coop; cfg.dstconf = dst; cfg.coopScan = (coop + dst + ser) % 2;
          RunOut o = runGtx(w, cfg, true);
          report(cs.name, cfg, o, true);
        }
  }

  printf("== B. write-skew probe ==\n");
  {
    HostWorkload w = writeSkew(4000, 4);
    for (int ser = 0; ser <= 1; ser++) {
      gtxg::Cfg cfg; cfg.ser = ser;
      RunOut o = runGtx(w, cfg, true);
      report(ser ? "write-skew SER" : "write-skew SI", cfg, o, true);
      if (!ser) printf("   SI anomaly witnessed: %s (DSG back edges=%lld)\n", o.rep.cycleTxns ? "YES" : "no (probe too weak)", o.rep.cycleTxns);
      if (ser && o.rep.cycleTxns) { printf("   SER produced a cycle!\n"); failures++; }
    }
  }

  printf("== C. mutation tests (expect FAIL: checker must catch the broken protocol) ==\n");
  {
    WlParams p = cases[2].p;  // identical-edge contention
    HostWorkload w1 = makeWorkload(p);
    auto counts = [](const char* n, const RunOut& o) {
      printf("   %s violations: C1-read=%lld C1-scan=%lld C2-obs=%lld C3-ww=%lld C3-sameEpoch=%lld C4-finalMissing=%lld C4-finalExtra=%lld C5-backEdges=%lld | prototype log-vs-final: missing=%lld extra=%lld\n",
             n, o.rep.readMismatch, o.rep.scanMismatch, o.rep.obsMismatch, o.rep.wwViolations, o.rep.sameEpochWW,
             o.rep.finalMissing, o.rep.finalExtra, o.rep.cycleTxns, o.rep.logFinalMissing, o.rep.logFinalExtra);
    };
    gtxg::Cfg c1; c1.mut = 1; { RunOut o = runGtx(w1, c1, true); report("mut1-no-ww-check", c1, o, false); counts("mut1", o); }
    WlParams q = cases[0].p; q.N = 20000;
    HostWorkload w2 = makeWorkload(q);
    gtxg::Cfg c2; c2.mut = 2; { RunOut o = runGtx(w2, c2, true); report("mut2-dirty-reads", c2, o, false); counts("mut2", o); }
    gtxg::Cfg c3; c3.mut = 3; { RunOut o = runGtx(w2, c3, true); report("mut3-ignore-snapshot", c3, o, false); counts("mut3", o); }
  }

  printf("== D. resource exhaustion (tiny arena; expect PASS on committed prefix) ==\n");
  {
    WlParams p; p.V = 256; p.N = 20000; p.K = 4; p.pIns = .8; p.pDel = .2; p.seed = 17;
    HostWorkload w = makeWorkload(p);
    gtxg::Cfg cfg;
    RunOut o = runGtx(w, cfg, true, nullptr, 20000);
    report("tiny-arena", cfg, o, true);
    printf("   resource aborts=%u giveups=%u commits=%u flag=%u\n", o.stats[ST_ABORT_BASE + AB_RESOURCE], o.stats[ST_GIVEUP], o.stats[ST_COMMITS], o.stats[ST_N - 1]);
    for (u32 ar : {20000u, 40000u, 200000u}) { RunOut q = runGtx(w, cfg, true, nullptr, ar); printf("   arena=%u commits=%u resource=%u flag=%u grow=%u checker=%s\n", ar, q.stats[ST_COMMITS], q.stats[ST_ABORT_BASE + AB_RESOURCE], q.stats[ST_N - 1], q.stats[ST_GROWTHS], q.rep.ok ? "PASS" : q.rep.first.c_str()); }
  }
  printf("== E. optimistic pre-walk (expect PASS) ==\n");
  for (auto& cs : cases) {
    if (only && !strstr(cs.name, only)) continue;
    HostWorkload w = makeWorkload(cs.p);
    for (int ser = 0; ser <= 1; ser++) {
      gtxg::Cfg cfg; cfg.ser = ser; cfg.prewalk = 1; cfg.coopScan = ser;
      RunOut o = runGtx(w, cfg, true);
      report((std::string(cs.name) + "+prewalk").c_str(), cfg, o, true);
    }
  }

  // ---- F. Method 4: generation merging + block reuse. Merges are forced with low thresholds and 2x growth; the
  // workloads race merges against cooperative scans and SER validation on the same (hub) vertices.
  auto m4line = [](const RunOut& o) {
    printf("   M4 droppedDelObs=%lld merges=%u gensMerged=%u kept=%u/%u linked retired=%u freed=%u reused=%u holds=%u lockBusy=%u ringFull=%u overflow=%u\n",
           o.rep.droppedDelObs,
           o.m4[gtxg::M4_MERGES], o.m4[gtxg::M4_GENS_MERGED], o.m4[gtxg::M4_KEPT], o.m4[gtxg::M4_LINKED], o.m4[gtxg::M4_RETIRED],
           o.m4[gtxg::M4_FREED], o.m4[gtxg::M4_REUSED], o.m4[gtxg::M4_HOLDS], o.m4[gtxg::M4_LOCK_BUSY], o.m4[gtxg::M4_RING_FULL],
           o.m4[gtxg::M4_OVERFLOW]);
  };
  auto m4cfg = [](int ser, int level) { gtxg::Cfg c; c.ser = ser; c.m4 = level; c.mergeMin = 16; c.growShift = 1; c.coopScan = 1; return c; };
  std::vector<Case> m4cases = cases;
  { WlParams p; p.V = 256; p.N = 30000; p.K = 4; p.src = "hub"; p.hubFrac = .5; p.pIns = .35; p.pDel = .35; p.pScan = .3; p.roFrac = .3; p.roScan = .5; p.initEdges = 1500; p.seed = 21; m4cases.push_back({"m4-hub-scan-race", p}); }
  { WlParams p; p.V = 64; p.N = 30000; p.K = 4; p.hotEdges = 16; p.hotFrac = .7; p.pIns = .4; p.pDel = .4; p.pRead = .1; p.pScan = .1; p.roFrac = .2; p.roScan = .5; p.initEdges = 300; p.seed = 22; m4cases.push_back({"m4-hot-churn-scan", p}); }
  printf("== F. Method 4 merging + reuse (expect PASS; merges must occur) ==\n");
  u32 totalMerges = 0, totalFreed = 0;
  for (auto& cs : m4cases) {
    if (only && !strstr(cs.name, only)) continue;
    HostWorkload w = makeWorkload(cs.p);
    for (int ser = 0; ser <= 1; ser++)
      for (int level : {3, 7}) {
        gtxg::Cfg cfg = m4cfg(ser, level);
        RunOut o = runGtx(w, cfg, true);
        report((std::string(cs.name) + (level == 7 ? "+m4reuse" : "+m4merge")).c_str(), cfg, o, true);
        m4line(o); totalMerges += o.m4[gtxg::M4_MERGES]; totalFreed += o.m4[gtxg::M4_FREED];
        if (o.m4[gtxg::M4_OVERFLOW] || o.m4[gtxg::M4_RING_FULL]) { printf("   M4 overflow/ring-full!\n"); failures++; }
      }
  }
  if (!only && (totalMerges == 0 || totalFreed == 0)) { printf("   section F exercised no merges/frees -- test is vacuous\n"); failures++; }
  // F2: truncated merges (at most 2 generations merged; the rest stay linked below G*) -- DELs must then be kept
  u32 totalTrunc = 0;
  for (auto& cs : m4cases) {
    if (only && !strstr(cs.name, only)) continue;
    if (strcmp(cs.name, "m4-hot-churn-scan") && strcmp(cs.name, "churn-V64-K8") && strcmp(cs.name, "m4-hub-scan-race")) continue;
    HostWorkload w = makeWorkload(cs.p);
    for (int ser = 0; ser <= 1; ser++) {
      gtxg::Cfg cfg = m4cfg(ser, 7); cfg.dbg = 1024;
      RunOut o = runGtx(w, cfg, true);
      report((std::string(cs.name) + "+m4trunc").c_str(), cfg, o, true);
      m4line(o); printf("   truncated merges=%u\n", o.m4[gtxg::M4_TRUNC]); totalTrunc += o.m4[gtxg::M4_TRUNC];
    }
  }
  if (!only && totalTrunc == 0) { printf("   F2 exercised no truncated merges -- test is vacuous\n"); failures++; }

  printf("== G. Method 4 mutations (expect FAIL) ==\n");
  {
    const Case* race = &m4cases[m4cases.size() - 2];
    const Case* hot = &m4cases[m4cases.size() - 1];
    // informational = not expected to be observable on this GPU: the 32 lanes of a cooperative scan execute the
    // prevGen load as ONE SIMT instruction, so they practically never see different values; the hazard is closed by
    // the proof (L12), not by this test. It is run and reported, but does not count as a gate failure either way.
    struct Mut { const char* name; int dbg; int ser; const Case* cs; bool informational; };
    for (Mut mu : {Mut{"m4mut-its-no-handoff", 256, 0, hot, false}, Mut{"m4mut-drop-at-frontier", 512, 0, race, false},
                   Mut{"m4mut-drop-at-frontier-SER", 512, 1, race, false}, Mut{"m4mut-perlane-genlist", 128, 0, race, true},
                   Mut{"m4mut-trunc-drop-dels", 1024 | 2048, 0, hot, false}}) {
      HostWorkload w = makeWorkload(mu.cs->p);
      gtxg::Cfg cfg = m4cfg(mu.ser, 7); cfg.dbg = mu.dbg;
      RunOut o = runGtx(w, cfg, true);
      if (mu.informational) printf("%-26s (informational, SIMT-lockstep hazard) checker=%s\n", mu.name, o.rep.ok ? "PASS (not observable here)" : "FAIL (observed)");
      else report(mu.name, cfg, o, false);
      m4line(o);
      printf("   violations: C1-read=%lld C1-scan=%lld C2-obs=%lld C3-ww=%lld C3-sameEpoch=%lld C4-missing=%lld C4-extra=%lld C5-backEdges=%lld\n",
             o.rep.readMismatch, o.rep.scanMismatch, o.rep.obsMismatch, o.rep.wwViolations, o.rep.sameEpochWW,
             o.rep.finalMissing, o.rep.finalExtra, o.rep.cycleTxns);
    }
  }

  printf("== H. resource exhaustion with M4 reuse (expect PASS; compare commits with section D) ==\n");
  {
    WlParams p; p.V = 256; p.N = 20000; p.K = 4; p.pIns = .8; p.pDel = .2; p.seed = 17;
    HostWorkload w = makeWorkload(p);
    for (u32 ar : {20000u, 40000u, 200000u}) {
      gtxg::Cfg cfg = m4cfg(0, 7); cfg.growShift = 3;
      RunOut q = runGtx(w, cfg, true, nullptr, ar);
      printf("   m4 arena=%u commits=%u resource=%u flag=%u grow=%u checker=%s\n", ar, q.stats[ST_COMMITS], q.stats[ST_ABORT_BASE + AB_RESOURCE],
             q.stats[ST_N - 1], q.stats[ST_GROWTHS], q.rep.ok ? "PASS" : q.rep.first.c_str());
      m4line(q);
      if (!q.rep.ok) failures++;
    }
  }

  printf("== I. M5 quiescent compaction over multi-round streams (expect PASS; mutations expect FAIL) ==\n");
  {
    // FIFO-delete churn versions of the section A workloads: 6 rounds, compaction forced before every round after the
    // first, every round history-checked from its pre-compaction start state, every compaction compared directly.
    std::vector<Case> qcases;
    { WlParams p; p.V = 256; p.K = 4; p.pIns = .4; p.pDel = .4; p.pRead = .1; p.pScan = .1; p.initEdges = 2000; p.seed = 21; p.fifoDel = 1; qcases.push_back({"qc-mixed-uniform-V256", p}); }
    { WlParams p; p.V = 1024; p.K = 4; p.src = "hub"; p.hubFrac = .5; p.pIns = .5; p.pDel = .3; p.pRead = .1; p.pScan = .1; p.initEdges = 3000; p.seed = 22; qcases.push_back({"qc-hub50-mixed", p}); }
    { WlParams p; p.V = 512; p.K = 2; p.hotEdges = 8; p.hotFrac = .8; p.pIns = .5; p.pDel = .5; p.initEdges = 1000; p.seed = 23; p.fifoDel = 1; qcases.push_back({"qc-identical-edge-8", p}); }
    { WlParams p; p.V = 2048; p.K = 4; p.src = "zipf"; p.zipfS = 1.1; p.pIns = .6; p.pDel = .2; p.pRead = .1; p.pScan = .1; p.roFrac = .5; p.roScan = .3; p.initEdges = 8000; p.seed = 24; qcases.push_back({"qc-zipf-readers50", p}); }
    const u32 rounds = 6, per = 4000;
    // Correctness = every checked round passes (committed prefix, as in sections A and D). Exhaustion or watchdog flags in
    // the adversarial SER cases are reported in `flags`; they are failures only when requireNoOom (the trigger tests).
    auto runQc = [&](const Case& cs, gtxg::Cfg cfg, u32 arena, u32 qcEvery, std::string& why, u32& nQc, u32& nChecked,
                     bool requireNoOom = false, u32* flags = nullptr) {
      WlParams p = cs.p; p.N = rounds * per;
      HostWorkload w = makeWorkload(p);
      LongRunCfg lr; lr.rounds = rounds; lr.perRound = per; lr.qc = 1; lr.checkEvery = 1; lr.qcEvery = qcEvery; lr.stopOnOom = 0;
      nQc = 0; nChecked = 0; why.clear();
      int oom = 0;
      int bad = runLongRun(w, cfg, lr, arena, 16000000, [&](const RoundOut& ro) {
        nQc += ro.compacted; if (ro.check >= 0) nChecked++;
        if (!ro.fail.empty() && why.empty()) why = "round " + std::to_string(ro.round) + ": " + ro.fail;
        if (flags) *flags |= ro.st[ST_N - 1];
        if (ro.oom) { oom = 1; if (requireNoOom && why.empty()) why = "OOM in round " + std::to_string(ro.round); }
      });
      return bad == 0 && (!requireNoOom || oom == 0) && why.empty();
    };
    // Kernel variants: hyb = default hybrid kernels (small graphs: nearly all vertices take the warp-per-vertex path);
    // chunk = the long-run policy (growShift 1, slack 100) with every vertex above 8 slots forced onto the chunk path;
    // legacy = the first warp-per-vertex kernels (qcChunk 0), on the coop == dst combinations.
    struct QVar { const char* name; u32 chunk, big, gs1, slack; };
    const QVar qvars[3] = {{"hyb", 1, 4096, 0, 0}, {"chunk", 1, 8, 1, 100}, {"legacy", 0, 4096, 0, 0}};
    auto applyVar = [](gtxg::Cfg& cfg, const QVar& qv) {
      cfg.qcChunk = qv.chunk; cfg.qcBigSlots = qv.big;
      if (qv.gs1) cfg.growShift = 1;
      if (qv.slack) cfg.qcSlackPct = qv.slack;
    };
    u32 totalQc = 0;
    for (auto& cs : qcases) {
      if (only && !strstr(cs.name, only)) continue;
      for (const QVar& qv : qvars)
      for (int ser = 0; ser <= 1; ser++)
        for (int coop = 0; coop <= 1; coop++)
          for (int dst = 0; dst <= 1; dst++) {
            if ((quick || !qv.chunk) && coop != dst) continue;
            gtxg::Cfg cfg; cfg.ser = ser; cfg.coop = coop; cfg.dstconf = dst; cfg.coopScan = (coop + dst + ser) % 2;
            cfg.qcSlackPct = (coop + dst) % 2 ? 50 : 0;
            applyVar(cfg, qv);
            std::string why; u32 nQc, nChk, fl = 0;
            bool ok = runQc(cs, cfg, 2000000, 1, why, nQc, nChk, false, &fl);
            totalQc += nQc;
            if (!ok || nQc != rounds - 1 || nChk != rounds) failures++;
            printf("%-26s %-6s coop=%d dst=%d ser=%d cscan=%d gs=%d slack=%u | compactions=%u checkedRounds=%u flags=%u | checker=%s %s %s\n", cs.name,
                   qv.name, coop, dst, ser, cfg.coopScan, cfg.growShift, cfg.qcSlackPct, nQc, nChk, fl, ok ? "PASS" : "FAIL",
                   ok && nQc == rounds - 1 && nChk == rounds ? "[as expected]" : "[UNEXPECTED]", why.c_str());
            fflush(stdout);
          }
    }
    if (!only || strstr("qc-trigger", only)) {  // triggered (not forced) compaction under a small arena: must never OOM
      WlParams p; p.V = 1024; p.K = 4; p.src = "zipf"; p.zipfS = 1.0; p.pIns = .4; p.pDel = .4; p.pRead = .2; p.initEdges = 4000; p.seed = 25; p.fifoDel = 1;
      Case cs{"qc-trigger-small-arena", p};
      for (const QVar& qv : qvars)
      for (int ser = 0; ser <= 1; ser++) {
        gtxg::Cfg cfg; cfg.ser = ser; applyVar(cfg, qv);
        std::string why; u32 nQc, nChk;
        const u32 arena = qv.gs1 ? 120000 : 400000;  // 2x growth needs a smaller arena to reach the trigger
        bool ok = runQc(cs, cfg, arena, 0, why, nQc, nChk, true);
        bool good = ok && nQc >= 1;
        if (!good) failures++;
        printf("%-26s %-6s ser=%d arena=%u | compactions=%u checkedRounds=%u | checker=%s %s %s\n", cs.name, qv.name, ser, arena, nQc, nChk,
               ok ? "PASS" : "FAIL", good ? "[as expected]" : "[UNEXPECTED]", why.c_str());
        fflush(stdout);
      }
    }
    if (!only && totalQc == 0) { printf("   section I exercised no compactions -- test is vacuous\n"); failures++; }
    // F - 1 is informational: at a launch boundary the newest epoch is normally empty (the advancer closed it), so
    // compacting at F - 1 keeps every commit and is not a defect there. The observable stale-frontier mutation is F / 2.
    struct QMut { const char* name; int dbg; bool informational; };
    for (QMut mu : {QMut{"qcmut-drop-live-edge", 4096, false}, QMut{"qcmut-keep-invalidated", 8192, false},
                    QMut{"qcmut-stale-frontier-F/2", 32768, false}, QMut{"qcmut-compact-at-F-1", 16384, true}}) {
      if (only && !strstr(mu.name, only)) continue;
      for (const QVar& qv : qvars)
      for (int ser = 0; ser <= 1; ser++) {
        gtxg::Cfg cfg; cfg.ser = ser; cfg.dbg = mu.dbg; applyVar(cfg, qv);
        std::string why; u32 nQc, nChk;
        bool ok = runQc(qcases[0], cfg, 2000000, 1, why, nQc, nChk);
        if (ok && !mu.informational) failures++;
        printf("%-26s %-6s ser=%d | compactions=%u | checker=%s %s %s\n", mu.name, qv.name, ser, nQc, ok ? "PASS" : "FAIL",
               mu.informational ? "[informational]" : ok ? "[UNEXPECTED]" : "[as expected]", why.c_str());
        fflush(stdout);
      }
    }
  }

  printf("\nRESULT: %s (%d unexpected)\n", failures ? "FAILURES" : "ALL AS EXPECTED", failures);
  return failures ? 1 : 0;
}
