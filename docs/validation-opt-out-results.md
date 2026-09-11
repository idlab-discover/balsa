# Validation opt-out: full Treelite comparison — 2026-09-11

The full controlled comparison was rerun with Balsa's automatic model validation
**disabled** during timed encode/decode calls. Native Treelite and its Python
wrapper retain their standard behavior. Balsa's input bounds, format checks and
parser limits remain active; this is not a claim that the engines perform
identical checks. See [the validation policy](validation-policy.md).

## Findings

Against native Treelite 4.6.1, Balsa has lower encode latency on **all 12
checkpoints**, by **7.3–45.1%**. Decode latency is lower on **10 of 12**
checkpoints, by **8.5–16.7%**; the large random forest overlaps parity, and
large XGBoost remains **4.3% slower**. These classifications use the reported
95% bootstrap intervals, not just the point estimates.

Balsa has lower latency than Treelite's Python API in **all 24** encode/decode
comparisons. Decode latency is 8.7–49.9% lower and encode latency 6.4–50.0% lower.
These are per-case ranges, not an aggregate score or a prediction for arbitrary
forests.

For the two 100,020-node forests:

| Forest | Decode Balsa / native | Encode Balsa / native |
| --- | ---: | ---: |
| XGBoost | 6.320 / 6.059 ms | 2.686 / 4.408 ms |
| RF multioutput | 7.738 / 7.848 ms | 2.747 / 5.001 ms |

This sweep compares the current opt-out configuration with freshly measured
Treelite. It does not isolate the effect of disabling validation from preceding
Balsa optimizations: there is no checked-Balsa arm in this 144-job matrix.
Earlier checked/unchecked measurements are recorded in the policy document.

## Measurement contract

- Balsa commit `b2765e8`, Mojo 1.0.0, release `-O3` compilation.
- Treelite 4.6.1 from the pinned benchmark environment for both references;
  native C ABI worker linked to the wheel's library, not the sibling checkout.
  The native C++ and Python worker sources were copied unchanged from the
  preceding controlled harness.
- AMD Ryzen 9 5950X, CPU 14 pinned (SMT sibling 30), powersave governor,
  `amd-pstate-epp`, no CPU isolation or system tuning changes.
- Same 12 fixture/scaled checkpoints, encode and decode, three engines, and two
  blocks with reversed engine order: **144 completed pyperf jobs**, in
  **16.2 minutes**. Case/operation order uses the original seed, 1729.
- Each job uses three pyperf worker processes, five measured values per process,
  two pyperf warmups, and calibration to at least 0.1 seconds per measured batch.
  Across both blocks: six process groups and **30 measured batches per
  engine/checkpoint/operation**, totaling **2,160 measured batches**.
- Each codec subprocess performs eight operation-specific warmup calls. Startup,
  file I/O, setup, warmup, and validation/parity checks are outside the reported
  interval. Required input/output ownership copies and output/model destruction
  are inside it. Worker checksums are verified throughout.
- Only Balsa's timed codec helpers pass `ValidationOptions(enabled=False)`.
  Setup still uses default validated decode/encode and requires byte-exact
  roundtrip parity. Explicit validation diagnostics remain enabled.
- Corpus hashes, sample counts, affinity and binary hashes were checked by the
  analysis. No samples were discarded, and no jobs needed rerunning.

## All results

Latencies are means of process means in microseconds. Balsa/native ratios below
one favor Balsa. Intervals are 95% bootstrap estimates from 5,000 resamples of
process means within each block; they quantify sampling uncertainty rather than
prove formal equivalence or eliminate desktop system noise.

| Checkpoint / operation | Nodes | Balsa µs | Native Treelite µs | Python Treelite µs | Balsa/native [95% CI] |
| --- | ---: | ---: | ---: | ---: | ---: |
| catboost_numeric_regression/decode | 60 | 2.75 | 3.04 | 5.49 | 0.903 [0.899, 0.907] |
| catboost_numeric_regression/encode | 60 | 1.81 | 1.95 | 3.23 | 0.927 [0.901, 0.946] |
| lightgbm_categorical/decode | 26 | 3.17 | 3.47 | 5.85 | 0.915 [0.910, 0.919] |
| lightgbm_categorical/encode | 26 | 1.76 | 2.15 | 3.25 | 0.821 [0.758, 0.858] |
| sklearn_extra_multioutput_classification/decode | 54 | 3.55 | 3.96 | 6.37 | 0.896 [0.875, 0.916] |
| sklearn_extra_multioutput_classification/encode | 54 | 1.82 | 2.27 | 3.41 | 0.803 [0.785, 0.815] |
| sklearn_gradient_binary/decode | 60 | 3.49 | 3.85 | 6.29 | 0.907 [0.898, 0.914] |
| sklearn_gradient_binary/encode | 60 | 1.90 | 2.18 | 3.35 | 0.869 [0.851, 0.901] |
| sklearn_hist_missing_regression/decode | 60 | 3.22 | 3.81 | 6.15 | 0.846 [0.821, 0.868] |
| sklearn_hist_missing_regression/encode | 60 | 1.86 | 2.11 | 3.40 | 0.882 [0.862, 0.903] |
| sklearn_rf_multiclass/decode | 50 | 3.54 | 3.89 | 6.35 | 0.911 [0.896, 0.925] |
| sklearn_rf_multiclass/encode | 50 | 1.69 | 2.26 | 3.38 | 0.747 [0.739, 0.756] |
| sklearn_rf_multioutput_regression/decode | 60 | 3.52 | 3.92 | 6.41 | 0.898 [0.893, 0.903] |
| sklearn_rf_multioutput_regression/encode | 60 | 1.93 | 2.28 | 3.49 | 0.848 [0.815, 0.889] |
| sklearn_rf_multioutput_regression_x16/decode | 960 | 50.86 | 61.06 | 66.90 | 0.833 [0.828, 0.838] |
| sklearn_rf_multioutput_regression_x16/encode | 960 | 26.26 | 31.40 | 31.09 | 0.836 [0.827, 0.843] |
| sklearn_rf_multioutput_regression_x1667/decode | 100,020 | 7,737.79 | 7,848.31 | 8,473.63 | 0.986 [0.961, 1.010] |
| sklearn_rf_multioutput_regression_x1667/encode | 100,020 | 2,746.78 | 5,001.00 | 4,867.36 | 0.549 [0.548, 0.551] |
| xgboost_regression/decode | 60 | 3.12 | 3.42 | 5.89 | 0.911 [0.908, 0.914] |
| xgboost_regression/encode | 60 | 1.77 | 2.09 | 3.25 | 0.847 [0.844, 0.851] |
| xgboost_regression_x16/decode | 960 | 45.70 | 53.51 | 59.54 | 0.854 [0.835, 0.884] |
| xgboost_regression_x16/encode | 960 | 26.16 | 29.04 | 27.93 | 0.901 [0.890, 0.911] |
| xgboost_regression_x1667/decode | 100,020 | 6,319.64 | 6,059.38 | 7,002.07 | 1.043 [1.035, 1.052] |
| xgboost_regression_x1667/encode | 100,020 | 2,686.12 | 4,407.94 | 4,076.35 | 0.609 [0.595, 0.625] |

## Stability and practical limits

Pyperf emitted warnings for **83 of 144 jobs**: 75 reported insufficient samples
to establish variation below 1%, while eight reported elevated dispersion or
extreme values. All remain in the analysis. The largest coefficient of variation
among the six process means was **11.6%** (Python Treelite, histogram-regression
encode). The largest Balsa value was **6.2%** (small RF multioutput encode).

For every case/operation/reference, the point estimate favored the same engine
in both blocks; none crossed a ratio of one between blocks. Nevertheless, the
large RF decode interval spans parity, so its 1.4% lower point estimate should
not be reported as an established win. Large XGBoost's approximately 4.3%
decode deficit persists in both blocks and its interval excludes parity.

This corpus includes eight small trained-framework fixtures and two expanded
sizes each of XGBoost and RF multioutput. The large models repeat many small
trees. Results do not establish parity for few-large-tree, deep, or dominant-tree
shapes; the earlier profiling report separately explored those shapes.

## Evidence and reproduction

The isolated experiment is in the git-ignored
`benchmarking/validation-opt-out/` directory. It contains the unchanged Treelite
workers, adapted Balsa worker, controlled runner, build metadata, environment
and source/binary hashes, preflight verification log, progress log, and all
per-job pyperf JSON/log files. Historical experiment directories were retained.
These local harness files are absent from fresh clones, like the original
controlled experiment's harness.

The Balsa worker adaptation imports `ValidationOptions` and passes
`ValidationOptions(enabled=False)` in `decode_once`, `encode_once`, and the
unused-in-this-sweep roundtrip helper. Its `execute` setup remains validated.
The runner metadata explicitly records the opt-out. Other timing settings and
workers are unchanged from `benchmarking/CONTROLLED.md`.

Commands, run from the repository root in the existing experiment workspace:

```sh
pixi run -e benchmark python benchmarking/validation-opt-out/build.py
pixi run -e benchmark python benchmarking/validation-opt-out/verify.py
# Choose a fresh output directory; the runner refuses to overwrite results.
pixi run -e benchmark python benchmarking/validation-opt-out/controlled.py --output benchmarking/validation-opt-out/rerun --cpu 14
pixi run -e benchmark python benchmarking/validation-opt-out/analyze_controlled.py benchmarking/validation-opt-out/rerun
```

The recorded run is `results/`; `summary.json` retains every engine's mean,
median, p95 batch value, process variation, block means, and ratio intervals.
`quality.json` records completeness checks, all warning messages, interval
classifications and per-block ratios. The completed preflight passed all 12
checkpoints across Balsa, native Treelite and Python Treelite.
