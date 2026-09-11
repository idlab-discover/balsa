# Codec optimization results — 2026-09-11

Independent verification and performance rerun of the three changes explained in
[How the codec optimizations work](codec-optimization.md).

## Correctness verification

- `pixi run check`: passed 17 core and eight framework tests, package compilation,
  checkpoint smoke test and construction example.
- `pixi run -e oracle interop`: passed 14 byte-exact upstream roundtrips and field
  comparisons, including native-created models, builders and extension records.
- Rebuilt both native benchmark workers, then `benchmarking/verify.py` passed all
  twelve corpus inputs against Balsa, Treelite C ABI and Treelite Python, including
  byte-exact roundtrip and diagnostic operation checks.
- Independent review found no correctness regression in bounds-first bulk copies,
  endian conversion fallback, error-context construction, or traversal scratch
  reset. Big-endian execution is not tested on this little-endian host.


## Full controlled comparison

Mojo 1.0.0, `-O3`; Treelite 4.6.1 wheel for both native and Python references; GCC 16.2.1 native harness; Python 3.12.14 and pyperf 2.10.0. Host: AMD Ryzen 9 5950X, Linux 7.2.4, powersave governor, CPU 14 (SMT sibling 30), without CPU isolation.

Same corpus, workers, ownership/validation contract, CPU 14 affinity, two reversed blocks, three worker groups per block and five measured batches per group as [the baseline](benchmark-results.md). All 144 jobs completed in 17.2 minutes; every engine/case/operation has 30 samples. Required copies and output destruction are timed; startup, compilation, file I/O and eight initial warmup operations are excluded. Baseline and optimized sessions occurred at different times on the same untuned desktop host; before/after ratios are not simultaneous paired trials.

Public decode improved **2.47–3.68×**, and encode **2.43–4.00×** across the twelve cases. These are per-case ranges, not an aggregate score.

Latencies are means of worker means in microseconds. Speedup is baseline / optimized; final Balsa/C is optimized Balsa / freshly measured native Treelite (below one favors Balsa).

| Checkpoint | Decode before → after µs | Speedup | Encode before → after µs | Speedup | Final Balsa/C decode / encode |
| --- | ---: | ---: | ---: | ---: | ---: |
| catboost_numeric_regression | 16.71 → 5.60 | 2.98× | 8.73 → 3.09 | 2.82× | 1.83× / 1.58× |
| lightgbm_categorical | 13.30 → 5.39 | 2.47× | 5.98 → 2.45 | 2.43× | 1.54× / 1.19× |
| sklearn_extra_multioutput_classification | 21.77 → 6.19 | 3.52× | 10.59 → 2.97 | 3.56× | 1.58× / 1.32× |
| sklearn_gradient_binary | 21.06 → 6.26 | 3.36× | 11.10 → 3.16 | 3.51× | 1.65× / 1.43× |
| sklearn_hist_missing_regression | 19.35 → 6.07 | 3.19× | 10.26 → 3.11 | 3.30× | 1.66× / 1.47× |
| sklearn_rf_multiclass | 19.60 → 6.14 | 3.19× | 9.73 → 2.88 | 3.38× | 1.58× / 1.28× |
| sklearn_rf_multioutput_regression | 21.68 → 6.31 | 3.43× | 11.09 → 3.13 | 3.54× | 1.60× / 1.39× |
| sklearn_rf_multioutput_regression_x16 | 338.48 → 92.06 | 3.68× | 170.54 → 43.54 | 3.92× | 1.45× / 1.38× |
| sklearn_rf_multioutput_regression_x1667 | 40566.79 → 12960.82 | 3.13× | 19207.34 → 4806.97 | 4.00× | 1.53× / 0.92× |
| xgboost_regression | 18.91 → 6.09 | 3.11× | 10.15 → 3.21 | 3.16× | 1.77× / 1.53× |
| xgboost_regression_x16 | 297.11 → 85.20 | 3.49× | 152.21 → 45.26 | 3.36× | 1.54× / 1.55× |
| xgboost_regression_x1667 | 34109.90 → 10907.55 | 3.13× | 16270.99 → 4696.52 | 3.46× | 1.80× / 1.06× |

Optimized session has 102 pyperf warning logs; median worker CV 1.37%, maximum 8.86%. Median absolute block drift 0.97%, maximum 13.88%. Fresh native Treelite means / historical native means range 0.911–1.018. No samples were discarded. Bootstrap confidence intervals in the local full summary describe worker sampling uncertainty, not all host noise; close ratios do not establish universal parity.

## Clean sequential ablation

Six process batches per variant and operation, calibrated to at least 100 ms, pinned to CPU 14, alternating forward/reverse variant order. Each worker keeps its usual setup and eight warmups outside the reported interval. These smaller experiments identify mechanisms; use the full controlled run above for public performance comparisons. Earlier `step1-ablation.json` and `step2-ablation.json` were excluded.

| Checkpoint / operation | Original µs | Lazy diagnostics µs | + bulk I/O/planning µs | + validation µs |
| --- | ---: | ---: | ---: | ---: |
| sklearn_rf_multioutput_regression_x1667/decode | 41266.17 | 34329.72 | 15482.94 | 13252.30 |
| sklearn_rf_multioutput_regression_x1667/encode | 19203.90 | 12452.96 | 7198.18 | 5024.79 |
| sklearn_rf_multioutput_regression_x1667/validate | 12127.07 | 4330.10 | 4211.97 | 2094.46 |
| xgboost_regression/decode | 19.26 | 16.56 | 7.37 | 6.18 |
| xgboost_regression/encode | 10.05 | 6.14 | 4.42 | 3.22 |
| xgboost_regression/validate | 6.50 | 2.47 | 2.47 | 1.27 |
| xgboost_regression_x16/decode | 308.02 | 259.74 | 114.65 | 91.80 |
| xgboost_regression_x16/encode | 149.11 | 86.82 | 65.73 | 45.42 |
| xgboost_regression_x16/validate | 104.44 | 38.03 | 37.93 | 18.73 |
| xgboost_regression_x1667/decode | 35058.20 | 29079.34 | 13796.38 | 11476.05 |
| xgboost_regression_x1667/encode | 16668.24 | 10537.90 | 6894.63 | 4730.84 |
| xgboost_regression_x1667/validate | 10906.10 | 4018.88 | 4013.15 | 1949.85 |

Final rebuild was also measured alongside step 3 to check reproduction; exact binary hashes and every batch are retained in ablation provenance and `latency.json`. The validation step combines scratch reuse and helper inlining; this experiment does not separate those two contributions.

## Allocation and process memory evidence

A separate `LD_PRELOAD` shim counts calls to exported `KGEN_CompilerRT_AlignedAlloc`, which forwards to Mojo’s TCMalloc-backed allocator. Counts are differences between otherwise identical 1-, 11- and 21-iteration worker processes; both ten-operation differences agree exactly, removing fixed startup/setup/warmup calls. These are **compiler-runtime allocation calls**, not all-process malloc counts or allocated bytes. Instrumented timings are excluded.

| Checkpoint / operation | Original calls/op | After diagnostics | After bulk I/O | Final calls/op |
| --- | ---: | ---: | ---: | ---: |
| sklearn_rf_multioutput_regression_x1667/decode | 372,400 | 186,726 | 186,726 | 133,386 |
| sklearn_rf_multioutput_regression_x1667/encode | 166,725 | 53,369 | 53,345 | 5 |
| sklearn_rf_multioutput_regression_x1667/validate | 166,700 | 53,344 | 53,344 | 4 |
| xgboost_regression/decode | 207 | 111 | 111 | 83 |
| xgboost_regression/encode | 114 | 46 | 33 | 5 |
| xgboost_regression/validate | 100 | 32 | 32 | 4 |
| xgboost_regression_x1667/decode | 352,396 | 166,722 | 166,722 | 113,382 |
| xgboost_regression_x1667/encode | 166,725 | 53,369 | 53,345 | 5 |
| xgboost_regression_x1667/validate | 166,700 | 53,344 | 53,344 | 4 |

Peak RSS below uses three separate **uninstrumented** processes measured with Linux `wait4().ru_maxrss` per cell, each running 20 operations. Values show the median and full range in MiB. It includes executable/runtime, resident input, setup model/encoded bytes, warmup, and allocator-retained memory; it is not operation-only live memory.

| Checkpoint / operation | Original peak RSS MiB | Final peak RSS MiB |
| --- | ---: | ---: |
| sklearn_rf_multioutput_regression_x1667/decode | 74.0 [73.9, 74.1] | 75.9 [75.9, 76.0] |
| sklearn_rf_multioutput_regression_x1667/encode | 82.0 [81.9, 82.1] | 65.8 [65.8, 65.9] |
| xgboost_regression_x1667/decode | 68.1 [68.0, 68.1] | 67.9 [67.9, 68.0] |
| xgboost_regression_x1667/encode | 74.1 [74.0, 74.1] | 58.0 [57.9, 58.0] |

Encode peak RSS fell by about 16 MiB on both large cases. Decode RSS was roughly unchanged for XGBoost and increased by about 2 MiB for the large random forest; fewer allocation calls do not guarantee a lower process peak.

## Matched component diagnostics

Same four representative cases and isolated copy/validation/dense-array operations as the baseline diagnostics: one block, three groups, five measured batches each. These operations are not an additive decomposition of public latency.

| Component | Baseline µs | Optimized µs | Speedup |
| --- | ---: | ---: | ---: |
| sklearn_rf_multioutput_regression_x1667/copy | 183.99 | 186.84 | 0.98× |
| sklearn_rf_multioutput_regression_x1667/validate | 11732.71 | 2024.09 | 5.80× |
| sklearn_rf_multioutput_regression_x1667/wire_read | 12219.11 | 710.56 | 17.20× |
| sklearn_rf_multioutput_regression_x1667/wire_write | 8829.78 | 397.54 | 22.21× |
| xgboost_regression/copy | 0.07 | 0.07 | 0.99× |
| xgboost_regression/validate | 6.45 | 1.25 | 5.15× |
| xgboost_regression/wire_read | 6.83 | 0.18 | 38.47× |
| xgboost_regression/wire_write | 2.51 | 0.11 | 22.28× |
| xgboost_regression_x16/copy | 1.24 | 1.29 | 0.97× |
| xgboost_regression_x16/validate | 101.42 | 18.55 | 5.47× |
| xgboost_regression_x16/wire_read | 106.83 | 2.64 | 40.43× |
| xgboost_regression_x16/wire_write | 40.21 | 1.42 | 28.35× |
| xgboost_regression_x1667/copy | 139.30 | 140.79 | 0.99× |
| xgboost_regression_x1667/validate | 10851.91 | 1992.06 | 5.45× |
| xgboost_regression_x1667/wire_read | 11230.24 | 316.73 | 35.46× |
| xgboost_regression_x1667/wire_write | 6595.46 | 289.18 | 22.81× |

## Evidence and limits

Local git-ignored `benchmarking/controlled/optimized/` retains schedule, every pyperf JSON/log and full summary with fresh Treelite Python/native latencies and bootstrap intervals. `optimized-diagnostics/` retains component measurements, and `optimization-ablation/` retains binary provenance, every ablation batch, allocation counts and RSS measurements. `optimization-verification/` preserves passing check/interop/corpus logs and a copy of compiler/source/library provenance. Final source hashes still match the measured build. `benchmarking/build-info.json` records compiler/library/source hashes; the original worker is preserved as `benchmarking/balsa_worker_baseline` and its hash matches baseline pyperf metadata.

Large inputs repeat existing trees and do not cover every topology. Both float precisions, categories and vector leaves are covered, but big-endian execution, cold-cache/file I/O and prediction throughput are outside this experiment. Full Balsa validation remains enabled; Treelite has a different validation contract.
