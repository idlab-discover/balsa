# Packed checkpoint storage

Default load/decode representation since Balsa 0.2.0.
It targets frequent loading/saving of trained models with uncommon editing.

## Interface

Import `balsa.packed` as a module. It provides typed `decode`, `load`, `encode`
and `save`, plus precision-discovering `decode_auto` and `load_auto`. The auto
functions return `AnyPackedModel`, a variant of float32 and float64 owners;
`encode` and `save` accept that variant directly.

Typed `PackedModel` provides:

- `num_trees()`, `num_features()`, `postprocessor_name()`, `attributes_text()`.
- `base_scores()`, `target_ids()`, `class_ids()` as immutable borrowed spans.
- `tree(i)` for typed array and extension views. Arrays support `len`, checked
  indexing, and `to_list()` for independent storage.
- `validate()` for explicit semantic validation, including after opt-out loads.
- `to_model()` for an independent editable model, validating by default.

The fields beginning with `_` are implementation details and must not be changed.
Builders and the ordinary codec continue to use the editable `Model`.

## Storage and ownership

Tree payloads remain in an owned copy of the original wire buffer. One offset
index locates the trees; model-header fields are decoded into ordinary owned
arrays. Tree lookup scans the selected tree's field headers, then returns
origin-tracked views without allocating payload lists. Extension lookup scans
preceding records in that extension slot.

This is a wire-backed representation, not a native aligned arena. Its typed
array access uses explicitly byte-aligned loads and little-endian conversion.
It does not expose typed pointers or typed spans into potentially unaligned
wire payloads. Array indexing is checked. Views cannot outlive their owner;
obtaining an editable list or model requires an explicit copy.

`decode(data^)` consumes and retains the supplied List. `decode(Span(data))`
copies input once because the result must own it. File loading retains the
buffer read from disk. Encoding copies preserved checkpoint bytes; saving
writes them directly without constructing an intermediate output buffer.

## Validation

Every load scans the entire wire structure with version, precision, byte,
array-element, extension, tree-count and total-node limits. Truncations and
trailing bytes are rejected even when semantic validation is disabled.

Semantic validation is disabled by default; pass
`ValidationOptions(enabled=True)` for safety-first loading. It shares the editable codec's
metadata and topology rules, decoding one temporary tree at a time into reused
capacities. It never constructs an editable forest, but it still copies tree
fields during this validation pass and needs scratch space for the largest
tree seen. This implementation uses one validation worker; `max_workers` is
treated as a cap. There is no inference or structural-editing implementation.

`encode` and `save` emit preserved bytes without repeating semantic validation.
If loading was unchecked (the default), that policy is
also reflected in subsequent saving: structurally readable but semantically
invalid input can be preserved. Explicit `model.validate()` always validates.

## Verification and measurement

Run `pixi run check` for ordinary and packed runtime tests. Packed tests cover
both precisions, every tree-array field, extension payloads, owner moves,
independent editable conversion, index bounds, truncated prefixes, malformed
input diagnostics, and deterministic byte corruptions. The fixtures in
`tests/compile_fail/` must fail compilation: escaping a tree view from its
owner, and mutating a packed array element.

Run `pixi run -e benchmark python tools/benchmark_packed.py` for five shuffled
subprocess batches on CPU 14, with eight warmups and at least 100 timed calls.
It uses the existing 12-model corpus and four synthetic shapes when present.
Raw results and source/compiler provenance are retained in `benchmarking/packed`.

Fresh decode timings include model destruction. Both consuming decoders include
the input ownership copy needed to retain the benchmark's source buffer. The
ordinary borrowed decoder is reported separately and avoids that copy. All
validation-on decode measurements use one worker. Encoding is measured with
validation off for both representations and includes output destruction.
Packed encoding copies a preserved serialization; ordinary encoding rebuilds
it from editable fields. These operations have different capabilities, and the
results must not be described as a general-purpose encoder speedup.

### Initial local results

Median milliseconds per fresh decode, including destruction. The consuming
columns both include an input copy; validation uses one worker when enabled.

| Model | Validation | Editable consuming | Editable borrowed | Packed consuming |
| --- | --- | ---: | ---: | ---: |
| Large XGBoost | Off | 7.049 | 6.590 | 1.156 |
| Large RF | Off | 8.238 | 7.465 | 1.209 |
| Large XGBoost | On | 8.728 | 8.243 | 5.071 |
| Large RF | On | 10.187 | 9.399 | 5.095 |
| Few large trees | On | 1.925 | 1.778 | 1.655 |
| Dominant tree | On | 3.887 | 3.759 | 2.735 |

All 16 validation-off medians improved. With validation on, 15 improved and the
small RF multiclass case regressed. A targeted seven-batch repeat with 20,000
calls per batch measured 4.60 microseconds for editable consuming, 4.45 for
editable borrowed, and 4.79 for packed consuming: about 4% slower than editable
consuming. These are historical experiment results; 0.2 adopts unchecked packed storage
as the default based on the matched unchecked measurements. Raw repeat data is in
`benchmarking/packed/multiclass-repeat.txt`.

Without revalidation, rebuilding the large XGBoost/RF serializations took
2.534/2.653 ms; copying their preserved packed serializations took 0.155/0.196 ms.
Direct file saving was not timed. These are local exploratory measurements;
they do not establish native Treelite parity or statistical significance.
