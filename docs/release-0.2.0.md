# Balsa 0.2.0

## Storage policy

Ordinary loading returns `PackedModel[dtype]`; precision discovery returns
`AnyPackedModel`. Both retain checkpoint bytes for fast output and read-only
inspection. There is no tree-count cutoff: all 16 measured unchecked packed
cases improved over editable consuming decode. The earlier 64-tree heuristic
concerned checked decoding and does not justify a cutoff for unchecked loads.
Representation selection is resolved at the public API, with no runtime policy
branches scattered through callers.

Automatic semantic validation is disabled for codec operations by default.
`ValidationOptions(enabled=True)` enables it without changing representation.
Explicit `validate(model)` and packed `model.validate()` always check semantics.
`to_model()` and `ModelBuilder.build()` remain checked by default, and accept an
explicit unchecked option. Conversion allocates independent editable fields.

Bounds, supported format/precision, truncation, trailing-byte detection and
applicable resource limits remain unconditional. Semantically invalid metadata,
array relationships and topology may survive unchecked loading and output.
Packed output copies retained bytes without revalidation. Use validated loading
or explicit validation before output for uncertain input; revalidate editable
models after changes.

## Migration

| 0.1 use | 0.2 use |
| --- | --- |
| `load` / `decode` returning mutable `Model` | `load_editable` / `decode_editable` |
| `load_auto` / `decode_auto` returning `AnyModel` | `load_auto_editable` / `decode_auto_editable` |
| Automatic codec semantic checking | Pass `ValidationOptions(enabled=True)` |
| Inspect ordinary load result | `num_trees()`, `num_features()`, `tree(i)` |
| Edit an already packed model | `to_model()` then edit and revalidate |

`Model`, `Tree`, `AnyModel`, builders and `decode_into` retain their editable
capabilities. `balsa.codec` remains the explicit editable codec module.
Root `encode` and `save` dispatch by argument type at compile time, accepting
packed/editable models and both precision variants. Packed output takes no
validation options; validate the owner explicitly.

## Warning policy

No default-emitted warning. The library does not write unsolicited stderr,
track process-global acknowledgment state, or add synchronization to codec
calls. The README and public API state the performance-first policy prominently.
There is no suppression mechanism, and no first-use warning overhead to time.
Silence never indicates that a model has passed semantic validation.

## Validation and scope

`pixi run check` builds the CLI and precompiled library, runs native core,
framework, packed and public-default tests, checks compile-time rejection of
escaping/mutating views, and runs the public-default suite against the compiled
package. CI also checks generated docs, fixture reproducibility, Treelite and
framework interoperability, and an isolated Conda installation.

Performance is workload-dependent. Existing evidence measures warmed in-memory
codec operations, excluding file I/O, peak memory, editing/conversion cost and
intensive repeated inspection. Large framework cases repeat trained trees.
Packed byte copying and serializing editable fields have different capabilities.
The release benchmark uses the new public interface and matched checked and
unchecked configurations; it is a local regression check, not a production
checkpoint performance guarantee.

## Release measurement

The [16-case release check](benchmarks/release-0.2.0.md) confirms that the public
packed default beats unchecked editable consuming decode on every input.
The two 100,020-node forests take 1.067 / 1.123 ms through the default API,
versus 6.865 / 7.607 ms editable unchecked. Checked packed loading takes
4.717 / 4.695 ms. Packed output copies take 0.146 / 0.191 ms, versus
2.361 / 2.502 ms to encode editable fields without validation.

The public-default and direct-packed timings agree within local measurement
variation. Checked small RF multiclass remains slower packed (4.643 vs
4.179 microseconds); unchecked packed is faster (0.997 vs 3.152 microseconds).
No checked-load cutoff is imposed on the unchecked storage policy. Raw samples
and source/input hashes are retained alongside the report.
