# Benchmark summary (RTX 4060 Laptop, CUDA 12.8; medians over repetitions)

Speedup = GTX-GPU committed-transaction throughput / baseline committed-transaction throughput (>1: GTX-GPU faster; medians over repetitions); 95% bootstrap CI in brackets; '>x' = lower bound for runs that did not finish within the timeout.

## SER-hub50-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.345 | 78.36 M | 163.53 M | 0.026 | 0 | 412 | 198 | - | — |
| GTX-GPU + M4 merge/reuse | 3.745 | 70.00 M | 146.09 M | 0.025 | 0 | 458 | 201 | - | 1.12 [1.11, 1.14] |
| GTX-conservative port | 3.535 | 74.16 M | 154.77 M | 0.034 | 0 | 443 | 211 | - | 1.06 [1.05, 1.07] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >26903 |
| TL2 word-STM | 1307.723 | 0.12 M | 0.22 M | 1.000 | 104877 | 181669 | 236 | - | 651.58 [629.45, 657.64] |
| TL2 word-STM (no degree) | 2.514 | 104.28 M | 217.41 M | 0.072 | 0 | 493 | 271 | - | 0.75 [0.75, 0.76] |

## SER-uniform-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.937 | 66.58 M | 183.33 M | 0.011 | 0 | 248 | 215 | - | — |
| GTX-GPU + M4 merge/reuse | 4.220 | 62.12 M | 171.04 M | 0.010 | 0 | 254 | 221 | - | 1.07 [1.06, 1.08] |
| GTX-conservative port | 3.970 | 66.03 M | 181.80 M | 0.020 | 0 | 403 | 213 | - | 1.01 [1.00, 1.02] |
| 2PL vertex locks | 1.914 | 136.97 M | 376.99 M | 0.000 | 0 | 322 | 353 | - | 0.49 [0.48, 0.49] |
| TL2 word-STM | 6.351 | 41.28 M | 113.58 M | 0.266 | 0 | 1594 | 620 | - | 1.61 [1.61, 1.62] |
| TL2 word-STM (no degree) | 3.149 | 83.25 M | 229.14 M | 0.085 | 0 | 615 | 344 | - | 0.80 [0.80, 0.81] |

## SER-zipf-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.535 | 57.80 M | 156.66 M | 0.012 | 0 | 376 | 259 | - | — |
| GTX-GPU + M4 merge/reuse | 4.823 | 54.35 M | 147.31 M | 0.012 | 0 | 398 | 266 | - | 1.06 [1.04, 1.08] |
| GTX-conservative port | 4.491 | 58.37 M | 158.19 M | 0.023 | 0 | 549 | 253 | - | 0.99 [0.97, 1.00] |
| 2PL vertex locks | 9648.955 | 0.03 M | 0.07 M | 0.000 | 0 | 7136445 | 8295205 | - | 2127.52 [2089.33, 2267.38] |
| TL2 word-STM | 1255.295 | 0.14 M | 0.35 M | 1.000 | 89219 | 301464 | 268 | - | 419.59 [410.62, 429.05] |
| TL2 word-STM (no degree) | 2.914 | 89.95 M | 243.68 M | 0.095 | 0 | 621 | 344 | - | 0.64 [0.63, 0.65] |

## SI-hub50-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.022 | 86.76 M | 180.82 M | 0.015 | 0 | 267 | 173 | - | — |
| GTX-GPU + M4 merge/reuse | 3.388 | 77.37 M | 161.25 M | 0.014 | 0 | 293 | 186 | - | 1.12 [1.11, 1.13] |
| GTX-conservative port | 3.264 | 80.33 M | 167.42 M | 0.022 | 0 | 392 | 190 | - | 1.08 [1.07, 1.09] |

## SI-uniform-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.703 | 70.80 M | 194.87 M | 0.009 | 0 | 223 | 207 | - | — |
| GTX-GPU + M4 merge/reuse | 3.975 | 65.95 M | 181.51 M | 0.008 | 0 | 227 | 209 | - | 1.07 [1.07, 1.09] |
| GTX-conservative port | 3.761 | 69.70 M | 191.84 M | 0.017 | 0 | 353 | 205 | - | 1.02 [1.01, 1.03] |

## SI-zipf-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.871 | 67.72 M | 183.47 M | 0.009 | 0 | 242 | 229 | - | — |
| GTX-GPU + M4 merge/reuse | 4.085 | 64.18 M | 173.86 M | 0.008 | 0 | 244 | 232 | - | 1.06 [1.04, 1.07] |
| GTX-conservative port | 3.882 | 67.53 M | 182.94 M | 0.018 | 0 | 352 | 224 | - | 1.00 [0.99, 1.01] |

## check-SER-hub50

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 38.390 | 1.71 M | 3.12 M | 0.289 | 0 | 19556 | 13352 | PASS | — |
| GTX-GPU + M4 merge/reuse | 34.714 | 1.89 M | 3.45 M | 0.285 | 0 | 19706 | 13796 | PASS | 0.90 [0.90, 0.90] |
| GTX-GPU, 2x growth layout | 31.638 | 2.07 M | 3.79 M | 0.286 | 0 | 20124 | 13698 | PASS | 0.82 [0.82, 0.82] |
| GTX-conservative port | 32.468 | 2.02 M | 3.69 M | 0.315 | 0 | 20450 | 13138 | PASS | 0.85 [0.85, 0.85] |
| 2PL vertex locks | 3379.735 | 0.02 M | 0.03 M | 0.000 | 0 | 3258834 | 3262667 | PASS | 88.04 [88.04, 88.04] |
| TL2 word-STM | 853.211 | 0.05 M | 0.06 M | 1.000 | 24941 | 268885 | 700829 | PASS | 35.88 [35.88, 35.88] |
| TL2 word-STM (no degree) | 448.845 | 0.15 M | 0.27 M | 0.416 | 0 | 636 | 293707 | PASS | 11.69 [11.69, 11.69] |

## check-SER-uniform

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 0.631 | 103.90 M | 244.34 M | 0.109 | 0 | 338 | 100 | PASS | — |
| GTX-GPU + M4 merge/reuse | 0.710 | 92.35 M | 217.23 M | 0.101 | 0 | 342 | 113 | PASS | 1.12 [1.12, 1.12] |
| GTX-GPU, 2x growth layout | 0.656 | 99.85 M | 234.82 M | 0.110 | 0 | 328 | 101 | PASS | 1.04 [1.04, 1.04] |
| GTX-conservative port | 0.704 | 93.06 M | 218.42 M | 0.167 | 0 | 428 | 99 | PASS | 1.12 [1.12, 1.12] |
| 2PL vertex locks | 1.255 | 52.21 M | 121.05 M | 0.000 | 0 | 630 | 620 | PASS | 1.99 [1.99, 1.99] |
| TL2 word-STM | 2.637 | 24.85 M | 57.42 M | 0.754 | 0 | 2315 | 1833 | PASS | 4.18 [4.18, 4.18] |
| TL2 word-STM (no degree) | 0.845 | 77.58 M | 181.24 M | 0.301 | 0 | 623 | 706 | PASS | 1.34 [1.34, 1.34] |

## check-SER-zipf

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.805 | 17.22 M | 39.48 M | 0.122 | 0 | 1754 | 1435 | PASS | — |
| GTX-GPU + M4 merge/reuse | 3.849 | 17.03 M | 39.02 M | 0.118 | 0 | 1846 | 1533 | PASS | 1.01 [1.01, 1.01] |
| GTX-GPU, 2x growth layout | 4.052 | 16.17 M | 37.11 M | 0.123 | 0 | 2117 | 1633 | PASS | 1.06 [1.06, 1.06] |
| GTX-conservative port | 3.902 | 16.79 M | 38.43 M | 0.184 | 0 | 2002 | 1480 | PASS | 1.03 [1.03, 1.03] |
| 2PL vertex locks | 6078.509 | 0.01 M | 0.02 M | 0.000 | 0 | 6070841 | 6016196 | PASS | 1597.42 [1597.42, 1597.42] |
| TL2 word-STM | 413.432 | 0.11 M | 0.21 M | 1.000 | 18939 | 278640 | 379027 | PASS | 152.81 [152.81, 152.81] |
| TL2 word-STM (no degree) | 96.874 | 0.68 M | 1.55 M | 0.396 | 0 | 738 | 46618 | PASS | 25.46 [25.46, 25.46] |

## check-SI-hub50

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 32.982 | 1.99 M | 3.60 M | 0.237 | 0 | 17846 | 13320 | PASS | — |
| GTX-GPU + M4 merge/reuse | 32.967 | 1.99 M | 3.60 M | 0.232 | 0 | 17931 | 13565 | PASS | 1.00 [1.00, 1.00] |
| GTX-GPU, 2x growth layout | 31.237 | 2.10 M | 3.80 M | 0.235 | 0 | 18779 | 13226 | PASS | 0.95 [0.95, 0.95] |
| GTX-conservative port | 32.288 | 2.03 M | 3.68 M | 0.278 | 0 | 19551 | 13913 | PASS | 0.98 [0.98, 0.98] |

## check-SI-uniform

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 0.550 | 119.18 M | 279.06 M | 0.087 | 0 | 242 | 92 | PASS | — |
| GTX-GPU + M4 merge/reuse | 0.623 | 105.26 M | 246.52 M | 0.079 | 0 | 274 | 104 | PASS | 1.13 [1.13, 1.13] |
| GTX-GPU, 2x growth layout | 0.533 | 122.84 M | 287.61 M | 0.086 | 0 | 243 | 91 | PASS | 0.97 [0.97, 0.97] |
| GTX-conservative port | 0.612 | 107.02 M | 250.21 M | 0.144 | 0 | 358 | 89 | PASS | 1.11 [1.11, 1.11] |

## check-SI-zipf

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.441 | 19.04 M | 43.48 M | 0.105 | 0 | 1675 | 1444 | PASS | — |
| GTX-GPU + M4 merge/reuse | 3.772 | 17.37 M | 39.67 M | 0.102 | 0 | 1746 | 1528 | PASS | 1.10 [1.10, 1.10] |
| GTX-GPU, 2x growth layout | 4.053 | 16.17 M | 36.94 M | 0.103 | 0 | 1866 | 1496 | PASS | 1.18 [1.18, 1.18] |
| GTX-conservative port | 3.726 | 17.59 M | 40.12 M | 0.170 | 0 | 1898 | 1532 | PASS | 1.08 [1.08, 1.08] |

## check-batch4096-SER-zipf

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 22.052 | 2.97 M | 6.85 M | 0.046 | 0 | 1231 | 1250 | PASS | — |
| GTX-GPU + M4 merge/reuse | 22.253 | 2.94 M | 6.79 M | 0.045 | 0 | 1247 | 1288 | PASS | 1.01 [1.01, 1.01] |
| GTX-GPU, 2x growth layout | 23.555 | 2.78 M | 6.41 M | 0.049 | 0 | 1329 | 1345 | PASS | 1.07 [1.07, 1.07] |

## check-bulk-SER-hub50

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 31.502 | 2.08 M | 3.80 M | 0.286 | 0 | 19086 | 13067 | PASS | — |
| GTX-GPU + M4 merge/reuse | 36.361 | 1.80 M | 3.30 M | 0.281 | 0 | 19336 | 13684 | PASS | 1.15 [1.15, 1.15] |
| GTX-GPU, 2x growth layout | 29.571 | 2.22 M | 4.06 M | 0.291 | 0 | 19237 | 13107 | PASS | 0.94 [0.94, 0.94] |

## check-bulk-SI-uniform

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 0.592 | 110.73 M | 259.23 M | 0.086 | 0 | 252 | 94 | PASS | — |
| GTX-GPU + M4 merge/reuse | 0.678 | 96.68 M | 226.36 M | 0.077 | 0 | 282 | 105 | PASS | 1.15 [1.15, 1.15] |
| GTX-GPU, 2x growth layout | 0.618 | 106.01 M | 248.21 M | 0.086 | 0 | 250 | 94 | PASS | 1.04 [1.04, 1.04] |

## check-file-roadNet-SER

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 1.068 | 61.37 M | 171.75 M | 0.024 | 0 | 389 | 216 | PASS | — |
| GTX-GPU + M4 merge/reuse | 1.146 | 57.19 M | 160.05 M | 0.023 | 0 | 414 | 226 | PASS | 1.07 [1.07, 1.07] |
| GTX-GPU, 2x growth layout | 1.061 | 61.78 M | 172.87 M | 0.023 | 0 | 378 | 215 | PASS | 0.99 [0.99, 0.99] |
| 2PL vertex locks | 0.861 | 76.10 M | 212.96 M | 0.000 | 0 | 455 | 588 | PASS | 0.81 [0.81, 0.81] |
| TL2 word-STM | 1.998 | 32.80 M | 91.80 M | 0.239 | 0 | 1616 | 1242 | PASS | 1.87 [1.87, 1.87] |

## check-file-wikiTalk-SI

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 12.682 | 5.17 M | 14.49 M | 0.000 | 0 | 5466 | 5745 | PASS | — |
| GTX-GPU + M4 merge/reuse | 13.829 | 4.74 M | 13.29 M | 0.000 | 0 | 5851 | 6034 | PASS | 1.09 [1.09, 1.09] |
| GTX-GPU, 2x growth layout | 13.813 | 4.74 M | 13.31 M | 0.000 | 0 | 5960 | 6119 | PASS | 1.09 [1.09, 1.09] |

## hub50-ins-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 2.962 | 353.97 M | 197.74 M | 0.000 | 0 | 55 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 3.053 | 343.51 M | 191.90 M | 0.000 | 0 | 55 | 0 | - | 1.03 [1.02, 1.04] |
| GTX-GPU, 2x growth layout | 3.700 | 283.42 M | 158.33 M | 0.000 | 0 | 70 | 0 | - | 1.25 [1.25, 1.26] |
| GTX-conservative port | 3.591 | 291.99 M | 163.11 M | 0.001 | 0 | 70 | 0 | - | 1.21 [1.20, 1.22] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >30381 |
| TL2 word-STM | 167.549 | 5.83 M | 3.16 M | 0.997 | 71489 | 117 | 0 | - | 60.70 [60.51, 60.99] |
| TL2 word-STM (no degree) | 1.888 | 555.31 M | 310.22 M | 0.003 | 0 | 102 | 0 | - | 0.64 [0.64, 0.64] |
| non-transactional CAS | 1.561 | 671.92 M | 375.36 M | 0.000 | 0 | 60 | 0 | - | 0.53 [0.52, 0.53] |

## hub50-ins-K2

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 2.869 | 182.73 M | 204.30 M | 0.002 | 0 | 101 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 2.958 | 177.22 M | 198.14 M | 0.002 | 0 | 101 | 0 | - | 1.03 [1.02, 1.05] |
| GTX-GPU, 2x growth layout | 3.622 | 144.76 M | 161.84 M | 0.002 | 0 | 124 | 0 | - | 1.26 [1.25, 1.28] |
| GTX-conservative port | 3.495 | 150.01 M | 167.72 M | 0.004 | 0 | 131 | 0 | - | 1.22 [1.21, 1.23] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >31368 |
| TL2 word-STM | 343.509 | 1.32 M | 1.43 M | 0.998 | 71423 | 281 | 0 | - | 138.60 [137.23, 140.25] |
| TL2 word-STM (no degree) | 1.889 | 277.51 M | 310.25 M | 0.014 | 0 | 176 | 0 | - | 0.66 [0.65, 0.67] |
| non-transactional CAS | 1.411 | 371.55 M | 415.40 M | 0.000 | 0 | 102 | 0 | - | 0.49 [0.49, 0.50] |

## hub50-ins-K32

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.753 | 6.89 M | 123.07 M | 0.226 | 0 | 3940 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 5.009 | 6.54 M | 116.78 M | 0.222 | 0 | 4170 | 0 | - | 1.05 [1.03, 1.09] |
| GTX-GPU, 2x growth layout | 6.079 | 5.39 M | 96.24 M | 0.229 | 0 | 5078 | 0 | - | 1.28 [1.25, 1.37] |
| GTX-conservative port | 6.197 | 5.29 M | 94.39 M | 0.384 | 0 | 5478 | 0 | - | 1.30 [1.28, 1.36] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >18934 |
| TL2 word-STM | 4274.498 | 0.00 M | 0.02 M | 1.000 | 28810 | 4225970 | 0 | - | 7530.61 [7348.74, 7615.13] |
| TL2 word-STM (no degree) | 15.199 | 2.16 M | 38.49 M | 0.879 | 0 | 14300 | 0 | - | 3.20 [3.09, 3.23] |
| non-transactional CAS | 1.384 | 23.67 M | 422.63 M | 0.000 | 0 | 1076 | 0 | - | 0.29 [0.28, 0.29] |

## hub50-ins-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 2.936 | 89.29 M | 199.87 M | 0.006 | 0 | 189 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 3.010 | 87.10 M | 194.98 M | 0.006 | 0 | 189 | 0 | - | 1.03 [1.02, 1.05] |
| GTX-GPU, 2x growth layout | 3.738 | 70.14 M | 157.00 M | 0.006 | 0 | 240 | 0 | - | 1.27 [1.27, 1.30] |
| GTX-conservative port | 3.590 | 73.02 M | 163.45 M | 0.015 | 0 | 322 | 0 | - | 1.22 [1.22, 1.24] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >30656 |
| TL2 word-STM | 644.510 | 0.30 M | 0.66 M | 0.999 | 66735 | 69793 | 0 | - | 294.51 [293.18, 297.84] |
| TL2 word-STM (no degree) | 2.167 | 120.98 M | 270.81 M | 0.056 | 0 | 427 | 0 | - | 0.74 [0.73, 0.75] |
| non-transactional CAS | 1.323 | 198.14 M | 443.53 M | 0.000 | 0 | 176 | 0 | - | 0.45 [0.45, 0.46] |

## hub50-ins-K8

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.139 | 41.76 M | 186.73 M | 0.022 | 0 | 761 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 3.263 | 40.18 M | 179.64 M | 0.021 | 0 | 762 | 0 | - | 1.04 [1.02, 1.05] |
| GTX-GPU, 2x growth layout | 4.074 | 32.18 M | 143.88 M | 0.023 | 0 | 927 | 0 | - | 1.30 [1.26, 1.33] |
| GTX-conservative port | 3.905 | 33.57 M | 150.10 M | 0.054 | 0 | 989 | 0 | - | 1.24 [1.22, 1.27] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >28675 |
| TL2 word-STM | 1382.266 | 0.05 M | 0.23 M | 1.000 | 58420 | 395899 | 0 | - | 794.54 [777.55, 796.16] |
| TL2 word-STM (no degree) | 3.167 | 41.38 M | 185.04 M | 0.208 | 0 | 1388 | 0 | - | 1.01 [0.99, 1.02] |
| non-transactional CAS | 1.367 | 95.88 M | 428.72 M | 0.000 | 0 | 330 | 0 | - | 0.44 [0.43, 0.44] |

## identical-edge-1024-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 13.821 | 18.97 M | 49.55 M | 0.635 | 0 | 11179 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 41.681 | 6.29 M | 16.49 M | 0.653 | 0 | 24551 | 0 | - | 3.02 [2.64, 7.41] |
| GTX-GPU, 2x growth layout | 13.872 | 18.90 M | 49.37 M | 0.635 | 0 | 11263 | 0 | - | 1.00 [0.93, 1.09] |
| GTX-conservative port | 13.457 | 19.48 M | 50.89 M | 0.635 | 0 | 10925 | 0 | - | 0.97 [0.90, 1.05] |
| 2PL vertex locks | 54.665 | 4.80 M | 12.62 M | 0.000 | 0 | 41605 | 0 | - | 3.96 [3.58, 4.31] |
| TL2 word-STM | 134.398 | 1.93 M | 5.18 M | 0.997 | 2859 | 95927 | 0 | - | 9.83 [9.06, 9.97] |
| TL2 word-STM (no degree) | 88.699 | 2.95 M | 8.24 M | 0.996 | 841 | 71043 | 0 | - | 6.44 [5.93, 7.10] |
| non-transactional CAS | 2.413 | 108.66 M | 270.84 M | 0.000 | 0 | 512 | 0 | - | 0.17 [0.16, 0.18] |

## identical-edge-64-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 163.281 | 1.61 M | 4.10 M | 0.900 | 0 | 130811 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 248.794 | 1.05 M | 2.68 M | 0.917 | 0 | 137573 | 0 | - | 1.52 [1.30, 1.67] |
| GTX-GPU, 2x growth layout | 165.596 | 1.58 M | 4.04 M | 0.900 | 0 | 134224 | 0 | - | 1.01 [1.01, 1.02] |
| GTX-conservative port | 157.668 | 1.66 M | 4.24 M | 0.899 | 0 | 127573 | 0 | - | 0.97 [0.96, 0.97] |
| 2PL vertex locks | 1008.784 | 0.26 M | 0.68 M | 0.000 | 0 | 894437 | 0 | - | 6.18 [6.11, 6.32] |
| TL2 word-STM | 692.698 | 0.27 M | 0.69 M | 1.000 | 75010 | 176623 | 0 | - | 5.94 [5.88, 6.02] |
| TL2 word-STM (no degree) | 574.575 | 0.29 M | 0.84 M | 1.000 | 98026 | 120461 | 0 | - | 5.62 [5.55, 5.70] |
| non-transactional CAS | 10.911 | 24.03 M | 57.01 M | 0.000 | 0 | 3119 | 0 | - | 0.07 [0.07, 0.07] |

## rmat-churn-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.990 | 262.77 M | 254.99 M | 0.001 | 0 | 79 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.216 | 248.72 M | 241.37 M | 0.001 | 0 | 81 | 0 | - | 1.06 [1.05, 1.06] |
| GTX-GPU, 2x growth layout | 5.378 | 194.97 M | 189.20 M | 0.001 | 0 | 103 | 0 | - | 1.35 [1.34, 1.36] |
| GTX-conservative port | 3.954 | 265.22 M | 257.37 M | 0.002 | 0 | 80 | 0 | - | 0.99 [0.99, 1.00] |
| 2PL vertex locks | 27.253 | 38.48 M | 37.33 M | 0.000 | 0 | 13111 | 0 | - | 6.83 [6.18, 6.87] |
| TL2 word-STM | 86.500 | 12.03 M | 11.67 M | 0.988 | 7573 | 33804 | 0 | - | 21.83 [21.71, 23.50] |
| TL2 word-STM (no degree) | 2.361 | 444.06 M | 430.93 M | 0.009 | 0 | 147 | 0 | - | 0.59 [0.59, 0.59] |
| non-transactional CAS | 1.574 | 666.23 M | 646.54 M | 0.000 | 0 | 76 | 0 | - | 0.39 [0.39, 0.40] |

## rmat-churn-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.346 | 60.32 M | 234.07 M | 0.019 | 0 | 416 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.549 | 57.63 M | 223.64 M | 0.018 | 0 | 418 | 0 | - | 1.05 [1.04, 1.06] |
| GTX-GPU, 2x growth layout | 5.935 | 44.17 M | 171.39 M | 0.020 | 0 | 557 | 0 | - | 1.37 [1.36, 1.37] |
| GTX-conservative port | 4.355 | 60.20 M | 233.58 M | 0.037 | 0 | 555 | 0 | - | 1.00 [1.00, 1.01] |
| 2PL vertex locks | 2013.952 | 0.13 M | 0.50 M | 0.000 | 0 | 1951907 | 0 | - | 463.41 [442.49, 503.21] |
| TL2 word-STM | 395.649 | 0.63 M | 2.43 M | 0.998 | 13265 | 222618 | 0 | - | 95.89 [95.46, 96.42] |
| TL2 word-STM (no degree) | 3.141 | 83.47 M | 323.92 M | 0.137 | 0 | 718 | 0 | - | 0.72 [0.71, 0.73] |
| non-transactional CAS | 1.327 | 197.53 M | 766.28 M | 0.000 | 0 | 196 | 0 | - | 0.31 [0.30, 0.31] |

## rmat-readers90-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 6.319 | 41.48 M | 16.52 M | 0.000 | 0 | 737 | 736 | - | — |
| GTX-GPU + M4 merge/reuse | 6.103 | 42.95 M | 17.10 M | 0.000 | 0 | 697 | 691 | - | 0.97 [0.95, 1.03] |
| GTX-GPU, 2x growth layout | 7.585 | 34.56 M | 13.76 M | 0.000 | 0 | 770 | 759 | - | 1.20 [1.18, 1.26] |
| GTX-conservative port | 6.038 | 43.41 M | 17.28 M | 0.001 | 0 | 694 | 685 | - | 0.96 [0.93, 1.05] |
| 2PL vertex locks | 125.474 | 2.09 M | 0.83 M | 0.000 | 0 | 117832 | 105995 | - | 19.86 [18.05, 23.86] |
| TL2 word-STM | 159.631 | 1.64 M | 0.65 M | 0.868 | 0 | 67106 | 78522 | - | 25.26 [24.23, 27.49] |
| TL2 word-STM (no degree) | 103.950 | 2.52 M | 1.00 M | 0.442 | 0 | 849 | 34139 | - | 16.45 [15.55, 17.41] |
| non-transactional CAS | 12.766 | 20.53 M | 8.18 M | 0.000 | 0 | 1203 | 5804 | - | 2.02 [1.81, 2.24] |

## rmat-readers90-K4-roCoop

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 5.969 | 43.92 M | 17.49 M | 0.000 | 0 | 685 | 685 | - | — |
| GTX-GPU + M4 merge/reuse | 6.210 | 42.22 M | 16.81 M | 0.000 | 0 | 709 | 697 | - | 1.04 [0.95, 1.05] |
| GTX-GPU, 2x growth layout | 7.647 | 34.28 M | 13.65 M | 0.000 | 0 | 768 | 753 | - | 1.28 [1.18, 1.29] |
| GTX-conservative port | 5.943 | 44.11 M | 17.56 M | 0.000 | 0 | 702 | 693 | - | 1.00 [0.91, 1.00] |
| 2PL vertex locks | 129.397 | 2.03 M | 0.81 M | 0.655 | 0 | 79191 | 24490 | - | 21.68 [19.89, 22.10] |
| TL2 word-STM | 130.179 | 2.01 M | 0.80 M | 0.327 | 0 | 2061 | 121823 | - | 21.81 [20.01, 22.25] |
| TL2 word-STM (no degree) | 89.671 | 2.92 M | 1.16 M | 0.191 | 0 | 322 | 83020 | - | 15.02 [13.78, 16.14] |
| non-transactional CAS | 2.560 | 102.40 M | 40.77 M | 0.000 | 0 | 67 | 632 | - | 0.43 [0.39, 0.43] |

## snap-cit-Patents-SER-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 8.346 | 62.82 M | 175.94 M | 0.004 | 0 | 238 | 234 | - | — |
| 2PL vertex locks | 6.293 | 83.31 M | 233.31 M | 0.000 | 0 | 671 | 651 | - | 0.75 [0.71, 0.77] |
| TL2 word-STM | 14.376 | 36.47 M | 102.14 M | 0.320 | 0 | 2021 | 537 | - | 1.72 [1.63, 1.76] |
| TL2 word-STM (no degree) | 7.272 | 72.09 M | 201.90 M | 0.066 | 0 | 732 | 395 | - | 0.87 [0.79, 0.88] |

## snap-cit-Patents-churn-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 9.150 | 229.19 M | 229.19 M | 0.000 | 0 | 72 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 9.760 | 214.88 M | 214.88 M | 0.000 | 0 | 75 | 0 | - | 1.07 [1.06, 1.15] |
| GTX-GPU, 2x growth layout | 9.054 | 231.62 M | 231.62 M | 0.000 | 0 | 70 | 0 | - | 0.99 [0.99, 1.12] |
| GTX-conservative port | 9.194 | 228.11 M | 228.11 M | 0.000 | 0 | 72 | 0 | - | 1.00 [0.99, 1.10] |
| 2PL vertex locks | 5.995 | 349.85 M | 349.85 M | 0.000 | 0 | 127 | 0 | - | 0.66 [0.65, 0.66] |
| TL2 word-STM | 8.472 | 247.55 M | 247.55 M | 0.034 | 0 | 257 | 0 | - | 0.93 [0.92, 0.94] |
| TL2 word-STM (no degree) | 5.264 | 398.37 M | 398.37 M | 0.005 | 0 | 153 | 0 | - | 0.58 [0.57, 0.58] |
| non-transactional CAS | 4.938 | 424.72 M | 424.72 M | 0.000 | 0 | 91 | 0 | - | 0.54 [0.54, 0.54] |

## snap-cit-Patents-churn-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 9.779 | 53.61 M | 214.45 M | 0.000 | 0 | 271 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 10.607 | 49.43 M | 197.72 M | 0.000 | 0 | 287 | 0 | - | 1.08 [1.02, 1.09] |
| GTX-GPU, 2x growth layout | 9.758 | 53.73 M | 214.92 M | 0.000 | 0 | 271 | 0 | - | 1.00 [0.94, 1.07] |
| GTX-conservative port | 9.886 | 53.04 M | 212.14 M | 0.007 | 0 | 281 | 0 | - | 1.01 [0.95, 1.05] |
| 2PL vertex locks | 7.119 | 73.65 M | 294.59 M | 0.000 | 0 | 1185 | 0 | - | 0.73 [0.68, 0.74] |
| TL2 word-STM | 19.669 | 26.66 M | 106.62 M | 0.521 | 0 | 3528 | 0 | - | 2.01 [1.89, 2.07] |
| TL2 word-STM (no degree) | 6.984 | 75.07 M | 300.29 M | 0.083 | 0 | 777 | 0 | - | 0.71 [0.67, 0.73] |
| non-transactional CAS | 4.325 | 121.21 M | 484.85 M | 0.000 | 0 | 280 | 0 | - | 0.44 [0.41, 0.45] |

## snap-cit-Patents-ins-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 8.222 | 255.08 M | 255.08 M | 0.000 | 0 | 66 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 8.346 | 251.29 M | 251.29 M | 0.000 | 0 | 66 | 0 | - | 1.02 [0.95, 1.08] |
| GTX-GPU, 2x growth layout | 8.218 | 255.20 M | 255.20 M | 0.000 | 0 | 66 | 0 | - | 1.00 [0.93, 1.01] |
| GTX-conservative port | 8.233 | 254.73 M | 254.73 M | 0.001 | 0 | 66 | 0 | - | 1.00 [0.93, 1.01] |
| 2PL vertex locks | 6.180 | 339.35 M | 339.35 M | 0.000 | 0 | 130 | 0 | - | 0.75 [0.70, 0.76] |
| TL2 word-STM | 8.859 | 236.74 M | 236.74 M | 0.035 | 0 | 255 | 0 | - | 1.08 [1.00, 1.09] |
| TL2 word-STM (no degree) | 5.472 | 383.23 M | 383.23 M | 0.006 | 0 | 156 | 0 | - | 0.67 [0.62, 0.67] |
| non-transactional CAS | 4.990 | 420.27 M | 420.27 M | 0.000 | 0 | 93 | 0 | - | 0.61 [0.57, 0.61] |

## snap-cit-Patents-readers90-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.532 | 115.68 M | 46.23 M | 0.000 | 0 | 154 | 152 | - | — |
| GTX-GPU + M4 merge/reuse | 4.810 | 109.01 M | 43.56 M | 0.000 | 0 | 163 | 157 | - | 1.06 [1.04, 1.07] |
| GTX-GPU, 2x growth layout | 4.543 | 115.42 M | 46.12 M | 0.000 | 0 | 155 | 151 | - | 1.00 [0.98, 1.02] |
| GTX-conservative port | 4.529 | 115.76 M | 46.26 M | 0.000 | 0 | 154 | 151 | - | 1.00 [0.98, 1.00] |
| 2PL vertex locks | 5.070 | 103.41 M | 41.32 M | 0.000 | 0 | 1375 | 586 | - | 1.12 [0.99, 1.14] |
| TL2 word-STM | 10.937 | 47.94 M | 19.15 M | 0.177 | 0 | 2016 | 3045 | - | 2.41 [2.37, 2.49] |
| TL2 word-STM (no degree) | 8.652 | 60.60 M | 24.22 M | 0.076 | 0 | 1036 | 1893 | - | 1.91 [1.88, 1.98] |
| non-transactional CAS | 3.202 | 163.74 M | 65.43 M | 0.000 | 0 | 337 | 509 | - | 0.71 [0.69, 0.71] |

## snap-roadNet-CA-SER-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.787 | 69.23 M | 193.86 M | 0.012 | 0 | 295 | 209 | - | — |
| 2PL vertex locks | 2.789 | 93.98 M | 263.17 M | 0.000 | 0 | 420 | 463 | - | 0.74 [0.73, 0.75] |
| TL2 word-STM | 6.071 | 43.18 M | 120.91 M | 0.198 | 0 | 1403 | 516 | - | 1.60 [1.60, 1.61] |
| TL2 word-STM (no degree) | 3.110 | 84.29 M | 236.05 M | 0.067 | 0 | 595 | 336 | - | 0.82 [0.82, 0.82] |

## snap-roadNet-CA-churn-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.205 | 249.39 M | 249.39 M | 0.000 | 0 | 66 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.637 | 226.15 M | 226.15 M | 0.000 | 0 | 70 | 0 | - | 1.10 [1.09, 1.11] |
| GTX-GPU, 2x growth layout | 4.196 | 249.88 M | 249.88 M | 0.000 | 0 | 66 | 0 | - | 1.00 [0.99, 1.01] |
| GTX-conservative port | 4.210 | 249.09 M | 249.09 M | 0.001 | 0 | 67 | 0 | - | 1.00 [0.99, 1.01] |
| 2PL vertex locks | 2.919 | 359.17 M | 359.17 M | 0.000 | 0 | 102 | 0 | - | 0.69 [0.69, 0.70] |
| TL2 word-STM | 4.022 | 260.69 M | 260.69 M | 0.020 | 0 | 210 | 0 | - | 0.96 [0.95, 1.09] |
| TL2 word-STM (no degree) | 2.556 | 410.26 M | 410.26 M | 0.005 | 0 | 121 | 0 | - | 0.61 [0.60, 0.61] |
| non-transactional CAS | 2.410 | 435.00 M | 435.00 M | 0.000 | 0 | 78 | 0 | - | 0.57 [0.57, 0.58] |

## snap-roadNet-CA-churn-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.319 | 60.69 M | 242.77 M | 0.000 | 0 | 231 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.767 | 54.99 M | 219.98 M | 0.000 | 0 | 251 | 0 | - | 1.10 [1.09, 1.11] |
| GTX-GPU, 2x growth layout | 4.355 | 60.19 M | 240.77 M | 0.000 | 0 | 234 | 0 | - | 1.01 [1.00, 1.01] |
| GTX-conservative port | 4.410 | 59.44 M | 237.75 M | 0.010 | 0 | 250 | 0 | - | 1.02 [1.00, 1.16] |
| 2PL vertex locks | 3.021 | 86.78 M | 347.12 M | 0.000 | 0 | 482 | 0 | - | 0.70 [0.69, 0.70] |
| TL2 word-STM | 7.434 | 35.26 M | 141.05 M | 0.291 | 0 | 1983 | 0 | - | 1.72 [1.70, 1.92] |
| TL2 word-STM (no degree) | 3.263 | 80.35 M | 321.41 M | 0.076 | 0 | 706 | 0 | - | 0.76 [0.75, 0.76] |
| non-transactional CAS | 2.121 | 123.61 M | 494.45 M | 0.000 | 0 | 251 | 0 | - | 0.49 [0.49, 0.49] |

## snap-roadNet-CA-ins-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.836 | 273.36 M | 273.36 M | 0.000 | 0 | 63 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 3.888 | 269.69 M | 269.69 M | 0.000 | 0 | 60 | 0 | - | 1.01 [0.90, 1.02] |
| GTX-GPU, 2x growth layout | 3.803 | 275.71 M | 275.71 M | 0.000 | 0 | 60 | 0 | - | 0.99 [0.88, 1.00] |
| GTX-conservative port | 3.845 | 272.70 M | 272.70 M | 0.001 | 0 | 63 | 0 | - | 1.00 [0.88, 1.01] |
| 2PL vertex locks | 2.950 | 355.42 M | 355.42 M | 0.000 | 0 | 108 | 0 | - | 0.77 [0.68, 0.77] |
| TL2 word-STM | 4.071 | 257.55 M | 257.55 M | 0.020 | 0 | 208 | 0 | - | 1.06 [0.94, 1.20] |
| TL2 word-STM (no degree) | 2.626 | 399.38 M | 399.38 M | 0.005 | 0 | 125 | 0 | - | 0.68 [0.60, 0.69] |
| non-transactional CAS | 2.360 | 444.25 M | 444.25 M | 0.000 | 0 | 79 | 0 | - | 0.62 [0.54, 0.69] |

## snap-roadNet-CA-readers90-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 2.156 | 121.56 M | 47.91 M | 0.000 | 0 | 154 | 151 | - | — |
| GTX-GPU + M4 merge/reuse | 2.303 | 113.83 M | 44.87 M | 0.000 | 0 | 161 | 155 | - | 1.07 [1.05, 1.08] |
| GTX-GPU, 2x growth layout | 2.178 | 120.36 M | 47.44 M | 0.000 | 0 | 151 | 148 | - | 1.01 [0.99, 1.02] |
| GTX-conservative port | 2.193 | 119.51 M | 47.11 M | 0.000 | 0 | 155 | 151 | - | 1.02 [1.00, 1.03] |
| 2PL vertex locks | 1.812 | 144.71 M | 57.04 M | 0.000 | 0 | 325 | 260 | - | 0.84 [0.82, 0.85] |
| TL2 word-STM | 2.986 | 87.79 M | 34.60 M | 0.074 | 0 | 1571 | 514 | - | 1.38 [1.36, 1.57] |
| TL2 word-STM (no degree) | 2.290 | 114.49 M | 45.13 M | 0.025 | 0 | 803 | 333 | - | 1.06 [1.04, 1.07] |
| non-transactional CAS | 1.537 | 170.55 M | 67.22 M | 0.000 | 0 | 312 | 210 | - | 0.71 [0.70, 0.72] |

## snap-soc-pokec-SER-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 7.995 | 65.57 M | 183.60 M | 0.002 | 0 | 227 | 225 | - | — |
| 2PL vertex locks | 8.850 | 59.24 M | 165.86 M | 0.000 | 0 | 1481 | 1895 | - | 1.11 [1.05, 1.42] |
| TL2 word-STM | 26.142 | 20.06 M | 56.15 M | 0.619 | 0 | 3211 | 517 | - | 3.27 [3.23, 3.56] |
| TL2 word-STM (no degree) | 6.230 | 84.16 M | 235.62 M | 0.066 | 0 | 644 | 354 | - | 0.78 [0.77, 0.80] |

## snap-soc-pokec-churn-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 8.601 | 243.84 M | 243.84 M | 0.000 | 0 | 69 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 9.260 | 226.47 M | 226.47 M | 0.000 | 0 | 73 | 0 | - | 1.08 [1.07, 1.08] |
| GTX-GPU, 2x growth layout | 8.660 | 242.17 M | 242.17 M | 0.000 | 0 | 69 | 0 | - | 1.01 [0.99, 1.01] |
| GTX-conservative port | 8.682 | 241.54 M | 241.54 M | 0.000 | 0 | 69 | 0 | - | 1.01 [1.00, 1.01] |
| 2PL vertex locks | 6.948 | 301.84 M | 301.84 M | 0.000 | 0 | 112 | 0 | - | 0.81 [0.80, 0.82] |
| TL2 word-STM | 13.518 | 155.14 M | 155.14 M | 0.219 | 0 | 267 | 0 | - | 1.57 [1.55, 1.64] |
| TL2 word-STM (no degree) | 4.952 | 423.49 M | 423.49 M | 0.006 | 0 | 158 | 0 | - | 0.58 [0.57, 0.58] |
| non-transactional CAS | 4.067 | 515.61 M | 515.61 M | 0.000 | 0 | 85 | 0 | - | 0.47 [0.47, 0.47] |

## snap-soc-pokec-churn-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 9.304 | 56.35 M | 225.40 M | 0.000 | 0 | 259 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 10.015 | 52.35 M | 209.41 M | 0.000 | 0 | 274 | 0 | - | 1.08 [1.07, 1.08] |
| GTX-GPU, 2x growth layout | 9.364 | 55.99 M | 223.97 M | 0.000 | 0 | 261 | 0 | - | 1.01 [0.99, 1.30] |
| GTX-conservative port | 9.403 | 55.76 M | 223.02 M | 0.005 | 0 | 264 | 0 | - | 1.01 [1.00, 1.05] |
| 2PL vertex locks | 9.426 | 55.62 M | 222.49 M | 0.000 | 0 | 1874 | 0 | - | 1.01 [0.98, 1.40] |
| TL2 word-STM | 44.468 | 11.79 M | 47.16 M | 0.824 | 0 | 7357 | 0 | - | 4.78 [4.74, 4.88] |
| TL2 word-STM (no degree) | 6.800 | 77.10 M | 308.39 M | 0.088 | 0 | 784 | 0 | - | 0.73 [0.73, 0.74] |
| non-transactional CAS | 3.447 | 152.11 M | 608.44 M | 0.000 | 0 | 247 | 0 | - | 0.37 [0.37, 0.37] |

## snap-soc-pokec-ins-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 7.736 | 271.08 M | 271.08 M | 0.000 | 0 | 63 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 7.818 | 268.24 M | 268.24 M | 0.000 | 0 | 63 | 0 | - | 1.01 [1.00, 1.02] |
| GTX-GPU, 2x growth layout | 7.692 | 272.63 M | 272.63 M | 0.000 | 0 | 63 | 0 | - | 0.99 [0.99, 1.00] |
| GTX-conservative port | 7.708 | 272.09 M | 272.09 M | 0.000 | 0 | 63 | 0 | - | 1.00 [0.99, 1.00] |
| 2PL vertex locks | 7.780 | 269.54 M | 269.54 M | 0.000 | 0 | 128 | 0 | - | 1.01 [0.92, 1.02] |
| TL2 word-STM | 13.986 | 149.95 M | 149.95 M | 0.220 | 0 | 268 | 0 | - | 1.81 [1.78, 1.88] |
| TL2 word-STM (no degree) | 5.192 | 403.94 M | 403.94 M | 0.007 | 0 | 160 | 0 | - | 0.67 [0.67, 0.68] |
| non-transactional CAS | 4.148 | 505.55 M | 505.55 M | 0.000 | 0 | 89 | 0 | - | 0.54 [0.53, 0.54] |

## snap-soc-pokec-readers90-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 5.161 | 101.59 M | 41.04 M | 0.000 | 0 | 238 | 242 | - | — |
| GTX-GPU + M4 merge/reuse | 5.343 | 98.12 M | 39.64 M | 0.000 | 0 | 241 | 245 | - | 1.04 [1.02, 1.04] |
| GTX-GPU, 2x growth layout | 5.125 | 102.30 M | 41.32 M | 0.000 | 0 | 238 | 242 | - | 0.99 [0.97, 1.00] |
| GTX-conservative port | 5.121 | 102.38 M | 41.36 M | 0.000 | 0 | 246 | 251 | - | 0.99 [0.97, 1.00] |
| 2PL vertex locks | 6.142 | 85.36 M | 34.48 M | 0.000 | 0 | 2756 | 785 | - | 1.19 [1.17, 1.35] |
| TL2 word-STM | 35.110 | 14.93 M | 6.03 M | 0.357 | 0 | 1934 | 12331 | - | 6.80 [6.54, 7.36] |
| TL2 word-STM (no degree) | 27.812 | 18.85 M | 7.62 M | 0.190 | 0 | 1087 | 8880 | - | 5.39 [4.72, 5.74] |
| non-transactional CAS | 5.657 | 92.69 M | 37.44 M | 0.000 | 0 | 522 | 1107 | - | 1.10 [1.08, 1.20] |

## snap-wiki-Talk-SER-rw-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 1.271 | 103.14 M | 288.75 M | 0.014 | 0 | 203 | 129 | - | — |
| 2PL vertex locks | 677.834 | 0.19 M | 0.54 M | 0.000 | 0 | 665650 | 653769 | - | 533.39 [526.10, 561.30] |
| TL2 word-STM | 337.768 | 0.34 M | 0.94 M | 0.999 | 15145 | 221386 | 237 | - | 300.52 [286.24, 305.76] |
| TL2 word-STM (no degree) | 1.339 | 97.88 M | 274.01 M | 0.093 | 0 | 531 | 274 | - | 1.05 [1.03, 1.07] |

## snap-wiki-Talk-churn-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 1.481 | 354.08 M | 354.08 M | 0.000 | 0 | 61 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 1.531 | 342.47 M | 342.47 M | 0.000 | 0 | 63 | 0 | - | 1.03 [1.02, 1.04] |
| GTX-GPU, 2x growth layout | 1.456 | 360.07 M | 360.07 M | 0.000 | 0 | 61 | 0 | - | 0.98 [0.97, 0.99] |
| GTX-conservative port | 1.492 | 351.41 M | 351.41 M | 0.002 | 0 | 62 | 0 | - | 1.01 [1.00, 1.02] |
| 2PL vertex locks | 43.830 | 11.96 M | 11.96 M | 0.000 | 0 | 27778 | 0 | - | 29.60 [29.09, 32.20] |
| TL2 word-STM | 112.203 | 4.54 M | 4.54 M | 0.996 | 14784 | 41601 | 0 | - | 77.98 [77.02, 78.54] |
| TL2 word-STM (no degree) | 1.160 | 451.87 M | 451.87 M | 0.008 | 0 | 142 | 0 | - | 0.78 [0.77, 0.79] |
| non-transactional CAS | 0.699 | 749.63 M | 749.63 M | 0.000 | 0 | 59 | 0 | - | 0.47 [0.47, 0.47] |

## snap-wiki-Talk-churn-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 1.339 | 97.86 M | 391.44 M | 0.000 | 0 | 146 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 1.453 | 90.20 M | 360.82 M | 0.000 | 0 | 155 | 0 | - | 1.08 [1.06, 1.10] |
| GTX-GPU, 2x growth layout | 1.336 | 98.10 M | 392.40 M | 0.000 | 0 | 145 | 0 | - | 1.00 [0.99, 1.01] |
| GTX-conservative port | 1.429 | 91.76 M | 367.03 M | 0.030 | 0 | 341 | 0 | - | 1.07 [1.06, 1.07] |
| 2PL vertex locks | 1477.073 | 0.09 M | 0.35 M | 0.000 | 0 | 1460460 | 0 | - | 1102.79 [1084.18, 1131.10] |
| TL2 word-STM | 413.421 | 0.25 M | 0.99 M | 0.999 | 28767 | 193531 | 0 | - | 395.45 [386.58, 398.97] |
| TL2 word-STM (no degree) | 1.365 | 96.04 M | 384.17 M | 0.108 | 0 | 598 | 0 | - | 1.02 [1.01, 1.02] |
| non-transactional CAS | 0.617 | 212.36 M | 849.44 M | 0.000 | 0 | 175 | 0 | - | 0.46 [0.46, 0.47] |

## snap-wiki-Talk-ins-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 1.191 | 440.24 M | 440.24 M | 0.000 | 0 | 51 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 1.222 | 429.04 M | 429.04 M | 0.000 | 0 | 52 | 0 | - | 1.03 [1.02, 1.03] |
| GTX-GPU, 2x growth layout | 1.195 | 438.67 M | 438.67 M | 0.000 | 0 | 52 | 0 | - | 1.00 [0.99, 1.02] |
| GTX-conservative port | 1.197 | 437.98 M | 437.98 M | 0.002 | 0 | 53 | 0 | - | 1.01 [1.00, 1.02] |
| 2PL vertex locks | 40.817 | 12.84 M | 12.84 M | 0.000 | 0 | 25231 | 0 | - | 34.27 [33.97, 34.45] |
| TL2 word-STM | 111.492 | 4.57 M | 4.57 M | 0.996 | 14691 | 41657 | 0 | - | 96.32 [95.45, 96.81] |
| TL2 word-STM (no degree) | 1.200 | 436.86 M | 436.86 M | 0.011 | 0 | 146 | 0 | - | 1.01 [1.00, 1.01] |
| non-transactional CAS | 0.704 | 745.27 M | 745.27 M | 0.000 | 0 | 60 | 0 | - | 0.59 [0.59, 0.60] |

## snap-wiki-Talk-readers90-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 17.974 | 7.29 M | 2.89 M | 0.000 | 0 | 5233 | 5228 | - | — |
| GTX-GPU + M4 merge/reuse | 18.132 | 7.23 M | 2.86 M | 0.000 | 0 | 5274 | 5278 | - | 1.01 [1.00, 1.03] |
| GTX-GPU, 2x growth layout | 17.914 | 7.32 M | 2.90 M | 0.000 | 0 | 5238 | 5252 | - | 1.00 [0.99, 1.01] |
| GTX-conservative port | 17.887 | 7.33 M | 2.90 M | 0.000 | 0 | 5263 | 5241 | - | 1.00 [0.99, 1.02] |
| 2PL vertex locks | 3521.022 | 0.04 M | 0.01 M | 0.000 | 0 | 3507545 | 3423939 | - | 195.89 [158.74, 203.56] |
| TL2 word-STM | 541.116 | 0.24 M | 0.09 M | 0.970 | 135 | 214791 | 286990 | - | 30.14 [29.33, 33.89] |
| TL2 word-STM (no degree) | 370.289 | 0.35 M | 0.14 M | 0.600 | 0 | 811 | 115610 | - | 20.60 [19.81, 20.96] |
| non-transactional CAS | 37.557 | 3.49 M | 1.38 M | 0.000 | 0 | 2719 | 16303 | - | 2.09 [2.06, 2.13] |

## sweep-uniform-churn-K1-b10

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 224.868 | 18.65 M | 17.05 M | 0.000 | 0 | 25 | 0 | - | — |

## sweep-uniform-churn-K1-b12

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 59.479 | 70.52 M | 64.44 M | 0.000 | 0 | 29 | 0 | - | — |

## sweep-uniform-churn-K1-b14

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 27.913 | 150.27 M | 137.31 M | 0.001 | 0 | 63 | 0 | - | — |

## sweep-uniform-churn-K1-b16

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 20.902 | 200.66 M | 183.36 M | 0.001 | 0 | 74 | 0 | - | — |

## sweep-uniform-churn-K1-b18

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 19.034 | 220.36 M | 201.37 M | 0.001 | 0 | 71 | 0 | - | — |

## sweep-uniform-churn-K1-b20

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 18.528 | 226.38 M | 206.87 M | 0.001 | 0 | 69 | 0 | - | — |

## sweep-uniform-churn-K1-b22

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 18.410 | 227.83 M | 208.20 M | 0.001 | 0 | 69 | 0 | - | — |

## uniform-churn-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.398 | 238.42 M | 231.51 M | 0.001 | 0 | 73 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.793 | 218.76 M | 212.43 M | 0.001 | 0 | 78 | 0 | - | 1.09 [1.08, 1.09] |
| GTX-GPU, 2x growth layout | 4.378 | 239.53 M | 232.60 M | 0.001 | 0 | 73 | 0 | - | 1.00 [0.99, 1.00] |
| GTX-conservative port | 4.408 | 237.86 M | 230.98 M | 0.002 | 0 | 74 | 0 | - | 1.00 [1.00, 1.00] |
| 2PL vertex locks | 2.226 | 471.02 M | 457.41 M | 0.000 | 0 | 99 | 0 | - | 0.51 [0.50, 0.51] |
| TL2 word-STM | 3.847 | 272.56 M | 264.61 M | 0.029 | 0 | 218 | 0 | - | 0.87 [0.87, 0.98] |
| TL2 word-STM (no degree) | 2.445 | 428.81 M | 416.34 M | 0.007 | 0 | 132 | 0 | - | 0.56 [0.55, 0.56] |
| non-transactional CAS | 1.952 | 537.25 M | 521.61 M | 0.000 | 0 | 78 | 0 | - | 0.44 [0.44, 0.44] |

## uniform-churn-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.734 | 55.38 M | 214.95 M | 0.020 | 0 | 479 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 5.186 | 50.55 M | 196.23 M | 0.018 | 0 | 487 | 0 | - | 1.10 [1.09, 1.10] |
| GTX-GPU, 2x growth layout | 4.715 | 55.59 M | 215.80 M | 0.020 | 0 | 468 | 0 | - | 1.00 [0.99, 1.01] |
| GTX-conservative port | 4.826 | 54.32 M | 210.84 M | 0.035 | 0 | 622 | 0 | - | 1.02 [1.01, 1.04] |
| 2PL vertex locks | 2.068 | 126.73 M | 491.94 M | 0.000 | 0 | 360 | 0 | - | 0.44 [0.43, 0.44] |
| TL2 word-STM | 7.917 | 33.11 M | 128.48 M | 0.395 | 0 | 2205 | 0 | - | 1.67 [1.66, 1.68] |
| TL2 word-STM (no degree) | 3.334 | 78.62 M | 305.21 M | 0.116 | 0 | 718 | 0 | - | 0.70 [0.70, 0.71] |
| non-transactional CAS | 1.568 | 167.21 M | 648.79 M | 0.000 | 0 | 233 | 0 | - | 0.33 [0.33, 0.33] |

## uniform-delete-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 5.277 | 49.68 M | 174.84 M | 0.042 | 0 | 684 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 6.100 | 42.97 M | 151.24 M | 0.038 | 0 | 777 | 0 | - | 1.16 [1.15, 1.16] |
| GTX-GPU, 2x growth layout | 5.241 | 50.02 M | 176.03 M | 0.042 | 0 | 679 | 0 | - | 0.99 [0.98, 1.01] |
| GTX-conservative port | 5.318 | 49.30 M | 173.49 M | 0.052 | 0 | 691 | 0 | - | 1.01 [1.00, 1.01] |
| 2PL vertex locks | 1.970 | 133.06 M | 468.26 M | 0.000 | 0 | 357 | 0 | - | 0.37 [0.36, 0.38] |
| TL2 word-STM | 6.708 | 39.08 M | 137.53 M | 0.390 | 0 | 1881 | 0 | - | 1.27 [1.27, 1.28] |
| TL2 word-STM (no degree) | 3.043 | 86.14 M | 303.14 M | 0.131 | 0 | 701 | 0 | - | 0.58 [0.57, 0.58] |
| non-transactional CAS | 1.450 | 180.78 M | 636.22 M | 0.000 | 0 | 207 | 0 | - | 0.27 [0.27, 0.29] |

## uniform-ins-K1

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.905 | 268.55 M | 268.55 M | 0.000 | 0 | 67 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 3.993 | 262.63 M | 262.63 M | 0.000 | 0 | 68 | 0 | - | 1.02 [1.02, 1.03] |
| GTX-GPU, 2x growth layout | 3.909 | 268.27 M | 268.27 M | 0.000 | 0 | 67 | 0 | - | 1.00 [1.00, 1.01] |
| GTX-conservative port | 3.926 | 267.09 M | 267.09 M | 0.001 | 0 | 67 | 0 | - | 1.01 [1.00, 1.01] |
| 2PL vertex locks | 2.205 | 475.62 M | 475.61 M | 0.000 | 0 | 98 | 0 | - | 0.56 [0.56, 0.57] |
| TL2 word-STM | 3.805 | 275.57 M | 275.56 M | 0.029 | 0 | 209 | 0 | - | 0.97 [0.97, 1.10] |
| TL2 word-STM (no degree) | 2.420 | 433.35 M | 433.35 M | 0.006 | 0 | 124 | 0 | - | 0.62 [0.62, 0.70] |
| non-transactional CAS | 1.823 | 575.28 M | 575.28 M | 0.000 | 0 | 74 | 0 | - | 0.47 [0.46, 0.47] |

## uniform-ins-K2

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.873 | 135.38 M | 270.77 M | 0.000 | 0 | 126 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 3.943 | 132.95 M | 265.90 M | 0.000 | 0 | 125 | 0 | - | 1.02 [1.01, 1.02] |
| GTX-GPU, 2x growth layout | 3.851 | 136.14 M | 272.29 M | 0.000 | 0 | 128 | 0 | - | 0.99 [0.99, 1.00] |
| GTX-conservative port | 3.917 | 133.86 M | 267.72 M | 0.005 | 0 | 134 | 0 | - | 1.01 [1.01, 1.02] |
| 2PL vertex locks | 1.988 | 263.78 M | 527.56 M | 0.000 | 0 | 172 | 0 | - | 0.51 [0.51, 0.52] |
| TL2 word-STM | 4.498 | 116.55 M | 233.10 M | 0.121 | 0 | 567 | 0 | - | 1.16 [1.16, 1.17] |
| TL2 word-STM (no degree) | 2.506 | 209.24 M | 418.47 M | 0.027 | 0 | 258 | 0 | - | 0.65 [0.64, 0.65] |
| non-transactional CAS | 1.607 | 326.32 M | 652.64 M | 0.000 | 0 | 129 | 0 | - | 0.41 [0.41, 0.42] |

## uniform-ins-K32

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.681 | 7.00 M | 223.98 M | 0.000 | 0 | 1989 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.767 | 6.87 M | 219.98 M | 0.000 | 0 | 1994 | 0 | - | 1.02 [1.01, 1.02] |
| GTX-GPU, 2x growth layout | 4.692 | 6.98 M | 223.48 M | 0.000 | 0 | 1971 | 0 | - | 1.00 [1.00, 1.01] |
| GTX-conservative port | 7.797 | 4.20 M | 134.49 M | 0.416 | 0 | 6942 | 0 | - | 1.67 [1.65, 1.70] |
| 2PL vertex locks | 4.973 | 6.59 M | 210.87 M | 0.000 | 0 | 4390 | 0 | - | 1.06 [1.05, 1.09] |
| TL2 word-STM | 396.333 | 0.08 M | 2.65 M | 0.997 | 0 | 389005 | 0 | - | 84.66 [84.17, 84.88] |
| TL2 word-STM (no degree) | 37.893 | 0.86 M | 27.67 M | 0.952 | 0 | 36454 | 0 | - | 8.09 [7.80, 8.14] |
| non-transactional CAS | 1.546 | 21.19 M | 678.14 M | 0.000 | 0 | 1112 | 0 | - | 0.33 [0.33, 0.33] |

## uniform-ins-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.039 | 64.91 M | 259.63 M | 0.000 | 0 | 232 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.094 | 64.03 M | 256.13 M | 0.000 | 0 | 239 | 0 | - | 1.01 [1.01, 1.02] |
| GTX-GPU, 2x growth layout | 4.003 | 65.49 M | 261.96 M | 0.000 | 0 | 232 | 0 | - | 0.99 [0.99, 1.00] |
| GTX-conservative port | 4.154 | 63.10 M | 252.41 M | 0.020 | 0 | 469 | 0 | - | 1.03 [1.02, 1.04] |
| 2PL vertex locks | 2.018 | 129.88 M | 519.53 M | 0.000 | 0 | 350 | 0 | - | 0.50 [0.50, 0.51] |
| TL2 word-STM | 7.561 | 34.67 M | 138.68 M | 0.408 | 0 | 2137 | 0 | - | 1.87 [1.87, 1.89] |
| TL2 word-STM (no degree) | 3.217 | 81.48 M | 325.91 M | 0.103 | 0 | 712 | 0 | - | 0.80 [0.80, 0.80] |
| non-transactional CAS | 1.486 | 176.43 M | 705.72 M | 0.000 | 0 | 209 | 0 | - | 0.37 [0.37, 0.37] |

## uniform-ins-K8

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.296 | 30.51 M | 244.10 M | 0.000 | 0 | 470 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.367 | 30.01 M | 240.09 M | 0.000 | 0 | 479 | 0 | - | 1.02 [1.01, 1.02] |
| GTX-GPU, 2x growth layout | 4.274 | 30.67 M | 245.33 M | 0.000 | 0 | 468 | 0 | - | 0.99 [0.99, 1.00] |
| GTX-conservative port | 4.691 | 27.94 M | 223.53 M | 0.071 | 0 | 1190 | 0 | - | 1.09 [1.09, 1.10] |
| 2PL vertex locks | 2.350 | 55.77 M | 446.19 M | 0.000 | 0 | 903 | 0 | - | 0.55 [0.54, 0.56] |
| TL2 word-STM | 19.536 | 6.71 M | 53.67 M | 0.836 | 0 | 11898 | 0 | - | 4.55 [4.39, 4.57] |
| TL2 word-STM (no degree) | 5.232 | 25.05 M | 200.43 M | 0.348 | 0 | 2632 | 0 | - | 1.22 [1.21, 1.22] |
| non-transactional CAS | 1.526 | 85.91 M | 687.25 M | 0.000 | 0 | 353 | 0 | - | 0.36 [0.35, 0.36] |

## uniform-readers50-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.229 | 81.19 M | 160.20 M | 0.005 | 0 | 212 | 184 | - | — |
| GTX-GPU + M4 merge/reuse | 3.467 | 75.61 M | 149.18 M | 0.005 | 0 | 219 | 191 | - | 1.07 [1.06, 1.08] |
| GTX-GPU, 2x growth layout | 3.221 | 81.37 M | 160.55 M | 0.006 | 0 | 212 | 184 | - | 1.00 [0.99, 1.00] |
| GTX-conservative port | 3.229 | 81.19 M | 160.20 M | 0.010 | 0 | 323 | 183 | - | 1.00 [0.99, 1.00] |
| 2PL vertex locks | 1.801 | 145.54 M | 287.16 M | 0.000 | 0 | 296 | 300 | - | 0.56 [0.54, 0.58] |
| TL2 word-STM | 5.663 | 46.29 M | 91.32 M | 0.235 | 0 | 1833 | 1099 | - | 1.75 [1.75, 1.76] |
| TL2 word-STM (no degree) | 3.084 | 84.99 M | 167.70 M | 0.075 | 0 | 694 | 603 | - | 0.96 [0.95, 0.96] |
| non-transactional CAS | 1.514 | 173.09 M | 341.42 M | 0.000 | 0 | 224 | 255 | - | 0.47 [0.47, 0.47] |

## uniform-readers50-K4-roCoop

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 3.211 | 81.63 M | 161.07 M | 0.006 | 0 | 243 | 184 | - | — |
| GTX-GPU + M4 merge/reuse | 3.452 | 75.94 M | 149.84 M | 0.005 | 0 | 213 | 189 | - | 1.07 [1.06, 1.08] |
| GTX-GPU, 2x growth layout | 3.223 | 81.35 M | 160.51 M | 0.006 | 0 | 223 | 183 | - | 1.00 [0.99, 1.01] |
| GTX-conservative port | 3.257 | 80.48 M | 158.81 M | 0.010 | 0 | 329 | 187 | - | 1.01 [1.00, 1.02] |
| 2PL vertex locks | 1.766 | 148.41 M | 292.85 M | 0.000 | 0 | 196 | 254 | - | 0.55 [0.54, 0.56] |
| TL2 word-STM | 4.249 | 61.70 M | 121.75 M | 0.153 | 0 | 450 | 436 | - | 1.32 [1.31, 1.33] |
| TL2 word-STM (no degree) | 2.493 | 105.13 M | 207.47 M | 0.061 | 0 | 251 | 278 | - | 0.78 [0.77, 0.78] |
| non-transactional CAS | 1.230 | 213.16 M | 420.51 M | 0.000 | 0 | 147 | 187 | - | 0.38 [0.38, 0.39] |

## zipf-churn-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 4.117 | 63.68 M | 243.70 M | 0.020 | 0 | 383 | 0 | - | — |
| GTX-GPU + M4 merge/reuse | 4.467 | 58.69 M | 224.60 M | 0.018 | 0 | 409 | 0 | - | 1.09 [1.06, 1.10] |
| GTX-GPU, 2x growth layout | 5.909 | 44.37 M | 169.79 M | 0.020 | 0 | 552 | 0 | - | 1.44 [1.41, 1.45] |
| GTX-conservative port | 4.119 | 63.65 M | 243.57 M | 0.036 | 0 | 520 | 0 | - | 1.00 [0.98, 1.01] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >21863 |
| TL2 word-STM | 1498.816 | 0.09 M | 0.34 M | 1.000 | 126892 | 284014 | 0 | - | 705.69 [685.24, 714.03] |
| TL2 word-STM (no degree) | 3.006 | 87.19 M | 333.72 M | 0.130 | 0 | 695 | 0 | - | 0.73 [0.72, 0.74] |
| non-transactional CAS | 1.507 | 173.91 M | 665.35 M | 0.000 | 0 | 221 | 0 | - | 0.37 [0.36, 0.37] |

## zipf-readers50-K4

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 146.163 | 1.79 M | 3.49 M | 0.006 | 0 | 24275 | 23810 | - | — |
| GTX-GPU + M4 merge/reuse | 147.192 | 1.78 M | 3.46 M | 0.006 | 0 | 24156 | 23860 | - | 1.01 [0.99, 1.02] |
| GTX-GPU, 2x growth layout | 146.988 | 1.78 M | 3.47 M | 0.007 | 0 | 24175 | 23643 | - | 1.01 [1.00, 1.03] |
| GTX-conservative port | 147.032 | 1.78 M | 3.47 M | 0.012 | 0 | 25953 | 24674 | - | 1.01 [0.98, 1.02] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >616 |
| TL2 word-STM | 3318.986 | 0.06 M | 0.10 M | 0.999 | 49024 | 413545 | 2676368 | - | 27.93 [27.24, 29.57] |
| TL2 word-STM (no degree) | 1076.539 | 0.24 M | 0.47 M | 0.729 | 0 | 702 | 553605 | - | 7.37 [7.12, 7.53] |
| non-transactional CAS | 165.100 | 1.59 M | 3.09 M | 0.000 | 0 | 322 | 120983 | - | 1.13 [1.06, 1.21] |

## zipf-readers50-K4-roCoop

| system | ms (median) | committed txn/s | effective edges/s | abort ratio | give-ups | upd p99 us | RO p99 us | check | speedup of GTX-GPU |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| GTX-GPU (ours) | 145.751 | 1.80 M | 3.50 M | 0.006 | 0 | 24333 | 24041 | - | — |
| GTX-GPU + M4 merge/reuse | 148.272 | 1.77 M | 3.44 M | 0.006 | 0 | 24343 | 23880 | - | 1.02 [1.00, 1.03] |
| GTX-GPU, 2x growth layout | 147.822 | 1.77 M | 3.45 M | 0.007 | 0 | 24240 | 24144 | - | 1.01 [1.00, 1.03] |
| GTX-conservative port | 145.970 | 1.80 M | 3.49 M | 0.012 | 0 | 25347 | 24032 | - | 1.00 [0.99, 1.02] |
| 2PL vertex locks | DNF>90000 | | | | | | | | >617 |
| TL2 word-STM | DNF>90000 | | | | | | | | >617 |
| TL2 word-STM (no degree) | DNF>90000 | | | | | | | | >617 |
| non-transactional CAS | 76.881 | 3.41 M | 6.63 M | 0.000 | 0 | 110 | 17850 | - | 0.53 [0.52, 0.59] |

