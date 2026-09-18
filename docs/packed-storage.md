# Packed checkpoint storage

Default load/decode representation since Balsa 0.2.0.
It targets frequent loading/saving of trained models with uncommon editing.

## Interface

The root `balsa` API uses packed storage for `decode`, `load`, `decode_auto` and
`load_auto`; the same operations are available from `balsa.packed`. Auto functions
return `AnyPackedModel`, a variant of float32 and float64 owners. Root `encode`
and `save` accept packed and editable models and their precision variants.

Typed `PackedModel` provides:

- `num_trees()`, `num_features()`, `postprocessor_name()`, `attributes_text()`.
- `base_scores()`, `target_ids()`, `class_ids()` as immutable borrowed spans.
- `tree(i)` for typed array and extension views. Arrays support `len`, checked
  indexing, and `to_list()` for independent storage.
- `validate()` for explicit semantic validation, including after unchecked loads.
- `to_model()` for an independent editable model, validating by default.

The fields beginning with `_` are implementation details and must not be changed.
Builders and the explicit editable codec continue to use `Model`.

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
`ValidationOptions(enabled=True)` for safety-first loading. It shares the editable
codec's metadata and topology rules, decoding one temporary tree at a time into
reused capacities. It never constructs an editable forest, but it still copies tree
fields during this validation pass and needs scratch space for the largest
tree seen. This implementation uses one validation worker; `max_workers` is
treated as a cap. There is no inference or structural-editing implementation.

`encode` and `save` emit preserved bytes without repeating semantic validation.
Unchecked loading (the default) can therefore preserve semantically invalid
input through saving. Explicit `model.validate()` always validates.

## Verification and measurement

Run `pixi run check` for ordinary and packed runtime tests. Packed tests cover
both precisions, every tree-array field, extension payloads, owner moves,
independent editable conversion, index bounds, truncated prefixes, malformed
input diagnostics, and deterministic byte corruptions. The fixtures in
`tests/compile_fail/` must fail compilation: escaping a tree view from its
owner, and mutating a packed array element.

For in-memory comparisons, use the [controlled codec harness](../tools/pyperf_codec/README.md).
It selects the current commit by default and records explicit historical revisions
when requested. See the [0.2 public API results](benchmarks/release-0.2.0.md)
and [larger storage workload study](benchmarks/storage-workload-2026-09-18.md).
Packed output copies preserved serialization; editable output rebuilds fields.
These operations have different capabilities and should be reported separately.
