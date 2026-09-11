# Measuring Balsa and Treelite checkpoint performance

Proposed next step; no performance results are claimed yet.

Use two persistent runners over exactly the same checkpoint corpus: a compiled
Mojo executable calling Balsa, and a Python process calling the pinned Treelite
wheel. Time operations inside each runner after warmup. Process startup,
imports, Mojo compilation, model training and framework conversion belong
outside timed regions. This measures the public Mojo and Python interfaces;
a separate C++ runner would be needed to isolate Treelite's core from Python
call overhead.

## Operations

| Measurement | Balsa | Treelite |
| --- | --- | --- |
| Decode resident bytes | `decode[dtype]` and separately `decode_auto` | `Model.deserialize_bytes` |
| Encode a resident model | `encode(model)` | `model.serialize_bytes()` |
| Whole codec roundtrip | Decode then encode | Deserialize then serialize |
| Filesystem load/save | `load` / `save` | `Model.deserialize` / `model.serialize` |
| Validation cost, diagnostic | `validate(model)` | No equivalent standalone Python operation |

Keep in-memory codec measurements separate from filesystem measurements. Report
warm-page-cache file I/O first; any cold-cache experiment needs a documented,
controlled cache procedure. A successful save does not imply an fsync, so do
not describe ordinary save timing as durable-storage latency.

Balsa validates during decode and encode. Report the default safe behavior;
Treelite's checks differ, so these are not identical validation workloads.
Standalone validation timing helps identify cost but should not simply be
subtracted from the other measurements.

Balsa decoding consumes owned bytes. Prepare fresh inputs outside the timed
region for decode-only timing, and separately measure copy-plus-decode when
that matches the application's repeated-use scenario. State where input copies,
output allocation, and object destruction occur. Both libraries should allocate
fresh outputs; neither runner should accumulate live models between iterations.
Keep a small result checksum and validate roundtrips outside timing.

## Corpus and reported metrics

Start with the eight real-framework fixtures for correctness and small-model
latency. They are only 3–7 KiB each and cannot establish large-model throughput.
Add deterministic ensembles at roughly 1,000, 100,000 and 1,000,000 total nodes,
covering shallow/wide versus deep trees, float32/float64, scalar/vector leaves,
and categorical payloads. Record exact bytes, trees, nodes, precision and vector
width; these all affect codec work. Use explicit Balsa `Limits` large enough
for each corpus entry and record them.

Run warmups, then enough iterations per sample to amortize timer overhead
(e.g. at least 100 ms), collecting at least 30 samples in several fresh runs.
Use one CPU/thread configuration, alternate runner order and record CPU, OS,
compiler, library versions and checkpoint hashes. Avoid running the two runners
concurrently.

Report median and p95 latency (label batched samples as such), MiB/s, nodes/s,
and peak RSS measured separately per workload. For RSS, report both the idle
runtime baseline and the observed peak; Python's baseline differs from Mojo's.
Include absolute timings and the Treelite/Balsa latency ratio for every case,
with the ratio direction clearly labeled. Save samples and metadata as JSON
so future changes can be compared on the same machine and corpus.

For interchange specifically, also report Balsa encode → Treelite decode and
Treelite encode → Balsa decode costs from the component timings. Measure
transport separately if deployment crosses a file, pipe or network; otherwise
transport overhead can hide the format costs being compared.
