# GPMA+ vs transactional systems on identical streams (effective edge changes per second)

GPMA+ applies each batch as one sorted unit (no multi-edge transactions, no concurrent readers, intra-batch INS/DEL order not preserved). Transactional systems commit every operation as its own transaction (K=1). Times are GPU operation time only.

| stream | system | batch | median ms | effective edges/s | final-state verify | GTX-GPU speedup |
|---|---|---:|---:|---:|---|---:|
| hub50-ins-K1 | GPMA+ (Windows port) | 65536 | 29.92 | 19.58 M | FAIL | 10.1x |
| hub50-ins-K1 | GPMA+ (Windows port) | 524288 | 25.95 | 22.57 M | FAIL | 8.8x |
| hub50-ins-K1 | GPMA+ (upstream, CDP1) | 65536 | 28.18 | 20.79 M | FAIL | 9.5x |
| hub50-ins-K1 | GPMA+ (upstream, CDP1) | 524288 | 23.10 | 25.36 M | FAIL | 7.8x |
| hub50-ins-K1 | GTX-GPU (ours) | txn | 2.96 | 197.74 M | - | |
| hub50-ins-K1 | GTX-GPU + M4 merge/reuse | txn | 3.05 | 191.90 M | - | |
| hub50-ins-K1 | GTX-GPU, 2x growth layout | txn | 3.70 | 158.33 M | - | |
| hub50-ins-K1 | GTX-conservative port | txn | 3.59 | 163.11 M | - | |
| hub50-ins-K1 | TL2 word-STM | txn | 167.55 | 3.16 M | - | |
| hub50-ins-K1 | TL2 word-STM (no degree) | txn | 1.89 | 310.22 M | - | |
| hub50-ins-K1 | non-transactional CAS | txn | 1.56 | 375.36 M | - | |
| rmat-churn-K1 | GPMA+ (Windows port) | 65536 | 27.28 | 37.32 M | FAIL | 6.8x |
| rmat-churn-K1 | GPMA+ (Windows port) | 524288 | 25.30 | 40.24 M | FAIL | 6.3x |
| rmat-churn-K1 | GPMA+ (upstream, CDP1) | 65536 | 28.42 | 35.82 M | FAIL | 7.1x |
| rmat-churn-K1 | GPMA+ (upstream, CDP1) | 524288 | 23.13 | 44.01 M | FAIL | 5.8x |
| rmat-churn-K1 | GTX-GPU (ours) | txn | 3.99 | 254.99 M | - | |
| rmat-churn-K1 | GTX-GPU + M4 merge/reuse | txn | 4.22 | 241.37 M | - | |
| rmat-churn-K1 | GTX-GPU, 2x growth layout | txn | 5.38 | 189.20 M | - | |
| rmat-churn-K1 | GTX-conservative port | txn | 3.95 | 257.37 M | - | |
| rmat-churn-K1 | 2PL vertex locks | txn | 27.25 | 37.33 M | - | |
| rmat-churn-K1 | TL2 word-STM | txn | 86.50 | 11.67 M | - | |
| rmat-churn-K1 | TL2 word-STM (no degree) | txn | 2.36 | 430.93 M | - | |
| rmat-churn-K1 | non-transactional CAS | txn | 1.57 | 646.54 M | - | |
| snap-cit-Patents-churn-K1 | GPMA+ (Windows port) | 65536 | 63.50 | 33.03 M | PASS | 6.9x |
| snap-cit-Patents-churn-K1 | GPMA+ (upstream, CDP1) | 65536 | 60.10 | 34.89 M | PASS | 6.6x |
| snap-cit-Patents-churn-K1 | GTX-GPU (ours) | txn | 9.15 | 229.19 M | - | |
| snap-cit-Patents-churn-K1 | GTX-GPU + M4 merge/reuse | txn | 9.76 | 214.88 M | - | |
| snap-cit-Patents-churn-K1 | GTX-GPU, 2x growth layout | txn | 9.05 | 231.62 M | - | |
| snap-cit-Patents-churn-K1 | GTX-conservative port | txn | 9.19 | 228.11 M | - | |
| snap-cit-Patents-churn-K1 | 2PL vertex locks | txn | 5.99 | 349.85 M | - | |
| snap-cit-Patents-churn-K1 | TL2 word-STM | txn | 8.47 | 247.55 M | - | |
| snap-cit-Patents-churn-K1 | TL2 word-STM (no degree) | txn | 5.26 | 398.37 M | - | |
| snap-cit-Patents-churn-K1 | non-transactional CAS | txn | 4.94 | 424.72 M | - | |
| snap-cit-Patents-ins-K1 | GPMA+ (Windows port) | 65536 | 101.96 | 20.57 M | PASS | 12.4x |
| snap-cit-Patents-ins-K1 | GPMA+ (upstream, CDP1) | 65536 | 101.48 | 20.66 M | PASS | 12.3x |
| snap-cit-Patents-ins-K1 | GTX-GPU (ours) | txn | 8.22 | 255.08 M | - | |
| snap-cit-Patents-ins-K1 | GTX-GPU + M4 merge/reuse | txn | 8.35 | 251.29 M | - | |
| snap-cit-Patents-ins-K1 | GTX-GPU, 2x growth layout | txn | 8.22 | 255.20 M | - | |
| snap-cit-Patents-ins-K1 | GTX-conservative port | txn | 8.23 | 254.73 M | - | |
| snap-cit-Patents-ins-K1 | 2PL vertex locks | txn | 6.18 | 339.35 M | - | |
| snap-cit-Patents-ins-K1 | TL2 word-STM | txn | 8.86 | 236.74 M | - | |
| snap-cit-Patents-ins-K1 | TL2 word-STM (no degree) | txn | 5.47 | 383.23 M | - | |
| snap-cit-Patents-ins-K1 | non-transactional CAS | txn | 4.99 | 420.27 M | - | |
| snap-roadNet-CA-churn-K1 | GPMA+ (Windows port) | 65536 | 37.12 | 28.25 M | PASS | 8.8x |
| snap-roadNet-CA-churn-K1 | GPMA+ (upstream, CDP1) | 65536 | 34.63 | 30.28 M | PASS | 8.2x |
| snap-roadNet-CA-churn-K1 | GTX-GPU (ours) | txn | 4.20 | 249.39 M | - | |
| snap-roadNet-CA-churn-K1 | GTX-GPU + M4 merge/reuse | txn | 4.64 | 226.15 M | - | |
| snap-roadNet-CA-churn-K1 | GTX-GPU, 2x growth layout | txn | 4.20 | 249.88 M | - | |
| snap-roadNet-CA-churn-K1 | GTX-conservative port | txn | 4.21 | 249.09 M | - | |
| snap-roadNet-CA-churn-K1 | 2PL vertex locks | txn | 2.92 | 359.17 M | - | |
| snap-roadNet-CA-churn-K1 | TL2 word-STM | txn | 4.02 | 260.69 M | - | |
| snap-roadNet-CA-churn-K1 | TL2 word-STM (no degree) | txn | 2.56 | 410.26 M | - | |
| snap-roadNet-CA-churn-K1 | non-transactional CAS | txn | 2.41 | 435.00 M | - | |
| snap-roadNet-CA-ins-K1 | GPMA+ (Windows port) | 65536 | 1137.39 | 0.92 M | PASS | 296.5x |
| snap-roadNet-CA-ins-K1 | GPMA+ (upstream, CDP1) | 65536 | 12815.07 | 0.08 M | PASS | 3340.8x |
| snap-roadNet-CA-ins-K1 | GTX-GPU (ours) | txn | 3.84 | 273.36 M | - | |
| snap-roadNet-CA-ins-K1 | GTX-GPU + M4 merge/reuse | txn | 3.89 | 269.69 M | - | |
| snap-roadNet-CA-ins-K1 | GTX-GPU, 2x growth layout | txn | 3.80 | 275.71 M | - | |
| snap-roadNet-CA-ins-K1 | GTX-conservative port | txn | 3.85 | 272.70 M | - | |
| snap-roadNet-CA-ins-K1 | 2PL vertex locks | txn | 2.95 | 355.42 M | - | |
| snap-roadNet-CA-ins-K1 | TL2 word-STM | txn | 4.07 | 257.55 M | - | |
| snap-roadNet-CA-ins-K1 | TL2 word-STM (no degree) | txn | 2.63 | 399.38 M | - | |
| snap-roadNet-CA-ins-K1 | non-transactional CAS | txn | 2.36 | 444.25 M | - | |
| snap-soc-pokec-churn-K1 | GPMA+ (Windows port) | 65536 | 81.07 | 25.87 M | PASS | 9.4x |
| snap-soc-pokec-churn-K1 | GPMA+ (upstream, CDP1) | 65536 | 72.86 | 28.78 M | PASS | 8.5x |
| snap-soc-pokec-churn-K1 | GTX-GPU (ours) | txn | 8.60 | 243.84 M | - | |
| snap-soc-pokec-churn-K1 | GTX-GPU + M4 merge/reuse | txn | 9.26 | 226.47 M | - | |
| snap-soc-pokec-churn-K1 | GTX-GPU, 2x growth layout | txn | 8.66 | 242.17 M | - | |
| snap-soc-pokec-churn-K1 | GTX-conservative port | txn | 8.68 | 241.54 M | - | |
| snap-soc-pokec-churn-K1 | 2PL vertex locks | txn | 6.95 | 301.84 M | - | |
| snap-soc-pokec-churn-K1 | TL2 word-STM | txn | 13.52 | 155.14 M | - | |
| snap-soc-pokec-churn-K1 | TL2 word-STM (no degree) | txn | 4.95 | 423.49 M | - | |
| snap-soc-pokec-churn-K1 | non-transactional CAS | txn | 4.07 | 515.61 M | - | |
| snap-soc-pokec-ins-K1 | GPMA+ (Windows port) | 65536 | 117.21 | 17.89 M | PASS | 15.2x |
| snap-soc-pokec-ins-K1 | GPMA+ (upstream, CDP1) | 65536 | 119.87 | 17.50 M | PASS | 15.5x |
| snap-soc-pokec-ins-K1 | GTX-GPU (ours) | txn | 7.74 | 271.08 M | - | |
| snap-soc-pokec-ins-K1 | GTX-GPU + M4 merge/reuse | txn | 7.82 | 268.24 M | - | |
| snap-soc-pokec-ins-K1 | GTX-GPU, 2x growth layout | txn | 7.69 | 272.63 M | - | |
| snap-soc-pokec-ins-K1 | GTX-conservative port | txn | 7.71 | 272.09 M | - | |
| snap-soc-pokec-ins-K1 | 2PL vertex locks | txn | 7.78 | 269.54 M | - | |
| snap-soc-pokec-ins-K1 | TL2 word-STM | txn | 13.99 | 149.95 M | - | |
| snap-soc-pokec-ins-K1 | TL2 word-STM (no degree) | txn | 5.19 | 403.94 M | - | |
| snap-soc-pokec-ins-K1 | non-transactional CAS | txn | 4.15 | 505.55 M | - | |
| snap-wiki-Talk-churn-K1 | GPMA+ (Windows port) | 65536 | 21.20 | 24.73 M | PASS | 14.3x |
| snap-wiki-Talk-churn-K1 | GPMA+ (upstream, CDP1) | 65536 | 20.83 | 25.17 M | PASS | 14.1x |
| snap-wiki-Talk-churn-K1 | GTX-GPU (ours) | txn | 1.48 | 354.08 M | - | |
| snap-wiki-Talk-churn-K1 | GTX-GPU + M4 merge/reuse | txn | 1.53 | 342.47 M | - | |
| snap-wiki-Talk-churn-K1 | GTX-GPU, 2x growth layout | txn | 1.46 | 360.07 M | - | |
| snap-wiki-Talk-churn-K1 | GTX-conservative port | txn | 1.49 | 351.41 M | - | |
| snap-wiki-Talk-churn-K1 | 2PL vertex locks | txn | 43.83 | 11.96 M | - | |
| snap-wiki-Talk-churn-K1 | TL2 word-STM | txn | 112.20 | 4.54 M | - | |
| snap-wiki-Talk-churn-K1 | TL2 word-STM (no degree) | txn | 1.16 | 451.87 M | - | |
| snap-wiki-Talk-churn-K1 | non-transactional CAS | txn | 0.70 | 749.63 M | - | |
| snap-wiki-Talk-ins-K1 | GPMA+ (Windows port) | 65536 | 186.75 | 2.81 M | PASS | 156.8x |
| snap-wiki-Talk-ins-K1 | GPMA+ (upstream, CDP1) | 65536 | 61.38 | 8.54 M | PASS | 51.5x |
| snap-wiki-Talk-ins-K1 | GTX-GPU (ours) | txn | 1.19 | 440.24 M | - | |
| snap-wiki-Talk-ins-K1 | GTX-GPU + M4 merge/reuse | txn | 1.22 | 429.04 M | - | |
| snap-wiki-Talk-ins-K1 | GTX-GPU, 2x growth layout | txn | 1.20 | 438.67 M | - | |
| snap-wiki-Talk-ins-K1 | GTX-conservative port | txn | 1.20 | 437.98 M | - | |
| snap-wiki-Talk-ins-K1 | 2PL vertex locks | txn | 40.82 | 12.84 M | - | |
| snap-wiki-Talk-ins-K1 | TL2 word-STM | txn | 111.49 | 4.57 M | - | |
| snap-wiki-Talk-ins-K1 | TL2 word-STM (no degree) | txn | 1.20 | 436.86 M | - | |
| snap-wiki-Talk-ins-K1 | non-transactional CAS | txn | 0.70 | 745.27 M | - | |
| sweep-uniform-churn-K1 | GPMA+ (Windows port) | 1024 | 3319.24 | 1.15 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (Windows port) | 4096 | 1050.07 | 3.65 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (Windows port) | 16384 | 292.49 | 13.11 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (Windows port) | 65536 | 123.93 | 30.93 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (Windows port) | 262144 | 103.29 | 37.11 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (Windows port) | 1048576 | 77.06 | 49.75 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (Windows port) | 4194304 | 36.48 | 105.08 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (upstream, CDP1) | 1024 | 3198.71 | 1.20 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (upstream, CDP1) | 4096 | 978.93 | 3.92 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (upstream, CDP1) | 16384 | 297.96 | 12.87 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (upstream, CDP1) | 65536 | 124.42 | 30.81 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (upstream, CDP1) | 262144 | 98.98 | 38.73 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (upstream, CDP1) | 1048576 | 80.51 | 47.61 M | FAIL |  |
| sweep-uniform-churn-K1 | GPMA+ (upstream, CDP1) | 4194304 | 33.39 | 114.82 M | FAIL |  |
| uniform-churn-K1 | GPMA+ (Windows port) | 65536 | 29.05 | 35.06 M | FAIL | 6.6x |
| uniform-churn-K1 | GPMA+ (Windows port) | 524288 | 26.72 | 38.12 M | FAIL | 6.1x |
| uniform-churn-K1 | GPMA+ (upstream, CDP1) | 65536 | 28.60 | 35.61 M | FAIL | 6.5x |
| uniform-churn-K1 | GPMA+ (upstream, CDP1) | 524288 | 25.35 | 40.17 M | FAIL | 5.8x |
| uniform-churn-K1 | GTX-GPU (ours) | txn | 4.40 | 231.51 M | - | |
| uniform-churn-K1 | GTX-GPU + M4 merge/reuse | txn | 4.79 | 212.43 M | - | |
| uniform-churn-K1 | GTX-GPU, 2x growth layout | txn | 4.38 | 232.60 M | - | |
| uniform-churn-K1 | GTX-conservative port | txn | 4.41 | 230.98 M | - | |
| uniform-churn-K1 | 2PL vertex locks | txn | 2.23 | 457.41 M | - | |
| uniform-churn-K1 | TL2 word-STM | txn | 3.85 | 264.61 M | - | |
| uniform-churn-K1 | TL2 word-STM (no degree) | txn | 2.45 | 416.34 M | - | |
| uniform-churn-K1 | non-transactional CAS | txn | 1.95 | 521.61 M | - | |
| uniform-ins-K1 | GPMA+ (Windows port) | 65536 | 46.31 | 22.64 M | PASS | 11.9x |
| uniform-ins-K1 | GPMA+ (Windows port) | 524288 | 34.76 | 30.17 M | PASS | 8.9x |
| uniform-ins-K1 | GPMA+ (upstream, CDP1) | 65536 | 44.41 | 23.61 M | PASS | 11.4x |
| uniform-ins-K1 | GPMA+ (upstream, CDP1) | 524288 | 34.99 | 29.97 M | PASS | 9.0x |
| uniform-ins-K1 | GTX-GPU (ours) | txn | 3.90 | 268.55 M | - | |
| uniform-ins-K1 | GTX-GPU + M4 merge/reuse | txn | 3.99 | 262.63 M | - | |
| uniform-ins-K1 | GTX-GPU, 2x growth layout | txn | 3.91 | 268.27 M | - | |
| uniform-ins-K1 | GTX-conservative port | txn | 3.93 | 267.09 M | - | |
| uniform-ins-K1 | 2PL vertex locks | txn | 2.20 | 475.61 M | - | |
| uniform-ins-K1 | TL2 word-STM | txn | 3.81 | 275.56 M | - | |
| uniform-ins-K1 | TL2 word-STM (no degree) | txn | 2.42 | 433.35 M | - | |
| uniform-ins-K1 | non-transactional CAS | txn | 1.82 | 575.28 M | - | |
