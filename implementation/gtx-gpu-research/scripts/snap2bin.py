"""Convert a SNAP edge list (.txt or .txt.gz) to the binary edge cache read by workload.hpp (src=file).

Edges are directed pairs in file order. Self loops and duplicate (u, v) pairs (keeping the first occurrence) are
dropped. Vertex ids are remapped densely in increasing order of the original id. Output format (little endian):
    char[4] 'GTXE' | u32 V | u64 E | E x (u32 u, u32 v)
usage: python scripts/snap2bin.py data/snap/wiki-Talk.txt.gz data/snap/wiki-Talk.bin
Also prints a degree summary and the GTX-GPU slot estimate used to size the arena:
  ladder = generations 8, 64, 512, ... (loader through transactions); bulk = one generation of pow2ceil(deg + 1).
"""
import gzip, re, sys
import numpy as np


def header_edges(src):
    """Edge count declared in the SNAP header ('# Nodes: N Edges: E'), or None."""
    with (gzip.open if src.endswith(".gz") else open)(src, "rt") as f:
        for _ in range(10):
            l = f.readline()
            if not l.startswith("#"):
                return None
            m = re.search(r"Edges:\s*(\d+)", l)
            if m:
                return int(m.group(1))
    return None


def main(src, dst):
    a = np.loadtxt(src, dtype=np.int64, comments=("#", "%"), usecols=(0, 1), ndmin=2)
    he = header_edges(src)
    print(f"parsed {len(a)} lines; header says {he}" + ("" if he is None or he == len(a) else "  ** MISMATCH (truncated download?) **"))
    if he is not None and len(a) < he:
        sys.exit(f"{src}: fewer edges than the header declares - re-download")
    a = a[a[:, 0] != a[:, 1]]
    ids, inv = np.unique(a, return_inverse=True)
    e = inv.reshape(-1, 2).astype(np.uint64)
    key = (e[:, 0] << np.uint64(32)) | e[:, 1]
    _, first = np.unique(key, return_index=True)
    e = e[np.sort(first)].astype(np.uint32)
    V, E = len(ids), len(e)
    with open(dst, "wb") as f:
        f.write(b"GTXE")
        f.write(np.array([V], dtype=np.uint32).tobytes())
        f.write(np.array([E], dtype=np.uint64).tobytes())
        f.write(np.ascontiguousarray(e).tobytes())
    deg = np.bincount(e[:, 0], minlength=V).astype(np.int64)
    top = np.sort(deg)[::-1][:8]
    # slot estimates for the initial 80% window
    d8 = np.bincount(e[: int(0.8 * E), 0], minlength=V).astype(np.int64)
    ladder = 0
    caps = [8 * 8 ** k for k in range(10)]
    for d in d8[d8 > 0]:
        tot = 0
        for c in caps:
            tot += c
            if tot >= d:
                break
        ladder += tot
    nz = d8[d8 > 0]
    bulk = int(np.sum(np.maximum(8, 2 ** np.ceil(np.log2(nz + 1)).astype(np.int64))))
    print(f"{src}: V={V} E={E} maxdeg={top[0]} top={top.tolist()} mean={E / V:.2f} srcs={int((deg > 0).sum())} "
          f"| 80% window: edges={int(d8.sum())} ladder_slots={ladder} bulk_slots={bulk} "
          f"(x32B: ladder {ladder * 32 / 2**30:.2f} GB, bulk {bulk * 32 / 2**30:.2f} GB)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
