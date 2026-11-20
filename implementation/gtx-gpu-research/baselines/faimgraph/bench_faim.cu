// faimGraph (Winter et al., SC'18; upstream GPUPeople/faimGraph @ d54a72e) on the SAME workload streams as bench.cu
// (workload.hpp generator), mirroring baselines/gpma/bench_gpma.cu.
// * The initial graph is written as a DIMACS (METIS-style, 1-based, one directed adjacency line per vertex) file and
//   loaded with faimGraph's own parser + initializeMemory (not timed).
// * The op stream is cut into batches of --batch ops; each batch is applied as one insertion batch followed by one
//   deletion batch (faimGraph has no mixed batches) -- like GPMA+, intra-batch order is not preserved, so final-state
//   verification is exact only for streams whose insert and delete keys are disjoint (SNAP sliding windows,
//   insert-only streams). Duplicate checking within a batch is faimGraph's own (enabled by default).
// * Timing: cudaEvents around faimGraph's edgeInsertion()/edgeDeletion(), which INCLUDE faimGraph's internal
//   host->device copy of the batch (its API takes host batches). The same bytes are also copied alone and timed
//   ("h2d_ms") so the PCIe share can be subtracted for comparison with device-resident GPMA+/GTX inputs.
// Output: RESULT,label,faimgraph,rep,ms,batches,edges,effective,edges_per_s,eff_per_s,p50_batch_ms,p99_batch_ms,bytes,verify,h2d_ms
#include <algorithm>
#include <cstdio>
#include <fstream>
#include <map>
#include <string>
#include <unordered_set>
#include <vector>
#include "MemoryManager.h"
#include "GraphParser.h"
#include "faimGraph.h"
#include "EdgeUpdate.h"
#include "ConfigurationParser.h"
#include "../../src/workload.hpp"

static std::map<std::string, std::string> args;
static double AD(const char* k, double d) { auto it = args.find(k); return it == args.end() ? d : atof(it->second.c_str()); }
static std::string A(const char* k, const char* d) { auto it = args.find(k); return it == args.end() ? d : it->second; }

using FG = faimGraph<VertexData, VertexUpdate, EdgeData, EdgeDataUpdate>;

int main(int argc, char** argv) {
  for (int i = 1; i + 1 < argc; i += 2) args[argv[i] + 2] = argv[i + 1];
  WlParams p;
  p.V = (u32)AD("V", 1 << 20); p.N = (u32)AD("N", 1 << 20); p.K = (u32)AD("K", 1);
  p.pIns = AD("pins", 1); p.pDel = AD("pdel", 0); p.src = A("src", "uniform"); p.hubFrac = AD("hub", 0);
  p.zipfS = AD("zipf", 1.0); p.hotEdges = (u32)AD("hot", 0); p.hotFrac = AD("hotfrac", 0);
  p.initEdges = (u32)AD("init", 0); p.seed = (u64)AD("seed", 1);
  p.graph = A("graph", ""); p.initFrac = AD("initfrac", 0.8);
  const u32 batch = (u32)AD("batch", 65536);
  const int reps = (int)AD("reps", 5);
  const double memGB = AD("memgb", 3.0);
  const std::string label = A("label", "run"), tmp = A("tmp", "faim_tmp");
  if (batch > (u32)MAXIMAL_BATCH_SIZE) { fprintf(stderr, "faimGraph supports batches <= %d\n", MAXIMAL_BATCH_SIZE); return 2; }
  HostWorkload w = makeWorkload(p);
  for (auto& o : w.ops) if (o.type != OP_INS && o.type != OP_DEL) { fprintf(stderr, "faimGraph harness: INS/DEL only\n"); return 2; }

  // ---- initial graph -> DIMACS file (directed adjacency lists, 1-based)
  {
    std::vector<std::vector<u32>> adj(w.V);
    for (auto& e : w.initEdges) adj[e.first].push_back(e.second + 1);
    FILE* f = fopen((tmp + ".graph").c_str(), "wb");
    fprintf(f, "%u %zu\n", w.V, w.initEdges.size());
    std::string line;
    for (u32 u = 0; u < w.V; u++) {
      line.clear();
      for (size_t i = 0; i < adj[u].size(); i++) { if (i) line += ' '; line += std::to_string(adj[u][i]); }
      line += '\n';
      fwrite(line.data(), 1, line.size(), f);
    }
    fclose(f);
  }
  // ---- configuration file (faimGraph's XML format)
  {
    std::ofstream x(tmp + ".xml");
    x << "<aimGraph><global><deviceID>0</deviceID><devicememsize>" << memGB << "</devicememsize></global><testrun><configuration>"
      << "<memorylayout>AOS</memorylayout><graphmode>simple</graphmode><updatevariant>standard</updatevariant>"
      << "<rounds>1</rounds><updaterounds>1</updaterounds><pagesize>64</pagesize><initlaunchblocksize>32</initlaunchblocksize>"
      << "<insertlaunchblocksize>256</insertlaunchblocksize><deletelaunchblocksize>256</deletelaunchblocksize>"
      << "<deletionvariation>standard</deletionvariation><verification>false</verification><performanceoutput>stdout</performanceoutput>"
      << "<memoryoverallocation>1.0</memoryoverallocation></configuration><graphs><filename>" << tmp << ".graph</filename></graphs>"
      << "<batches><batchsize>" << batch << "</batchsize></batches></testrun></aimGraph>\n";
  }
  ConfigurationParser cp(tmp + ".xml");
  std::shared_ptr<Config> config = cp.parseConfiguration();
  std::unique_ptr<GraphParser> parser(new GraphParser(tmp + ".graph"));
  if (!parser->parseGraph()) { fprintf(stderr, "faimGraph parser failed\n"); return 2; }

  // ---- batches + expected final state (sequential semantics; exact when insert/delete keys are disjoint per batch)
  std::vector<std::vector<EdgeDataUpdate>> bIns, bDel;
  for (size_t i = 0; i < w.ops.size(); i += batch) {
    size_t e = std::min(w.ops.size(), i + batch);
    std::vector<EdgeDataUpdate> ins, del;
    for (size_t j = i; j < e; j++) { EdgeDataUpdate u; u.source = w.ops[j].u; u.update.destination = w.ops[j].v; (w.ops[j].type == OP_INS ? ins : del).push_back(u); }
    bIns.push_back(ins); bDel.push_back(del);
  }
  std::unordered_set<u64> live;
  for (auto& e : w.initEdges) live.insert(((u64)e.first << 32) | e.second);
  size_t effective = 0;
  for (auto& o : w.ops) { u64 k = ((u64)o.u << 32) | o.v; if (o.type == OP_INS) effective += live.insert(k).second; else effective += live.erase(k); }

  cudaEvent_t a, c; cudaEventCreate(&a); cudaEventCreate(&c);
  for (int rep = -1; rep < reps; rep++) {
    parser->getFreshGraph();
    std::unique_ptr<FG> fg = std::make_unique<FG>(config, parser);
    fg->initializeMemory(parser);
    cudaDeviceSynchronize();
    std::vector<double> per; double tot = 0, h2d = 0;
    void* scratch = nullptr; cudaMalloc(&scratch, (size_t)batch * sizeof(EdgeDataUpdate));
    for (size_t b = 0; b < bIns.size(); b++) {
      double t = 0;
      for (int kind = 0; kind < 2; kind++) {
        auto& src = kind == 0 ? bIns[b] : bDel[b];
        if (src.empty()) continue;
        auto up = std::make_unique<EdgeUpdateBatch<EdgeDataUpdate>>();
        up->edge_update = src;
        fg->edge_update_manager->receiveEdgeUpdates(std::move(up), EdgeUpdateVersion::GENERAL);
        cudaDeviceSynchronize();
        cudaEventRecord(a);
        if (kind == 0) fg->edgeInsertion(); else fg->edgeDeletion();
        cudaEventRecord(c); cudaEventSynchronize(c);
        float ms = 0; cudaEventElapsedTime(&ms, a, c); t += ms;
        cudaEventRecord(a);
        cudaMemcpy(scratch, src.data(), src.size() * sizeof(EdgeDataUpdate), cudaMemcpyHostToDevice);
        cudaEventRecord(c); cudaEventSynchronize(c);
        float hm = 0; cudaEventElapsedTime(&hm, a, c); h2d += hm;
      }
      per.push_back(t); tot += t;
    }
    cudaFree(scratch);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) { fprintf(stderr, "CUDA error %s\n", cudaGetErrorString(err)); return 3; }
    if (rep < 0) continue;
    // ---- verify the final live edge set
    auto vg = fg->verifyGraphStructure(fg->memory_manager);
    size_t got = 0, bad = 0, dup = 0;
    std::unordered_set<u64> seen;
    for (u32 u = 0; u < w.V; u++)
      for (u32 i = vg->h_offset[u]; i < vg->h_offset[u + 1]; i++) {
        u64 k = ((u64)u << 32) | vg->h_adjacency[i];
        got++; if (!seen.insert(k).second) dup++; if (!live.count(k)) bad++;
      }
    bool ok = got == live.size() && !bad && !dup;
    if (!ok) fprintf(stderr, "verify: live=%zu got=%zu bad=%zu dup=%zu\n", live.size(), got, bad, dup);
    std::sort(per.begin(), per.end());
    size_t bytes = (size_t)fg->memory_manager->next_free_page * fg->memory_manager->page_size + (size_t)w.V * sizeof(VertexData);
    printf("RESULT,%s,faimgraph,%d,%.4f,%zu,%zu,%zu,%.1f,%.1f,%.4f,%.4f,%zu,%s,%.4f\n", label.c_str(), rep, tot, bIns.size(), w.ops.size(),
           effective, w.ops.size() / (tot / 1000), effective / (tot / 1000), per[per.size() / 2], per[(size_t)(0.99 * (per.size() - 1))],
           bytes, ok ? "PASS" : "FAIL", h2d);
    fflush(stdout);
  }
  return 0;
}
