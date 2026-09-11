# Serial decode and validation: profile-guided improvements

Investigation against `06ee661`, Mojo 1.0.0 / MAX core 26.5.0, Treelite 4.6.1,
Ryzen 5950X, Linux, 2026-09-11. All public validation remains enabled.

## Findings and implementation

Balsa's serial decode gap was not explained by allocating more objects. On the
100,020-node XGBoost forest, the original Balsa performs 113,382 allocations and
matching frees per decode; native Treelite performs 113,381 allocation/reallocation
calls and matching frees. They use different allocators and request different
byte volumes. A generic `malloc` hook alone would miss Balsa's TCMalloc-backed
list allocations, so the probe also intercepts Mojo's exported KGEN allocation
and free functions.

The initial `perf` profile attributed about 10% of sampled decode cycles to the
64-bit scalar reader, about 14% to the structural tree validator, and about 33%
to the Mojo runtime allocator library. These are sampled exclusive costs, not
an additive wall-time decomposition. Some allocator-internal symbols are stripped.
Native Treelite instead spends substantial time in C++ stream reads and glibc
allocation/free paths; it does not execute Balsa's full structural validation pass.

Three changes were tested independently and retained:

1. **Bounded scalar loads.** `Reader.scalar` proves the byte extent once, then
   uses an explicitly unaligned fixed-width load on little-endian hosts. This
   removes the byte loop, shifts and repeated list indexing for every array count
   and scalar field. Float bits are preserved. The explicit little-endian byte
   loop remains for big-endian hosts. `Reader.require` also checks the public
   cursor's lower and upper bounds before any raw pointer can be formed.
2. **Bounded tree reservation.** Reserve at most the declared tree count and at
   most `remaining_input_bytes / sizeof(Tree)` entries. This removes repeated
   tree-list growth on the measured forests without trusting a malicious count
   as an allocation request. It is a capacity hint, not a new wire validity
   condition, so parser failure ordering stays unchanged.
3. **Remove redundant node-array bounds checks.** After proving all relevant
   array lengths equal `n`, the `0 <= i < n` loop accesses those arrays directly.
   The immutable borrow keeps their storage stable. All semantic predicates and
   their order remain intact. Dynamic stack/topology indexing remains checked.

The single-core, seven-batch ablation showed scalar loading produced the largest
decode gain: about 18–20% on the two large forests. Reservation added a smaller,
variable latency improvement and reduced allocation traffic. Removing redundant
validation indexing improved standalone validation by roughly a quarter. The
final comparison below confirms the combined result on the whole corpus.

## Final timing comparison

Seven independently launched batches per configuration, seeded shuffled order,
12 real-framework/scaled checkpoints, 924 process batches. Both engines perform
eight **operation-specific** warmups. Batch lengths target 80 ms, capped at 10,000
calls (short operations therefore have shorter batches). The driver checks
checksums, and workers check byte parity outside timing. Input copies and output/model destruction are included; startup, file I/O, setup and warmup are excluded.

All processes have CPU affinity 0–7. Serial columns explicitly use one validation
worker; the default column uses the existing four-worker activation policy.
Treelite uses its public C ABI and returns independently owned bytes in the
harness, matching Balsa's output ownership. This is a wall-time comparison, not
an equal-instruction or equal-CPU-work contract. The desktop host is not isolated
or frequency-locked. No instrumented timings are used in this table.

Median decode times in microseconds:

| Checkpoint | Before, serial | After, serial | Time reduction | After, default | Native Treelite |
| --- | ---: | ---: | ---: | ---: | ---: |
| catboost_numeric_regression | 6.00 | 3.97 | 33.9% | 4.00 | 3.21 |
| lightgbm_categorical | 5.63 | 3.99 | 29.1% | 3.93 | 3.66 |
| sklearn_extra_multioutput_classification | 6.55 | 4.64 | 29.1% | 4.54 | 4.09 |
| sklearn_gradient_binary | 6.73 | 4.60 | 31.6% | 4.55 | 4.02 |
| sklearn_hist_missing_regression | 6.42 | 4.33 | 32.5% | 4.38 | 3.76 |
| sklearn_rf_multiclass | 6.41 | 4.39 | 31.5% | 4.44 | 4.04 |
| sklearn_rf_multioutput_regression | 6.68 | 4.59 | 31.2% | 4.69 | 4.05 |
| sklearn_rf_multioutput_regression_x16 | 92.69 | 68.07 | 26.6% | 65.18 | 65.62 |
| sklearn_rf_multioutput_regression_x1667 | 13985.41 | 10805.17 | 22.7% | 10332.71 | 8537.66 |
| xgboost_regression | 6.28 | 4.42 | 29.6% | 4.48 | 3.65 |
| xgboost_regression_x16 | 88.48 | 62.97 | 28.8% | 62.09 | 56.61 |
| xgboost_regression_x1667 | 12111.56 | 9024.76 | 25.5% | 8607.93 | 6881.33 |

Serial decode improves **23–34% across all twelve cases**; standalone serial
validation improves **22–29%**. On the large XGBoost / random-forest cases,
serial decode speedup is 1.34× / 1.29×, with approximate 95% bootstrap intervals
of 1.31–1.41× / 1.25–1.36× (5,000 independent resamples of process-batch medians).
These intervals quantify batch variation, not hardware or workload generality.

Large default decode now takes 8.61 / 10.33 ms versus native Treelite's
6.88 / 8.54 ms: still about **25% / 21% more time**, but substantially closer.
Large serial encode takes 4.45 / 4.69 ms; default encode takes 4.02 / 4.19 ms,
versus native Treelite's 4.68 / 5.56 ms. Small encoding mostly improves; the
categorical LightGBM case is about 0.07 µs (3%) slower in this run, with a
before/after interval that includes parity. This is not evidence of a uniform
encode win on small models.

An earlier complete sweep with validation-only Balsa warmups also showed the
same broad gains; the final figures above use the corrected, matched
operation-specific warmups in `tools/decode_worker.mojo`.

## Instruction and allocation evidence

Callgrind client requests bracket only the measured loop. On 100 decodes of the
960-node XGBoost case:

| Engine | Instructions |
| --- | ---: |
| Balsa before | 142,348,598 |
| Balsa after | 103,988,429 |
| Native Treelite | 102,703,953 |

Balsa executes **27% fewer instructions** and is within roughly 1% of Treelite's
instruction count on this case, despite performing additional validation. Equal
instruction counts do not imply equal latency: allocator implementation, caches,
branches and memory access patterns still differ.

In the old profile, scalar-reader-attributed code accounted for about 26.5 million
instructions. The new fixed-width loads inline into their callers, so the absence
of a standalone scalar-reader entry does **not** mean parsing is free. Instructions
attributed to validator list bounds checks fell from 11.52 million to 4.16 million;
checks for dynamic traversal and model annotations remain.

A preliminary Callgrind run on the 100,020-node Treelite case emitted a `brk
segment overflow` warning. Its allocator behavior may differ under Valgrind, so
it is not used for the cross-engine instruction table. The medium-case runs
above completed without that warning. Native `perf` sampling and ordinary
wall-time measurements corroborate the identified costs.

Allocator counters are measured in separate preloaded processes. Differences
between 1/11 and 11/21 decode iterations agree exactly. Bytes are the sum of
requested allocation sizes, including realloc requests; they are not live memory,
allocator size classes or physical traffic.

| Large forest | Engine | Allocation calls/decode | Requested bytes/decode |
| --- | --- | ---: | ---: |
| XGBoost | Balsa before | 113,382 | 25,291,268 |
| XGBoost | Balsa after | 113,369 | 19,850,868 |
| XGBoost | Native Treelite | 113,381 | 36,558,344 |
| Random forest | Balsa before | 133,386 | 30,398,980 |
| Random forest | Balsa after | 133,373 | 24,958,580 |
| Random forest | Native Treelite | 133,385 | 44,337,364 |

Reservation removes 13 growth allocations and **5,440,400 bytes (5.19 MiB)** of
requested allocation volume per large decode. Allocation/free counts balance at
the intercepted call sites; this is not a general leak proof. TCMalloc can retain
freed memory for reuse. Runtime allocation cost remains significant even though
allocation frequency is essentially equal to Treelite's.


Separate uninstrumented whole-process RSS probes (three processes, 20 decodes
each, CPU 0) include setup, warmup, input, models and retained allocator pages:

| Forest | Before MiB | After MiB | Native Treelite MiB |
| --- | ---: | ---: | ---: |
| XGBoost | 68.36 | 60.31 | 62.16 |
| Random forest | 76.36 | 70.39 | 84.60 |

These are process peaks, not per-operation live memory or proof that the
allocator returns freed pages to the OS. They corroborate the reduced
tree-growth allocation traffic without claiming identical storage strategies.

## Remaining gap and varied tree sizes

An ignored diagnostic build skips only the final `validate` call inside decode,
using known-valid fixtures that are separately validated by encode. This build
is never used for public output, malformed-input handling or the timing table
above. It estimates how much of the remaining gap comes from validation, rather
than proposing a validation bypass. See the supplemental measurements below.


Supplemental seven-batch serial measurements on CPU 0, in microseconds. These
are a separate session from the full corpus table, with matched operation
warmups. Larger individual trees and highly unequal sizes supplement the
real-framework corpus of mostly tiny repeated trees.

| Case | Before full decode | After full decode | Diagnostic parse only | Native Treelite |
| --- | ---: | ---: | ---: | ---: |
| XGBoost, 64 trees / 960 nodes | 83.93 | 60.06 | 44.18 | 53.00 |
| XGBoost, 6,668 trees / 100,020 nodes | 11047.61 | 8310.76 | 6691.81 | 6511.95 |
| Random forest, 6,668 trees / 100,020 nodes | 12789.53 | 9749.05 | 8028.39 | 8335.57 |
| 4,096 one-node trees | 4286.52 | 2889.32 | 2732.32 | 4868.17 |
| 4,096 unequal 1/255-node trees | 5792.09 | 3835.92 | 2818.66 | 3097.75 |
| 128 trees of 1,023 nodes | 2705.38 | 1990.59 | 425.37 | 567.15 |
| One 65,535-node tree + 4,095 leaves | 5601.60 | 3722.10 | 2799.20 | 3005.59 |

The diagnostic parser is broadly competitive with native Treelite. In the
128-large-tree case, full validation dominates: removing it diagnostically drops
Balsa from about 1.99 ms to 0.43 ms, versus Treelite's 0.57 ms. This explains why
full serial Balsa can still be slower even after much of the parser overhead is
removed. Different binaries/code layout mean these measurements are not an exact
additive decomposition. Production continues to reject malformed topology and
field semantics. Further work on large individual trees should focus on validation.

## Verification and reproduction

- `pixi run check`: 23 core tests, eight framework tests, CLI/example and package
  compilation passed.
- All 23 core tests passed under AddressSanitizer. Leak detection was disabled
  for this bounds/lifetime run; runtime global retention was not audited.
- Differential checks compared **134,246 outcomes** against `06ee661`: every
  truncation and three byte mutations per position over float32/float64,
  categorical, vector, deep and real-framework fixtures; parallel outcomes were
  compared to the serial reference too. Accepted models also re-encode byte-exactly.
- New tests cover all supported scalar widths at offsets 0–15, every truncated
  width, floating bit patterns, cursor bounds and exact failure context.
- Treelite interoperability passed 14 fixture roundtrips and all eight trained
  framework checkpoints. A consumer compiled against `build/balsa.mojoc` passed.
- Big-endian execution is not tested; its existing explicit byte-order path is retained.

The reusable driver builds both commits with the same compiler, prepares the
12-case corpus in a separate process, and records hashes, raw batches, bootstrap
summaries and profiles. It needs the pinned benchmark Pixi environment; `--profile`
also requires globally installed `perf`, Valgrind and a C/C++ compiler.

```sh
pixi run -e benchmark python tools/benchmark_decode.py --profile --output build/decode-confirmation
python tools/analyze_decode.py build/decode-confirmation
callgrind_annotate --auto=no build/decode-confirmation/current.callgrind.1
perf report -i build/decode-confirmation/current.perf
```

For differential verification, extract `06ee661:src/balsa` into an ignored
`reference/baseline_balsa` directory, then run:

```sh
pixi run mojo run -I src -I reference tools/compare_decode.mojo
pixi run mojo build -O3 -g1 --sanitize address -I src tests/test_balsa.mojo -o build/test-asan
ASAN_OPTIONS=detect_leaks=0 ./build/test-asan
```

Final raw evidence lives in ignored `build/decode-confirmation/`. Isolated
variants, ablations, supplemental shapes, RSS probes and differential/ASan logs
remain in ignored `benchmarking/decode-investigation/`. The public implementation,
regression tests, core benchmark/profiling tools and this report are tracked-source
changes; no diagnostic validation bypass is part of the library.
