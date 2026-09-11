# Serial decode optimization: completed stage

Investigation against `06ee661`, Mojo 1.0.0 / MAX core 26.5.0, Treelite 4.6.1,
Ryzen 5950X, Linux, 2026-09-11; retained in `c00ca17`. All validation was enabled
in this stage. The later [policy](validation-policy.md) added a supported opt-out;
the [full opt-out comparison](validation-opt-out-results.md) is the latest
Treelite result. These historical timings isolate the preceding optimizations.

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

## Decision and timing evidence

Keep all three changes. Across 12 real-framework/scaled checkpoints, serial
decode time fell **23–34%** and standalone serial validation **22–29%**.
The 924-batch sweep used seven independent shuffled process batches per
configuration, CPUs 0–7, eight operation-specific warmups, and an 80 ms target
capped at 10,000 calls. Copies and destruction were included; setup, I/O and
warmup were excluded. The host was not isolated or frequency-locked.

| 100,020-node forest | Before serial decode | After serial | After default | Native Treelite |
| --- | ---: | ---: | ---: | ---: |
| XGBoost | 12.11 ms | 9.02 ms | 8.61 ms | 6.88 ms |
| RF multioutput | 13.99 ms | 10.81 ms | 10.33 ms | 8.54 ms |

Serial decode speedup intervals were approximately 1.31–1.41× / 1.25–1.36×
(XGBoost / RF), from 5,000 bootstrap resamples of process-batch medians.
Default validated decoding still took 25% / 21% longer than native at this
stage. Large default encode took 4.02 / 4.19 ms versus native's 4.68 / 5.56 ms.
Small LightGBM encode was 0.07 µs slower, with an interval overlapping parity;
there was no established uniform small-model encode win.

An earlier sweep warmed only validation. Its broad trend agreed, but the
reported results use corrected, matched operation-specific warmups. The complete
12-case table remains in the original report in Git history and raw evidence.

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

## Paths ruled out and the next decision

Nearly equal allocation counts ruled out "Balsa allocates many more objects"
as the explanation for its serial gap. A generic malloc hook alone missed Mojo
allocations; the KGEN hook was necessary. Reservation saved requested bytes,
but scalar loading delivered the larger latency improvement. Dynamic topology
checks were retained: only checks justified by existing array-length proofs
were removed.

A separate diagnostic build skipped the final decode validation call on valid
fixtures, with independent validation outside timing. Seven-batch CPU 0 probes
included repeated small trees, single-node trees, uneven 1/255-node trees,
128 trees of 1,023 nodes, and a dominant 65,535-node tree plus leaves. The parser
was broadly competitive with native. For 128 large trees, validated decode took
1.99 ms, diagnostic parse-only 0.43 ms, and native 0.57 ms: model validation
dominated that shape. Separate binaries and sessions prevent interpreting those
numbers as an exact additive cost breakdown.

That diagnostic result subsequently led to the public per-call opt-out in
`b2765e8`. It did not justify dropping validation from default decoding. The
later 144-job opt-out sweep covers the real-framework/scaled corpus, not all
these synthetic shapes; large individual trees remain a separate tuning question.

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
changes. The diagnostic source fork remains local; the subsequent supported
opt-out is documented separately in the validation policy.
