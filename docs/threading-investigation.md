# Parallel validation: findings and next steps

Investigation against commit `737874f`, Mojo 1.0.0, 2026-09-11.
At that point production remained serial and had no MAX dependency.
The plan below has since been implemented; see [the MAX evaluation and results](threading-results.md).

## Evidence

An isolated C++ thread-pool prototype called Mojo through C FFI. With eight
workers on a Ryzen 5950X, structural validation improved **3.6–3.7×**:

| Model (100,020 nodes) | Serial validation | Eight workers |
| --- | ---: | ---: |
| XGBoost | 1.973 ms | 0.551 ms |
| Random forest | 1.974 ms | 0.533 ms |

These forests contain 6,668 repeated 15-node trees. Results are exploratory:
six timing batches, distinct physical cores, warm persistent pools, with
allocation and synchronization timed but pool startup excluded. Small forests
showed scheduling overhead; neither the crossover nor MAX executor performance
has been established. Existing native tests and corpus roundtrips passed the
prototype checks, including deterministic first-error selection.

The experiment also parallelized encoding (about 2× faster), but the next scope
is **validation only**. Decode parsing stayed serial; parallel validation reduced
large-case decode time by about 12–13%. That is a useful indication of end-to-end
benefit, not a promise of 3.7× faster loading. The encoding measurements do not
isolate the benefit of validation alone.

## Official API and dependency

`parallelize` moved from `std.algorithm` to `max.algorithm`; it was not eliminated.
The [MAX 26.5 release notes](https://max.modular.com/releases/v26.5/#highlights)
document the package move. Mojo's [1.0.0 package-move notes](https://mojolang.org/releases/v1.0.0/#package-moves)
describe the broader migration without explicitly naming this CPU API.
The [MAX CPU API reference](https://max.modular.com/stable/api/mojo/max/algorithm/backend/cpu/parallelize/)
lists `parallelize` and `sync_parallelize`. The
[Mojo runtime](https://mojolang.org/docs/std/runtime/asyncrt/initialize_runtime/)
manages their thread pool and initializes automatically for Mojo `main()`;
non-Mojo hosts calling shared libraries require explicit runtime initialization.

The C++ pool was an experimental workaround, not the official threading API or a
production backend. Prefer evaluating MAX's executor. Adding MAX is an acceptable
dependency tradeoff if it retains meaningful validation and end-to-end gains;
verify compatible versions, installation footprint and packaging before adopting
it. The existing C++ measurements establish potential, not MAX's performance.

## Implementation path

1. Prototype validation with MAX's CPU executor. Keep metadata and cumulative-limit
   checks serial, then process batches of trees against an immutable model. Reuse
   private traversal scratch within each batch; wait for all work before returning.
   Preserve serial error precedence, including competing metadata and tree errors.
2. Benchmark **2,048 and 4,096 trees as candidate activation thresholds**, with
   smaller and larger forests around them. Tree count alone is insufficient:
   include total nodes and uneven tree sizes, balance batches by node count, and
   avoid scheduling one task per tiny tree. Keep the serial path below the measured
   crossover and allow callers to request serial execution or limit concurrency.
3. Measure 2, 4 and 8 workers, cold first calls, warm calls, memory, and simultaneous
   callers. Reuse the runtime pool and verify its concurrency controls. Eight
   workers is a useful test point, not a universal default.
4. Verify correctness and deterministic failures, then rerun the existing benchmark
   infrastructure for standalone validation and full encode/decode. Adopt a
   conservative threshold only after MAX shows repeatable gains without small-input
   regressions. Defer parallel encoding and parsing to separate investigations.

Detailed timings, source snapshots and verification artifacts remain in the
ignored `benchmarking/threading-investigation/` directory.
