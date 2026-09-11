# Balsa: format-only MVP

Balsa implements the Treelite v4 binary checkpoint format in native Mojo.
Its scope is model field storage, loading, inspection, editing, structural
validation and serialization. Inference is out of scope, including reference
prediction and future CPU/GPU execution work.

Keep this first version small: plain typed models and codec functions, without
builders, execution abstractions or a general transport framework.

## Current implementation

| Module | Responsibility |
| --- | --- |
| `model.mojo` | Owned model/tree fields and opaque extensions |
| `wire.mojo` | Bounded little-endian scalar/array encoding and decoding |
| `codec.mojo` | Exact v4 field order and file I/O |
| `validation.mojo` | Field relationships, dimensions and tree structure |

The public operations are `load`, `decode`, `save`, `encode` and `validate`.
Precision is explicit for library callers; the small CLI detects it for
`inspect` and `roundtrip`. Raw fields remain mutable, so encoding validates them.

## Compatibility contract

- Support Float32/Float32 and Float64/Float64 checkpoint storage.
- Read and write every defined v4 field, including categories, leaf vectors,
  multi-target metadata, statistics and postprocessor configuration.
- Preserve floating-point bits, the source version triplet, raw attribute bytes
  and unknown extension records in their original slot/order.
- Reject other major versions, unsupported dtype pairs, malformed structure,
  trailing bytes and allocations exceeding configured limits.
- Treat JSON attributes and optional extension contents as opaque. Their content
  semantics are not validated.
- Verify producer version 4.6.1 only. New models default to that checkpoint
  version; Balsa's package version is separate.

The binary stream is distinct from Treelite's Python buffer frames and its
JSON diagnostic dump. It has no magic string or alignment padding. Arrays carry
UInt64 element counts; strings carry UInt64 byte counts. Optional fields carry
name bytes, element size/count and an opaque payload. The specification requires
little-endian order even though upstream stream primitives use native-memory I/O.

## Acceptance checks

1. Generate small deterministic checkpoints through pinned Treelite 4.6.1.
   Record wheel/artifact hashes, field dumps and independently annotated offsets.
2. Decode and re-encode 14 fixtures byte-for-byte across both precisions,
   numerical/categorical trees, vector leaves, multi-target fields, statistics
   and postprocessor metadata; compare upstream field dumps.
3. Load Mojo-created checkpoints in upstream Treelite, including checkpoints
   containing records in all three extension slots.
4. Exercise malformed counts, lengths, indices, topology and offsets, every
   truncated prefix of a stump, deterministic byte mutations and float bit
   preservation through native tests.
5. Reproduce checks with `pixi run check`, `pixi run -e oracle fixtures-check`
   and `pixi run -e oracle interop`. No check runs inference.

## Remaining scope

Add format compatibility fixtures for other producer versions when needed.
Python buffer interoperability, other checkpoint versions, native framework
importers and portable packaging are outside this first version. Do not add
architecture abstractions without a concrete caller need.

## Sources

Reference source commit: `a2cd458e2140052a2234402835bd02815d11458e`.
The separate test oracle pins the released Treelite 4.6.1 wheel.

- [v4 field specification](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/docs/serialization/v4.rst)
- [Serializer field order and version handling](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/src/serializer.cc)
- [Stream primitives and optional records](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/include/treelite/detail/serializer.h)
- [Model and tree storage](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/include/treelite/tree.h)
- [Buffer transport mixins](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/include/treelite/detail/serializer_mixins.h)
