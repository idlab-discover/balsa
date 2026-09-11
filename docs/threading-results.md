# MAX validation: implementation decision

Completed in `06ee661` against `737874f`, measured 2026-09-11 on Ryzen 5950X,
Mojo 1.0.0 / MAX core 26.5.0. These are historical validation-enabled results,
before the later serial optimizations. See [the performance wrap-up](performance-plan.md)
for the complete sequence and [validation policy](validation-policy.md) for the
current opt-out contract.

## What was kept

MAX's CPU executor validates contiguous, approximately node-balanced batches
against an immutable model. Each batch reuses private traversal scratch and
records its first error in a disjoint slot. The caller joins all batches and
selects the earliest error in tree order. Metadata and cumulative resource checks
stay serial; failed preflight checks replay serial validation to preserve error
precedence. There is no model copy or persistent validity cache.

The default uses at most four workers when there are at least 4,096 trees and
65,536 nodes, with no tree containing more than half the nodes. One worker forces
serial execution. Callers can tune both thresholds; the imbalance guard always
applies. The options propagate through codec/file APIs and model construction.
Parsing and encoding themselves remain serial.

| 100,020-node forest | Operation | Original serial | Default MAX |
| --- | --- | ---: | ---: |
| XGBoost | Validate | 2.012 ms | 0.844 ms |
| RF multioutput | Validate | 2.042 ms | 0.893 ms |
| XGBoost | Encode | 4.902 ms | 3.682 ms |
| RF multioutput | Encode | 5.000 ms | 3.803 ms |
| XGBoost | Decode | 11.678 ms | 11.116 ms |
| RF multioutput | Decode | 13.852 ms | 12.276 ms |

Nine randomized process batches per cell supported keeping the change:
validation improved 2.3–2.4×, encode time fell 24–25%, and decode time 5–11%.
Approximate 95% bootstrap speedup intervals were 2.15–2.52× / 2.20–2.72× for
validation and 1.02–1.11× / 1.04–1.19× for decode (XGBoost / RF). Smaller cases
never dispatch to the executor; tiny differences within roughly 6% were not
interpreted as systematic improvements.

## Choices constrained by the experiments

A confirmation sweep covered 24 models, 288 configurations and 2,016 process
batches, including unequal sizes, dominant trees and simultaneous callers.

- Warm crossover alone was misleading. At 64 trees, first validation took about
  90 µs with four workers versus 19 µs serial; eight workers took 286 µs. Large
  first-dispatch calls still benefited. These exclude process/runtime startup.
- Eight workers were not reliably better than four, especially for smaller or
  uneven forests. Four became the conservative default.
- Both 2,048- and 4,096-tree thresholds were tested with the 65,536-node floor.
  The latter intentionally leaves gains on synthetic 2,048/3,072-tree cases and
  few-large-tree cases. For repeated 15-node trees, the node floor controls
  activation: 4,096 trees stay serial; 4,608 activate.
- An unguarded dominant tree barely benefited and hurt concurrent throughput.
  Node balancing cannot split one tree, so the guard keeps that shape serial.
- With four simultaneous callers, four workers per call gave little aggregate
  benefit over serial validation per caller. Request-parallel applications need
  their own measurements; fewer workers did not consistently improve throughput.
- No material large-case peak-RSS increase was visible across worker counts.
  This is whole-process high-water memory, not a measurement of scratch alone.

The warm C++ pool prototype was replaced by MAX, not shipped. Parallel encoding
was deferred. The validation and encode gains justified keeping the executor;
the modest decode gain alone would have been a weaker argument.

## Dependency and measurement limits

The locked `max-core==26.5.0` package is compatible with Mojo 1.0.0. Its measured
linux-64 footprint was 112 MiB downloaded and 294 MiB installed, under
`LicenseRef-Modular-Proprietary`; no MAX Python package is required. This install
cost remains even for serial-only applications. The per-call worker limit does
not cap the global runtime pool. Mojo executables initialize the runtime;
foreign hosts must initialize it explicitly. Foreign-host lifecycle was not tested.

Measurements used CPUs 0–7 and seven independent shuffled batches for the
confirmation sweep. Another benchmark used cores 8–15 during part of the work;
shared cache, memory bandwidth and desktop activity were not isolated.
Simultaneous callers were nested tasks in one MAX pool, not independent host
threads; reported time per completed call measures throughput. A separate driver
was required for credible RSS results because preparation allocations inherited
through fork contaminated an earlier sweep. That earlier RSS evidence was discarded.

## Verification and reproduction

At this stage, 21 core and eight framework tests passed, including precision,
serial/parallel parity, deterministic error precedence, scratch reset and failing
concurrent callers. Package consumption, interoperability, the 12-case benchmark
verifier and executor overlap probes passed. No race-detector run was performed.

```sh
pixi run -e benchmark python tools/benchmark_threading.py --prepare-only
pixi run -e benchmark python tools/benchmark_threading.py --reuse
python tools/analyze_threading.py
pixi run mojo run tools/threading_executor_probe.mojo
```

Tracked tools reproduce the sweep against the source being built; they do not
freeze the historical implementation. Original raw records and hashes remain in
ignored `build/threading/` and `benchmarking/threading-investigation/`. Full
crossover and concurrency tables are preserved in Git history.
