# MAX validation evaluation

Implementation based on `737874f3eae9d95a0517397130f445b303d28cc6`,
Mojo 1.0.0 / MAX core 26.5.0, Ryzen 5950X, Linux, 2026-09-11.

## Implementation

Validation uses MAX's CPU `parallelize` executor. The immutable model is divided
into contiguous, approximately node-balanced batches, with at most one batch per
requested worker. Each batch reuses its own traversal scratch and records its
first error in a disjoint slot. The caller joins all batches and selects the first
error in tree order. Metadata and cumulative resource checks stay serial. If a
preflight check fails, serial validation is replayed to preserve the precedence
of earlier structural errors over later metadata or limit errors.

`ValidationOptions` propagates through typed and automatic-precision codecs and
file helpers, and `ModelBuilder.build`. The default is four workers, at least 4,096 trees and 65,536 nodes,
and no tree containing more than half the nodes. One worker explicitly selects
serial execution. Zero thresholds permit experiments on smaller forests; the
imbalance guard remains. Encoding and decode parsing have not been parallelized.
The model is never copied for validation and no validity cache persists.

## Method

`tools/benchmark_threading.py` prepares real-framework repeated forests and
synthetic unequal-size trees. Each configuration runs in seven independent
processes in a seeded shuffled order. Affinity is eight distinct physical cores
(CPUs 0–7), shared by all runtime workers and callers. First validation is timed
before eight warmups, followed by an adaptive batch of 5–400 calls. Setup,
checkpoint reads and byte-parity checks are outside timing. Decode timings
include the public API's required input copy. The first-call measurement excludes
process startup, runtime initialization in Mojo `main`, and serial setup decoding;
it includes the first executor dispatch and its allocations. It is not cold
filesystem or cold-process loading latency.

Simultaneous callers are nested tasks in the same MAX pool operating on the same
immutable model. Reported ns/call is elapsed / (loops × callers), a throughput
measure, not individual request latency. It does not model independent external
request threads, separate pools, or NUMA systems.

Peak RSS is whole-process high-water memory including model setup and the
out-of-timing parity check. It does not isolate traversal scratch or allocator
retention. The measurement driver must run with `--reuse` after preparation so
its own Treelite allocations do not contaminate child `ru_maxrss` through fork.

Another benchmark used physical cores 8–15 during part of the evaluation.
Although CPU affinity separates the tasks, cache, memory bandwidth, power and
background desktop activity are not fully isolated. This is not an idle-host
measurement.

The earlier pilot ran concurrently with some compilation/tests and used a less
selective policy. It informed the imbalance guard but is not the final evidence.

## Crossover, cold calls and concurrency

The confirmation sweep covers 24 models and 288 configurations, with 2,016
process batches. A separate seven-batch sweep of the final implementation showed
the same broad gains; its RSS readings are discarded because preparation ran in
the parent process. The table below uses the fresh-driver confirmation sweep.
Times are median warm validation µs with zero activation thresholds, except that
the dominant-tree guard always remains active:

| Forest | Trees / nodes | Serial | 2 workers | 4 workers | 8 workers |
| --- | ---: | ---: | ---: | ---: | ---: |
| XGBoost | 64 / 960 | 20.2 | 19.4 | 16.7 | 69.1 |
| XGBoost | 512 / 7,680 | 158.1 | 115.0 | 73.1 | 130.7 |
| XGBoost | 2,048 / 30,720 | 616.7 | 433.5 | 264.7 | 356.0 |
| XGBoost | 4,096 / 61,440 | 1,216.9 | 845.5 | 538.1 | 537.5 |
| XGBoost | 4,608 / 69,120 | 1,506.0 | 871.6 | 591.5 | 549.3 |
| XGBoost | 6,668 / 100,020 | 2,115.3 | 1,121.5 | 909.1 | 787.7 |
| Random forest | 6,668 / 100,020 | 2,034.7 | 1,091.7 | 869.0 | 723.6 |
| Single-node trees | 4,096 / 4,096 | 239.4 | 188.3 | 128.8 | 351.0 |
| Unequal 1/255-node trees | 4,096 / 69,120 | 1,519.1 | 764.8 | 413.5 | 649.8 |
| Few large trees | 128 / 130,944 | 2,326.4 | 1,164.4 | 613.1 | 498.7 |
| One dominant tree | 4,096 / 69,630 | 1,464.6 | 1,443.4 | 1,390.0 | 1,393.2 |

Four workers start paying off below the default threshold for warm calls. Cold
cost changes the tradeoff: on the 64-tree case, four workers take 90 µs on first
validation versus 19 µs serial, and eight workers take 286 µs. At 100,020 nodes,
default first validation takes 1.04 ms for XGBoost and 1.13 ms for random forest,
versus 2.21 ms and 2.13 ms serial. These are first-dispatch costs after serial
setup, not process startup. Eight workers are not reliably better than four;
unequal-tree and smaller-forest runs particularly show scheduling variability.

Both candidate tree thresholds were tested with the same 65,536-node floor:

| Forest | 2,048-tree threshold | 4,096-tree threshold |
| --- | ---: | ---: |
| 2,048 unequal trees / 67,328 nodes | 417 µs | 1,301 µs (serial) |
| 3,072 unequal trees / 100,992 nodes | 545 µs | 1,952 µs (serial) |
| 4,096 unequal trees / 69,120 nodes | 442 µs | 443 µs |
| 4,608 XGBoost trees / 69,120 nodes | 568 µs | 604 µs |

The 4,096-tree default deliberately leaves gains on the table for the synthetic
2,048/3,072-tree cases and the 128-large-tree case. This is a conservative choice
until there is evidence from more varied trained forests. For repeated 15-node
trees, the node floor is the binding condition: 4,096 trees remain serial and
4,608 activate. This also prevents a large count of trivial trees from triggering
the executor. Callers can lower the thresholds for measured workloads.

The initial unguarded dominant-tree pilot barely improved standalone validation
and worsened concurrent throughput; the largest indivisible tree held almost
all the work. The final guard keeps that shape serial, including when thresholds
are zero. Node-balanced batches help the dispersed unequal-size case, but cannot
parallelize the inside of a single tree.

For four simultaneous callers on the 100,020-node forests, confirmation throughput
in µs/completed validation is:

| Forest | Serial per caller | 2 workers/caller | 4 workers/caller | 8 workers/caller |
| --- | ---: | ---: | ---: | ---: |
| XGBoost | 674 | 990 | 682 | 334 |
| Random forest | 655 | 997 | 640 | 348 |

Two simultaneous XGBoost callers measure 1,038 / 1,048 / 778 / 524 µs per call
for the same worker settings. Thus fewer workers do not imply better aggregate
throughput, and four-worker validation provides little gain with four callers.
Request-parallel applications should benchmark their own policy; serial remains
a useful explicit option. These measurements test nested calls in one pool, not
independent host threads. The executor overlap probe observed exactly 1, 2, 4 and
8 concurrent tasks for those respective limits, and all nested runs completed.

Whole-process median peak RSS for the large XGBoost case is 59.3–59.4 MiB across
1/2/4/8 workers; random forest is 67.3–67.4 MiB. There is no material peak-RSS
increase visible at this resolution. Small-case RSS varies by several MiB and
cannot isolate executor allocation. The roughly 294 MiB installed package cost
is separate from these runtime measurements.

## Baseline comparison and decision

The original binary versus the final default policy on the existing corpus
(nine independently launched timing batches per cell):

| 100,020-node forest | Operation | Original serial | Default MAX | Speedup |
| --- | --- | ---: | ---: | ---: |
| XGBoost, float32 | Validate | 2.012 ms | 0.844 ms | 2.38× |
| Random forest, float64 | Validate | 2.042 ms | 0.893 ms | 2.29× |
| XGBoost | Encode | 4.902 ms | 3.682 ms | 1.33× |
| Random forest | Encode | 5.000 ms | 3.803 ms | 1.31× |
| XGBoost | Decode | 11.678 ms | 11.116 ms | 1.05× |
| Random forest | Decode | 13.852 ms | 12.276 ms | 1.13× |

Encoding time falls 24–25%, despite leaving encoding itself serial. Decode time
falls 5–11%; parsing and allocation still dominate. An independent bootstrap of
process-batch medians (5,000 resamples) puts the approximate 95% speedup intervals
at 2.15–2.52× / 2.20–2.72× for validation, 1.30–1.38× / 1.29–1.36× for encoding,
and 1.02–1.11× / 1.04–1.19× for decoding (XGBoost / random forest). These intervals
quantify batch variation on this host, not uncertainty across hardware or models.

Across the ten smaller corpus entries, median default validation ranges from
3.7% slower to 5.2% faster than the old binary; the largest observed slowdown is
about 25 ns on a 0.65 µs categorical fixture. Small encode/decode changes are
also within roughly 6%. There is no small-input executor dispatch. These tiny
absolute differences should not be interpreted as systematic improvements.

**Keep the implementation for large-model workloads**, with the conservative
policy and explicit serial control. The validation and encode improvements are
substantive and repeatable. The smaller decode improvement alone would be a
weaker argument for adding a 294 MiB dependency. Applications mostly handling
small models gain no executor benefit; this dependency tradeoff is real.
Measurements are still dominated by repeated small trees, so broader production
corpora and other hardware remain useful before relaxing automatic activation.

## Packaging

The locked `max-core==26.5.0` package requires `mojo-compiler==1.0.0` and adds no
Python package dependency. On linux-64 its download is 117,588,665 bytes
(112.14 MiB); its installed files total 308,062,412 bytes (293.79 MiB). Existing
Mojo runtime shared libraries provide CPU threading. This is a material install
cost even for applications that always select serial validation.

MAX core is distributed under `LicenseRef-Modular-Proprietary`, as recorded in
its conda package metadata. Balsa does not copy MAX source or ship a C++ pool.
Source imports and `mojo precompile` require the compatible MAX package.
[The official executor API](https://max.modular.com/stable/api/mojo/max/algorithm/backend/cpu/parallelize/parallelize.md)
provides a per-call `num_workers` limit and waits for completion. This does not
resize or cap the global runtime pool. [Mojo runtime initialization](https://mojolang.org/docs/std/runtime/asyncrt/initialize_runtime/)
is automatic for Mojo executables; foreign hosts calling Mojo shared libraries
must initialize it explicitly. Foreign-host integration is not exercised here.

## Reproduction

From `balsa`, with the locked Pixi environments:

```sh
pixi run check
pixi run mojo build -O3 -I src tools/threading_worker.mojo -o build/threading/worker
pixi run -e benchmark python tools/benchmark_threading.py --prepare-only
pixi run -e benchmark python tools/benchmark_threading.py --reuse
python tools/analyze_threading.py
pixi run mojo run tools/threading_executor_probe.mojo
```

`build/threading/{cases,results,environment,summary}.json` retain model hashes,
raw observations, source hashes and the environment. Generated checkpoints and
raw results are ignored; scripts and this report are tracked. The existing
`benchmarking/balsa_worker.mojo` can be built against the baseline commit's
`src` snapshot and current `src` as `build/threading/baseline` and
`build/threading/parallel`. `python tools/threading_compare.py` then compares
standalone validation and complete encode/decode on the existing corpus, using
nine randomized batches per binary/configuration. That legacy corpus and worker
are local, ignored investigation artifacts, as in the originating plan.


## Verification

The native suite checks serial/parallel byte equality, both float precisions,
vector leaves and categorical trees, invalid options, repeated deterministic
failures, metadata-versus-structure precedence, cumulative limits and scratch
reset after failure. Concurrent failing callers also compare against the serial
error. Benchmark workers validate byte parity outside every timing batch.

All 21 core tests and eight framework tests pass. The existing benchmark verifier
passes all 12 corpus entries across Balsa, native Treelite and Python Treelite.
The final checks include the repository `check` task, a consumer compiled against
`build/balsa.mojoc`, framework interoperability, and the executor overlap probe.
No foreign-host runtime lifecycle test or race-detector run was performed.
