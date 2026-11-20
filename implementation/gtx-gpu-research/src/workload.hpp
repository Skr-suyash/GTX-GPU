// Deterministic workload generator (splitmix64). All systems consume the same HostWorkload.
#pragma once
#include <algorithm>
#include <cmath>
#include <string>
#include <unordered_set>
#include <vector>
#include "common.cuh"

struct Rng {
  u64 s;
  explicit Rng(u64 seed) : s(seed * 0x9E3779B97F4A7C15ull + 1) {}
  u64 next() { u64 z = (s += 0x9E3779B97F4A7C15ull); z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull; z = (z ^ (z >> 27)) * 0x94D049BB133111EBull; return z ^ (z >> 31); }
  u32 below(u32 n) { return (u32)(next() % n); }
  double unit() { return (next() >> 11) * (1.0 / 9007199254740992.0); }
};

struct WlParams {
  u32 V = 1 << 16, N = 1 << 16, K = 1;
  double pIns = 1, pDel = 0, pRead = 0, pScan = 0;   // op mix of update transactions
  double roFrac = 0;                                  // fraction of read-only transactions
  double roScan = 0.2;                                // fraction of scans inside read-only txns
  std::string src = "uniform";                        // uniform | hub | zipf | rmat
  double hubFrac = 0; u32 nHubs = 1; double zipfS = 1.0;
  u32 hotEdges = 0; double hotFrac = 0;               // identical-edge contention
  u32 initEdges = 0;
  u64 seed = 1;
  std::string graph;                                  // src=file: binary edge cache (scripts/snap2bin.py)
  double initFrac = 0.8;                              // src=file: fraction of the (shuffled) edges loaded initially
  int fifoDel = 0;                                    // synthetic: DEL removes the oldest inserted/initial edge (constant live size)
};

// Binary edge cache: 'GTXE' | u32 V | u64 E | E x (u32 u, u32 v)
inline bool loadEdgeCache(const std::string& path, u32& V, std::vector<std::pair<u32, u32>>& e) {
  FILE* f = fopen(path.c_str(), "rb");
  if (!f) return false;
  char mg[4]; u64 E = 0;
  bool ok = fread(mg, 1, 4, f) == 4 && mg[0] == 'G' && mg[1] == 'T' && mg[2] == 'X' && mg[3] == 'E' &&
            fread(&V, 4, 1, f) == 1 && fread(&E, 8, 1, f) == 1;
  if (ok) { e.resize(E); ok = fread(e.data(), 8, E, f) == E; }
  fclose(f);
  return ok;
}

// Real-graph sliding-window stream (GPMA-style): edges are shuffled with the seed; the first initFrac are the initial
// graph; INS takes the next unseen edge, DEL removes the oldest edge of the window, READ/SCAN target a random edge
// (degree-proportional source). Insert and delete keys are disjoint by construction (no intra-batch duplicates).
inline HostWorkload makeFileWorkload(const WlParams& p) {
  HostWorkload w; std::vector<std::pair<u32, u32>> e;
  if (!loadEdgeCache(p.graph, w.V, e)) { fprintf(stderr, "cannot read edge cache %s\n", p.graph.c_str()); exit(2); }
  Rng r(p.seed);
  for (size_t i = e.size(); i > 1; i--) { size_t j = r.next() % i; std::swap(e[i - 1], e[j]); }
  size_t nInit = (size_t)(p.initFrac * e.size());
  w.initEdges.assign(e.begin(), e.begin() + nInit);
  size_t ins = nInit, del = 0;
  double tot = p.pIns + p.pDel + p.pRead + p.pScan;
  w.off.push_back(0);
  for (u32 t = 0; t < p.N; t++) {
    bool ro = r.unit() < p.roFrac;
    for (u32 j = 0; j < p.K; j++) {
      Op op;
      if (ro) { auto x = e[r.next() % e.size()]; op.type = (r.unit() < p.roScan) ? OP_SCAN : OP_READ; op.u = x.first; op.v = x.second; }
      else {
        double x = r.unit() * tot;
        if (x < p.pIns) {
          if (ins >= e.size()) { fprintf(stderr, "file stream exhausted: %zu inserts requested past the %zu-edge tail (lower N or initfrac)\n", ins - nInit + 1, e.size() - nInit); exit(2); }
          op.type = OP_INS; op.u = e[ins].first; op.v = e[ins].second; ins++;
        } else if (x < p.pIns + p.pDel) {
          if (del >= nInit) { fprintf(stderr, "file stream exhausted: more deletes than initial edges\n"); exit(2); }
          op.type = OP_DEL; op.u = e[del].first; op.v = e[del].second; del++;
        } else { auto y = e[r.next() % e.size()]; op.type = (x < p.pIns + p.pDel + p.pRead) ? OP_READ : OP_SCAN; op.u = y.first; op.v = y.second; }
      }
      w.ops.push_back(op);
    }
    w.off.push_back((u32)w.ops.size());
  }
  return w;
}

struct SrcSampler {
  const WlParams& p; std::vector<double> cdf; int rmatLevels = 0;
  explicit SrcSampler(const WlParams& p_) : p(p_) {
    if (p.src == "zipf") {
      cdf.resize(p.V); double s = 0;
      for (u32 i = 0; i < p.V; i++) { s += 1.0 / std::pow((double)(i + 1), p.zipfS); cdf[i] = s; }
      for (auto& x : cdf) x /= s;
    }
    if (p.src == "rmat") { while ((1u << rmatLevels) < p.V) rmatLevels++; }
  }
  u32 src(Rng& r) const {
    if (p.src == "hub") { if (r.unit() < p.hubFrac) return r.below(p.nHubs); return r.below(p.V); }
    if (p.src == "zipf") { double x = r.unit(); return (u32)(std::lower_bound(cdf.begin(), cdf.end(), x) - cdf.begin()) % p.V; }
    if (p.src == "rmat") {  // Graph500 parameters a=.57 b=.19 c=.19: source bits
      u32 u = 0; for (int l = 0; l < rmatLevels; l++) { double x = r.unit(); u = (u << 1) | (x >= 0.57 + 0.19 ? 1u : 0u); }
      return u % p.V;
    }
    return r.below(p.V);
  }
  u32 dst(Rng& r, u32 u) const { u32 v = r.below(p.V); if (v == u) v = (v + 1) % p.V; return v; }
};

inline HostWorkload makeWorkload(const WlParams& p) {
  if (p.src == "file") return makeFileWorkload(p);
  HostWorkload w; w.V = p.V;
  Rng r(p.seed);
  SrcSampler S(p);
  std::vector<std::pair<u32, u32>> hot;
  for (u32 i = 0; i < p.hotEdges; i++) { u32 u = S.src(r); hot.push_back({u, S.dst(r, u)}); }
  std::unordered_set<u64> seen;
  for (u32 i = 0; i < p.initEdges; i++) {
    u32 u = S.src(r), v = S.dst(r, u);
    if (seen.insert(((u64)u << 32) | v).second) w.initEdges.push_back({u, v});
  }
  std::vector<std::pair<u32, u32>> pool(w.initEdges);  // candidate targets for deletes
  size_t poolHead = 0;                                 // fifoDel: next edge to delete
  auto pick = [&](u32& u, u32& v) {
    if (!hot.empty() && r.unit() < p.hotFrac) { auto e = hot[r.below((u32)hot.size())]; u = e.first; v = e.second; return; }
    u = S.src(r); v = S.dst(r, u);
  };
  w.off.push_back(0);
  double tot = p.pIns + p.pDel + p.pRead + p.pScan;
  for (u32 t = 0; t < p.N; t++) {
    bool ro = r.unit() < p.roFrac;
    for (u32 j = 0; j < p.K; j++) {
      Op op; u32 u, v;
      if (ro) {
        pick(u, v);
        op.type = (r.unit() < p.roScan) ? OP_SCAN : OP_READ; op.u = u; op.v = v;
      } else {
        double x = r.unit() * tot;
        if (x < p.pIns) { pick(u, v); op.type = OP_INS; pool.push_back({u, v}); }
        else if (x < p.pIns + p.pDel) {
          if (p.fifoDel && poolHead < pool.size() && !(p.hotEdges && r.unit() < p.hotFrac)) { auto e = pool[poolHead++]; u = e.first; v = e.second; }
          else if (!p.fifoDel && !pool.empty() && !(p.hotEdges && r.unit() < p.hotFrac)) { auto e = pool[r.below((u32)pool.size())]; u = e.first; v = e.second; }
          else pick(u, v);
          op.type = OP_DEL;
        } else if (x < p.pIns + p.pDel + p.pRead) { pick(u, v); op.type = OP_READ; }
        else { pick(u, v); op.type = OP_SCAN; }
        op.u = u; op.v = v;
      }
      w.ops.push_back(op);
    }
    w.off.push_back((u32)w.ops.size());
  }
  return w;
}

// Workload made of single-insert transactions loading the initial graph.
inline HostWorkload loaderWorkload(const HostWorkload& w) {
  HostWorkload l; l.V = w.V; l.off.push_back(0);
  for (auto& e : w.initEdges) { l.ops.push_back({OP_INS, e.first, e.second}); l.off.push_back((u32)l.ops.size()); }
  return l;
}
