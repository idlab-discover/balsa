# Larger trained forests: file I/O, conversion and peak memory

Measured on rgbcore, Linux x86-64 / AMD Ryzen 9 5950X, CPU 14, on 2026-09-18.
Balsa library revision: `b933b55f409d155190b3df25e0763ddcbd66fe56`.
Mojo 1.0.0 (`ed45d567`), `-O3`, native Treelite 4.6.1 linked from its pinned
wheel. Files were on the workspace’s ext4 filesystem (`/dev/nvme1n1p3`).
Exact compiler, library and binary hashes are in [build provenance](storage-2026-09-18/build.json).

Packed Balsa loads these files faster than native Treelite in the operation
measurements, including when Balsa semantic validation is enabled. However,
**Treelite has the lowest whole-process peak RSS**. Packed Balsa saves memory
relative to editable Balsa, not relative to Treelite on this corpus. Process
launch/setup overhead also materially narrows the latency benefit.

## Corpus and verification

These models contain distinct trained trees, replacing the earlier repeated-tree
scale probes. All use 30,000 seeded generated rows and 24 numeric features;
they are larger workload probes, not production datasets. Framework predictions
and Treelite predictions agree on 100 verification rows per model. See the
[corpus manifest](storage-2026-09-18/corpus.json) for parameters, versions and hashes.

| Model | Trees | Nodes | File MiB | Precision |
| --- | ---: | ---: | ---: | --- |
| Random forest, two regression targets | 128 | 262,016 | 24.76 | float64 |
| Extra trees, four classes | 128 | 262,016 | 26.76 | float64 |
| XGBoost regression | 384 | 151,986 | 10.80 | float32 |

All 357 measured samples completed (51 cells × seven shuffled repetitions).
Every save/roundtrip output matched its input bytes. Separate untimed checks
verified upstream roundtrips and packed-to-editable conversion with validation
both on and off. No worker warnings, failures or sample exclusions occurred in
the completed run. An earlier attempt stopped before recording a sample because
GNU time was absent; the completed harness uses a native `wait4` launcher.

## File loading

Median milliseconds for the operation itself; parentheses give min–max across
seven fresh processes. Input files are read into the OS page cache before each
worker. Balsa checked measurements use one validation worker; upstream checks
are retained and are not asserted to perform identical work.

| Model | Treelite | Packed off | Packed on | Editable off |
| --- | ---: | ---: | ---: | ---: |
| RF multioutput | 15.477 (15.385–16.139) | 3.601 (3.489–3.732) | 8.766 (8.584–8.971) | 7.014 (6.915–7.245) |
| Extra multiclass | 16.494 (16.307–16.637) | 3.853 (3.679–4.065) | 9.295 (9.072–9.522) | 7.835 (7.347–8.031) |
| XGBoost | 9.295 (8.989–9.555) | 1.792 (1.715–2.205) | 4.747 (4.394–4.894) | 3.709 (3.576–3.858) |

Unchecked packed load operation medians are 4.3–5.2× faster than Treelite;
checked packed medians are 1.8–2.0× faster. These are descriptive ratios on
three local models, not general performance guarantees.

The full process view is less favorable to Balsa. Median launch-through-exit
wall times for **checked packed vs Treelite** are 19.306 vs 21.120 ms (RF),
20.017 vs 22.182 ms (extra trees), and **15.345 vs 14.263 ms (XGBoost)**.
Thus checked packed XGBoost loading wins inside the library but loses when
including worker launch and teardown. Unchecked editable XGBoost has the same
reversal: 3.709 vs 9.295 ms operation time, but 14.619 vs 14.263 ms process wall.
Wall time includes setup, runtime loading, destruction and measurement launcher
overhead; subtracting it from operation time does not isolate startup cost.

## Peak RSS during file loading

Median whole-worker peak resident memory in MiB, collected by Linux `wait4`.
The Python orchestrator and model training are not included.

| Model | Treelite | Packed off | Packed on | Editable off | Editable on |
| --- | ---: | ---: | ---: | ---: | ---: |
| RF multioutput | 29.67 | 40.03 | 40.22 | 66.35 | 66.34 |
| Extra multiclass | 31.61 | 42.19 | 42.02 | 70.44 | 70.34 |
| XGBoost | 18.93 | 26.52 | 26.52 | 40.55 | 40.55 |

Unchecked packed peak RSS is about 35–40% lower than editable Balsa, but about
33–40% higher than native Treelite. This includes runtimes, mapped library pages,
input buffers, allocated fields and scratch space. It does not establish which
allocation causes the difference, and independent process peaks must not be
subtracted to infer model-only storage. Investigating the remaining memory cost
is a concrete optimization opportunity if deployment footprint matters.

## Saving and conversion

Median operation milliseconds. Writes include file close but **not fsync**:
these are buffered filesystem writes, not durable-storage latency. Packed save
preserves bytes; editable and Treelite save serialize model fields.

| Model | Treelite save | Packed save (unchecked setup) | Editable save off | Editable save on | Conversion off | Conversion on |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| RF multioutput | 15.923 | 5.627 | 8.632 | 12.996 | 3.761 | 7.821 |
| Extra multiclass | 16.517 | 6.104 | 9.303 | 13.812 | 4.062 | 8.280 |
| XGBoost | 8.902 | 2.609 | 4.113 | 6.204 | 2.009 | 4.256 |

Conversion starts with an unchecked packed owner and retains it alongside the
editable result. Checked conversion is the public `to_model()` policy, here
with an explicit one-worker cap. It is a material cost: 4.3–8.3 ms in this corpus.
Loading packed and immediately converting should not be assumed faster than
loading editable directly. Conversion worker peak RSS reaches 40.5–70.4 MiB;
these are whole-process peaks including setup, not incremental allocations.

Editable save worker peaks reach 52.3–92.5 MiB; packed save remains around
26.5–42.3 MiB, while Treelite remains around 19.0–31.7 MiB. Native Treelite's
file API streams through its serializer; these file measurements should not be
mixed with the earlier owned-byte in-memory encoder comparison.

Median combined load/save operation times are:

| Model | Treelite | Packed off | Packed checked load | Editable off | Editable checked load + save |
| --- | ---: | ---: | ---: | ---: | ---: |
| RF multioutput | 31.087 | 9.177 | 14.092 | 16.002 | 24.149 |
| Extra multiclass | 32.728 | 9.901 | 15.034 | 16.956 | 26.209 |
| XGBoost | 18.152 | 4.373 | 7.111 | 7.826 | 12.027 |

Packed output never revalidates. Checked editable roundtrip validates twice.
These are explicit workload policies, not identical validation contracts.

## Reproduction, evidence and limits

Use the [storage workload harness](../../tools/storage_workload/README.md).
It defaults to the current commit; `--revision` explicitly selects older source.
The measured harness and source snapshots are preserved with the run.

- [Verification and archive checksum](storage-2026-09-18/verification.json).
- [All samples](storage-2026-09-18/samples.json), including process wall and peak RSS.
- [Summary with medians and min/max](storage-2026-09-18/summary.json).
- [Complete measurement table](storage-2026-09-18/tables.md).
- [Build provenance](storage-2026-09-18/build.json) and [corpus manifest](storage-2026-09-18/corpus.json).

The complete local run is `benchmarking/storage-2026-09-18-v2/`, including
source, harness, binaries and checkpoints; preserve its archive when sharing
results. JSON evidence is checked in, but the larger binaries/checkpoints are
not. The worker compilation durations in build metadata are incidental timings,
not a controlled compilation-performance comparison.

This study measures first-use operations in fresh processes with warm input
cache, rather than warmed in-memory codec loops. Timed load/conversion excludes
result destruction; process wall includes it. Seven observations per cell are
not a tail-latency study or formal statistical significance test. No global
cache dropping or host tuning was performed. Models have independently trained
trees, but broader deployment evidence still needs production data and distinct
hardware. Cold media, durable writes, concurrent workloads and intensive tree
inspection remain unmeasured. No macOS or Linux ARM claim follows from this run.
