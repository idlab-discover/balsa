# Linux storage workload study

Run from the repository root on rgbcore (Linux x86-64):

```sh
pixi run --locked -e frameworks python tools/storage_workload/corpus.py benchmarking/storage-corpus
pixi run --locked -e frameworks python tools/storage_workload/run.py benchmarking/storage-run --corpus benchmarking/storage-corpus --cpu 14
```

Both output directories must be new. Use an available quiet CPU and avoid other
heavy work during measurement. `--revision` accepts a commit, branch or tag;
it defaults to `HEAD`. Library sources are archived from that commit, excluding
uncommitted edits. The harness itself is copied from the working tree and hashed.
The selected source must support the current packed/editable API. The build
uses the current locked Pixi environment, not a historical compiler environment;
compiler and lock hashes are recorded. Compiler-incompatible revisions need a
separately configured matching environment.

The corpus trains a 128-tree random forest with two regression targets, a
128-tree extra-trees four-class classifier, and a 384-tree XGBoost regressor.
Trees are trained independently rather than made by duplicating a small forest.
Data is seeded and generated, not a production dataset. The manifest records
training parameters, versions, node counts, checkpoint hashes, and prediction
checks against the original frameworks. Regeneration need not produce identical
bytes across platforms/toolchains; retain the measured corpus.

Each of seven shuffled repetitions launches a fresh worker for every cell:

- Packed and editable file load, save and load/save roundtrip, with serial
  semantic validation on/off. Packed save never revalidates; its checked flag
  controls setup loading only. Editable checked roundtrip validates at both
  load and save.
- Packed-to-editable conversion with validation on/off. Conversion setup uses
  unchecked packed loading; both representations remain live during measurement.
- Native Treelite file load, save and roundtrip through the public C ABI,
  retaining upstream's normal checks. Validation work is not identical to Balsa.

Operation timers exclude setup for save/conversion and exclude destruction of
returned models. Process wall time includes launch, dynamic linking, setup,
printing and destruction plus the taskset/wait4 launcher overhead. It is **not**
an isolated startup measurement. All are first-use operations in fresh processes,
not the warmed codec batches measured by `pyperf_codec`.

Input files are pre-read before every worker. File load includes filesystem calls
but benefits from warm page cache. Save includes write/close without `fsync`;
it measures buffered output, not durable media latency. No cache dropping,
frequency changes, or global host tuning is performed.

The small native launcher uses Linux `wait4().ru_maxrss` for the worker's peak RSS
in KiB. It does not measure the Python orchestrator. RSS includes runtime/library
pages, load buffers, validation scratch and setup; save/conversion RSS is a
whole-process peak, **not** an incremental operation allocation. Do not subtract
independent process peaks to estimate model size. RSS varies with mapping and
allocator behavior. Packed memory advantages must be assessed from these numbers,
not inferred solely from the representation.

Untimed upstream roundtrips and checked/unchecked packed conversions verify byte
parity. Every timed save/roundtrip output is compared byte-for-byte afterward.
No failed sample is retained as a successful timing. Inspect failures before
starting a new run; output directories are never overwritten.

Outputs include archived library sources, harness, corpus, compiler/binary/source
provenance (`build.json`), every sample (`samples.json`), medians and min/max
(`summary.json`), and a full table (`tables.md`). Preserve the complete run with
published findings. The checked-in report also includes samples and manifests;
large binaries/checkpoints remain in the local run archive.
