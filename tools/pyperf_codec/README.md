# Controlled Balsa / Treelite codec comparison

Run from the repository root in the pinned benchmark environment:

```sh
pixi run -e benchmark python tools/pyperf_codec/build.py benchmarking/your-new-run
pixi run -e benchmark python tools/pyperf_codec/controlled.py benchmarking/your-new-run
pixi run -e benchmark python tools/pyperf_codec/analyze.py benchmarking/your-new-run
pixi run -e benchmark python tools/pyperf_codec/verify.py benchmarking/your-new-run
```

`build.py` refuses to overwrite a directory. By default it archives `HEAD` for both editable and packed workers, rather
than compiling uncommitted source changes. Use `--revision COMMIT_OR_TAG` to
measure an older revision, or `--main` / `--packed` to select different revisions
for the two representations. The selected revisions must contain the worker
APIs being measured; older incompatible revisions fail at build time.
To reproduce the historical September 15 comparison, pass
`--main fbba1fc --packed e7f11c0`. Full resolved commit hashes are recorded. Builds use the current locked Pixi
environment; selecting a historical commit does not restore its compiler.
For actual file APIs and process memory, see the [storage workload harness](../storage_workload/README.md). It links
the C++ reference to the installed Treelite 4.6.1 wheel's library and records
source, binary, corpus, compiler, library, and environment provenance.

`controlled.py` defaults to CPU 14 for the serial matrix and CPUs 14–17 for
the checked four-worker supplement. Choose available physical cores with
`--cpu` and `--multicore` on another machine. These settings are saved in the
schedule; a resumed run uses the saved settings. No governor, isolation, or
other system configuration is changed. Avoid unrelated CPU-heavy work while
measuring. Resume an interrupted run with the same command: completed cells
are skipped, but existing output for an unfinished cell requires inspection.

## Contracts

- `treelite-native`: C ABI decode; serialization followed by a copy from
  Treelite's thread-local buffer into independent owned bytes.
- `treelite-python`: public Python `deserialize_bytes` / `serialize_bytes`;
  includes wrapper overhead and is a secondary, user-facing comparison.
- `balsa-on` / `balsa-off`: editable consuming API, semantic validation
  enabled with one worker / disabled. Decode includes copying the resident
  source into an owned input list. Encode rebuilds bytes from model fields.
- `balsa-borrow-on` / `balsa-borrow-off`: editable borrowed-input decode,
  avoiding that input ownership copy. The decoded model still owns its fields.
- `packed-on` / `packed-off`: packed consuming decode, retaining
  the input copy and an offset index instead of allocating all tree arrays.
- `packed-copy`: copy already serialized bytes from a packed model validated
  during setup. No timed semantic revalidation; **not** an editable encoder.
- `balsa-default`: editable consuming API with explicit checked four-worker
  validation (legacy engine ID; **not** the current public API defaults), measured separately with four available CPU cores.

Disabling Balsa semantic validation does not disable structural parsing,
bounds checks, resource limits, or encoder sizing checks. Treelite uses its
normal API checks: its validation contract is not asserted to be identical.

## Measurement design

Sixteen inputs cover eight framework fixtures, four repeated-forest scale
cases, and four synthetic shapes (leaf-only, uneven, few-large, dominant-tree).
The scaled cases repeat real trees; they are allocation/scale probes, not
independently trained large models. The corpus includes float32 and float64.

The serial matrix has eight decode and five encode arms, repeated in two
blocks with reversed engine order: 416 cells. The checked four-worker supplement has 16 cells
covering two large forests, two operations, and two engines in two blocks.
Case/operation pairs use a fixed shuffled order. Each cell has three pyperf
process groups, five measured values per group, two pyperf warmups, and a
minimum target batch time of 100 ms. Each value invokes a fresh native/Python
codec subprocess with eight internal warmup calls, followed by one timed
batch. pyperf calibrates the number of calls; startup, file reading, setup,
warmups, and parity checks are outside the returned codec time. Fresh output
destruction is inside it. Input bytes and encode source models are resident.

This measures warmed, in-memory codec throughput. It does not measure disk
I/O, cold startup, end-to-end model training/conversion, individual-request
tail latency, or peak memory. pyperf's orchestrator RSS is not codec RSS.
Do not use `--track-memory` or `--tracemalloc` with this adapter.

Preflight checks cover all engine/operation/input configurations. Workers
verify round-trip byte parity during setup and operation checksums. Full
analysis requires all 432 cells and checks metadata, affinity, and sample
counts. Partial inspection is available with `analyze.py --partial` and
produces separately named files without bootstrap intervals.

## Reading the output

- `build.json`, `corpus/manifest.json`: pinned provenance and corpus hashes.
- `schedule.json`, `preflight.json`: execution progress/settings and checks.
- `results/*.json`, `results/*.log`: original pyperf samples and warnings.
- `summary.json`: per-arm means, batch medians/p95, process CV, block means,
  ratios against native/Python Treelite and editable Balsa, bootstrap intervals.
- `quality.json`: all warning lines and completeness counts.
- `tables.md`: complete latency and native-ratio tables.

Ratios below one favor the compared engine. The center is the mean of six
process-group means across both blocks (30 measured batches). The 95%
descriptive bootstrap interval resamples those means within each block,
5,000 times. A directional assessment additionally requires both block
ratios to agree. No samples are discarded. Intervals do not account for
all host drift or correct for multiple comparisons; close results should
not be presented as established performance advantages.

The raw run directory is intentionally ignored by git. Preserve it with any
published report; a Markdown summary alone is not the full evidence archive.

`verify.py` runs the checked-out branch's build/package/runtime acceptance,
oracle fixture and interop checks, generated-doc check, and packed compile-fail
checks only after timing finishes. It records logs and source hashes in a new
`acceptance/` directory. Inspect the compile-fail logs to confirm the failure
is the intended ownership/mutation diagnostic, not an unrelated compiler error.
