# Historical Balsa performance and completion assessment

This is the **2026-09-15 pre-release assessment**, preserved with its original
revision boundaries and findings. It is not the current release checklist.
Since this run, 0.2.0 promoted packed storage, changed validation defaults,
added CI and Conda packaging, and selected Apache-2.0 licensing. See
[current release status](../release-status.md), [0.2 migration](../release-0.2.0.md),
and [larger storage workloads](storage-workload-2026-09-18.md).
Any “default”, “main”, “experimental”, or outstanding-item statements below
refer to the historical revisions, not current HEAD.

Report date: 2026-09-15. The format-only acceptance checks pass. Balsa is close
to a first scoped release; remaining release housekeeping should be separated
from optional performance work and the packed-storage promotion decision.

## Findings

All 432 controlled pyperf cells completed in 46.0 minutes, retaining 6,480
measured batches. [Complete results](final-report-tables.md) include every
latency, native ratio, descriptive interval, and run-order comparison.

For the editable codec against native Treelite, the serial comparison is:

| Operation / semantic validation | Faster cases | Slower cases | Inconsistent cases |
|---|---:|---:|---:|
| Encode / off | 16 | 0 | 0 |
| Encode / on | 2 | 13 | 1 |
| Consuming decode / off | 15 | 1 | 0 |
| Consuming decode / on | 1 | 15 | 0 |
| Borrowed decode / off | 15 | 1 | 0 |
| Borrowed decode / on | 1 | 15 | 0 |

These are descriptive classifications with agreement in both run orders, not
a claim of statistical significance across arbitrary models. Validation-on
means one worker in this table; the default-policy supplement is below.

The unchecked editable encoder has 8.5–87.2% lower latency across the 16 cases;
restricting the comparison to the 12 framework/scaled cases gives 17.4–51.7%.
Checked encoding wins only on the two large repeated forests; the other
cases are 13 slower and one order-sensitive result (dominant-tree encode).
The default checked codec is **not universally faster than Treelite**.
The two engines also perform different validation work.

Unchecked consuming decode wins on 11 of 12 framework/scaled cases and all
four synthetic shapes. Large XGBoost remains slower: 6.447 ms versus native
5.899 ms, or 9.3%. Borrowing input reduces it to 6.224 ms, still 5.5% slower.
Those effect sizes vary across blocks: consuming is 5.4% / 13.2% slower;
borrowed is 1.8% / 9.3% slower. The narrow within-block bootstrap intervals
must not be interpreted as eliminating this run-order variation.

Against Treelite's Python API, unchecked editable decoding is faster on all
16 cases. Unchecked encoding is faster on 15, with leaf-only encoding
overlapping parity. Checked consuming decode is faster on 11, slower on four,
and overlaps on one; checked encoding is faster on ten and slower on six.
Python overhead is therefore not a substitute for the native comparison.

### Large-forest storage results

Both forests have 6,668 trees / 100,020 nodes. Times below are milliseconds;
validation-on uses one worker. Lower is better.

| Operation / representation | XGBoost | RF multioutput |
|---|---:|---:|
| Native Treelite decode | 5.899 | 8.094 |
| Editable consuming decode, on / off | 7.973 / 6.447 | 10.128 / 7.618 |
| Editable borrowed decode, on / off | 7.731 / 6.224 | 8.722 / 6.868 |
| Packed consuming decode, on / off | 4.937 / 1.139 | 5.152 / 1.170 |
| Native Treelite encode, independently owned output | 4.490 | 5.174 |
| Editable encode, on / off | 4.065 / 2.501 | 4.178 / 2.501 |
| Packed preserved-byte copy, no timed revalidation | 0.137 | 0.172 |

Checked packed loading has 16.3% / 36.4% lower latency than native Treelite on
these two forests, and 38.1% / 49.1% lower latency than checked editable
consuming decode. Across all 16 cases, checked packed decode is faster than
checked editable decode on 14, overlaps on CatBoost, and is 11.3% slower on
small RF multiclass (4.831 versus 4.341 µs). Against native Treelite, checked
packed decode wins on nine cases and loses on seven.

Unchecked packed decode is faster than native Treelite on all 16 cases, with
69.4–86.9% lower latency, but semantic validation is not being performed.
Packed-copy's much lower save-side cost is useful for preserved checkpoints;
it must not be presented as a general-purpose serialization improvement.

### Tree shape and default validation matter

The few-large-trees case makes the validation cost especially visible:
editable consuming decode takes 1.827 ms checked versus 0.371 ms unchecked;
native Treelite takes 0.578 ms. Checked packed decode still takes 1.709 ms,
about 2.96× the native time. Borrowed unchecked editable decode takes 0.245 ms.
On encode, the same model takes 1.575 ms checked versus 0.183 ms unchecked.
Packing does not remove semantic tree validation, and no single aggregate
score would describe these shape-dependent costs adequately.

With CPUs 14–17 available, Balsa's actual default four-worker validation policy
still has slower large-forest decode and faster encode than the independently
remeasured native reference:

| Forest / operation | Default Balsa ms | Native ms | Balsa/native [95% descriptive interval] |
|---|---:|---:|---|
| XGBoost decode | 9.873 | 7.751 | 1.274 [1.186–1.361] |
| RF decode | 11.151 | 9.314 | 1.197 [1.153–1.243] |
| XGBoost encode | 4.032 | 5.238 | 0.770 [0.736–0.797] |
| RF encode | 4.149 | 6.015 | 0.690 [0.680–0.700] |

This is a separate affinity configuration, not a paired measurement of the
benefit of four workers over one. Do not subtract its absolute times from the
single-core table to estimate parallel speedup.

## Scope and revision boundaries

Balsa's first milestone is a native Mojo implementation of the Treelite v4
checkpoint format: load, inspect, edit, validate, and save model fields. It is
not an inference engine or a replacement for framework training/import APIs.
The supported precision pairs are float32/float32 and float64/float64. Producer
compatibility is verified against Treelite 4.6.1, not every v4 producer release.

The comparison pins two separate revisions:

- Main `fbba1fc141efde7d75161141b6f6633843cde0e2`: editable model, borrowed-input
  decoding, reusable destination decoding, and the optimized bounded encoder.
- Experimental `e7f11c0ac1f437cba364e6cb95eee2f9bbf490b9`: owned packed checkpoint
  storage on `feature/packed-checkpoints`. It has not been merged into main.

The experiment matches the predominantly load/save workload described by the
user. It stores original tree payload bytes with an offset index, exposes
read-only views, and supports an explicit copy to an editable model. Semantic
validation reuses one scratch tree and currently runs serially. Packed saving
emits preserved bytes without another semantic validation pass. See
[packed storage](../packed-storage.md) for the complete ownership and policy
contract.

## What the benchmark measures

The primary reference is native Treelite 4.6.1 through its C ABI, linked to the
pinned wheel library. The Python API is measured separately. Native encoding
includes a copy from Treelite's thread-local output into independently owned
bytes, matching the ownership contract of Balsa's encoder and Treelite's Python
API. This is not the minimum possible latency of using Treelite's transient
output buffer directly.

Editable Balsa has explicit semantic-validation-on and -off entries. Borrowed
decode has its own pair of entries because it avoids the copy needed to keep
the benchmark's source buffer while calling a consuming API. Packed decode
also has on/off entries. Bounds, format, resource, and sizing checks are not
disabled by semantic validation opt-out. Treelite's normal checks are retained;
the two libraries are not claimed to perform identical validation work.

Packed-copy is reported separately: it copies an existing serialization and
does not serialize edited fields. Its setup validates the stored model, but
the timed save-side operation does not revalidate. It must not be counted as
an ordinary encoder win.

The corpus has eight small trained-framework fixtures, four repeated-forest
scale probes, and four synthetic shape probes. The two largest repeated forests
have 6,668 trees / 100,020 nodes each. Synthetic cases test 4,096 leaf-only trees,
an uneven forest, 128 larger trees, and a forest dominated by one 65,535-node
tree. Large repeated forests are not independently trained large models.

All timings are warmed in-memory codec calls including fresh result
destruction. File reading, process startup, setup, and warmups are excluded.
Disk load/save latency, peak resident memory, individual-call tail latency,
and training-to-checkpoint conversion are not measured. Reusable `decode_into`
is intentionally outside this fresh-load comparison. Packed storage's memory
advantage is an architectural expectation, not quantified by these timings.

## Reproducibility and uncertainty

The run uses Mojo 1.0.0 (`ed45d567`), `-O3`, native GCC 16.2.1, pyperf 2.10.0,
and an AMD Ryzen 9 5950X on Linux x86-64. The serial matrix is pinned to CPU 14;
the separate default-four-worker validation supplement has CPUs 14–17
available. The host retains its `amd-pstate-epp` powersave configuration with
boost enabled; cores are not isolated and no system tuning was applied.

Two reversed-engine-order blocks cover 416 serial cells and 16 default-policy
cells. Each cell has three pyperf process groups, five values per group, two
pyperf warmups, and calibrated batches targeting at least 100 ms. Each value
comes from a fresh codec subprocess with eight internal warmups. Across both
blocks, an engine/case/operation has six groups and 30 measured batches.

The center is the mean of process-group means. Descriptive 95% ratio intervals
use 5,000 bootstrap resamples within each block. Directional classifications
also require both block ratios to agree. These intervals do not correct for
multiple comparisons or eliminate host drift. All warnings and samples remain
in the analysis. Batch p95 values are not request-latency percentiles.

Pyperf warned on 253 of 432 cells: 235 only reported insufficient samples for
its under-1%-variation criterion; 18 reported elevated dispersion or extreme
values. The largest CV among the six process-group means was 11.4% for
unchecked editable histogram-regression decode; the default-policy large
XGBoost decode CV was 9.2%. Three comparisons against native crossed a ratio
of one between blocks: checked editable dominant-tree encode, Python
few-large-tree encode, and Python leaf-only decode. They are explicitly
classified as inconsistent/overlapping, even where a bootstrap interval alone
excludes one. No failed jobs, reruns, or sample exclusions were needed.

The reusable harness and full methodology are in
[tools/pyperf_codec](../../tools/pyperf_codec/README.md). Local raw evidence is in
`benchmarking/final-2026-09-15/`: source snapshots, build/library/corpus hashes,
preflight checks, schedule, per-cell pyperf JSON/logs, and analysis output. This
directory is git-ignored and needs separate preservation when publishing the
report. Earlier runs are retained; their timings are not mixed into this run.

## Completion assessment

The format-only MVP and a public release are different completion criteria.
The implemented codec covers both precision pairs, categories, vector leaves,
multi-target metadata, statistics, postprocessor fields, exact floating-point
bits, opaque attributes, and unknown extension records. Negative tests cover
malformed/truncated input, topology, limits, and deterministic corruptions.
Acceptance also requires byte-exact oracle roundtrips and upstream loading of
Mojo-created checkpoints. Fresh checks after the timing run passed:

- Build, package, CLI smoke, construction example, and all 46 runtime tests
  (32 core, eight framework, six packed).
- Reproducible regeneration of all 14 synthetic Treelite 4.6.1 fixtures.
- All 14 byte-exact synthetic roundtrips and upstream field comparisons,
  including Mojo-created models, builders, and extension records.
- All eight saved trained-framework checkpoints: byte-exact roundtrip and
  upstream fields. Framework retraining/prediction regeneration was not rerun.
- Generated API documentation check.
- Both packed compile-fail checks. Diagnostics were inspected: the escaping
  view fails because its origin belongs to the local owner; element assignment
  fails because the packed view is immutable.
- Five deterministic tests of the benchmark analysis bookkeeping.

These checks ran against `e7f11c0`; main remains at `fbba1fc`. Acceptance logs,
commands, and source hashes are retained alongside the timing evidence.

Concrete release decisions and housekeeping still visible in the repository:

| Item | Assessment / next action |
|---|---|
| Automated acceptance | No checked-in CI workflow was found. Put the existing build, package, tests, and oracle checks behind a repeatable release gate. |
| License selection | `THIRD_PARTY_NOTICES.md` explicitly leaves the original Balsa contributions' license unselected. The owner needs to select it before publication. |
| Public documentation | Several API/research documents are untracked. Attribution and source docstrings refer to a missing public `docs/mvp-plan.md`; the current plan is private/ignored. Resolve the public documentation set and links. |
| Compatibility claims | Keep claims scoped to the tested producer and Linux x86-64 toolchain. Other producer releases/platforms need separate fixtures and testing if promised. |
| Packed promotion | Optional experiment, not a prerequisite for declaring the editable format MVP complete. Decide whether it ships as experimental, gets more workload evidence, or stays on its branch. |
| Deployment workload evidence | Before promising storage-workload speedups broadly, measure representative independently trained large models, actual file I/O, and peak memory. These are absent from the current codec-only comparison. |

Inference, Python buffer-frame interoperability, native framework importers,
and portable packaging are not silently added to the format MVP. Remaining
optimization ideas, including an upstream allocator report, are not by
themselves evidence that the format implementation is unfinished.

My assessment: the format-only MVP meets its tested acceptance contract.
If completion means a first scoped Mojo release, prioritize the release gate,
public documentation, and owner decisions above further micro-optimization.
If completion instead requires default-validated performance at least matching
native Treelite on every shape, this run shows that criterion is not met.
Keep packed storage experimental until its promotion is an explicit decision;
the load/save results support pursuing it, not silently replacing editable
storage or merging its branch.
