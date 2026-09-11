# Balsa and Treelite

Balsa owns the model format: checkpoints, model/tree fields, construction,
structural validation and metadata. Execution libraries own capability checks,
prepared layouts, traversal, aggregation, transforms and prediction arrays.
Balsa has no dependency on Pyre, NuMojo, MAX, Python or libtreelite.

## Treelite's construction design

Treelite has a C++ model/tree core. Its Python `Model` owns a handle to that core;
its Python `ModelBuilder` wraps a C++ builder that creates the core model.
The builder is a general construction mechanism, used by first-party importers
as well as custom integrations. XGBoost, LightGBM and sklearn loaders use it;
the checked-out source also has sklearn bulk loaders that populate storage
directly. Thus the core is independent of the builder, but the builder is not
just a fallback wrapper for unusual libraries.

Sources, checked against local source commit
`a2cd458e2140052a2234402835bd02815d11458e` and the online API documentation:

- [Python builder interface](https://treelite.readthedocs.io/en/latest/treelite-api.html#module-treelite.model_builder)
- [C++ builder creates the core model](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/src/model_builder/model_builder.cc)
- [LightGBM loader](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/src/model_loader/lightgbm.cc)
- [XGBoost JSON loader](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/src/model_loader/detail/xgboost_json/delegated_handler.cc)
- [sklearn loader](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/src/model_loader/sklearn.cc)
- [sklearn bulk loader](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/src/model_loader/sklearn_bulk.cc)

The released Treelite **4.6.1** wheel remains Balsa's checkpoint oracle. Online
`latest` documentation and the source checkout do not expand that tested
compatibility claim.

## Balsa's interface

| Operation | Balsa | Treelite Python |
| --- | --- | --- |
| Load with precision discovery | `load_auto(path)` | `Model.deserialize(path)` |
| Load with a known precision | `load[dtype](path)` | Discovered automatically |
| Decode bytes with precision discovery | `decode_auto(bytes^)` | `Model.deserialize_bytes(bytes)` |
| Write a model | `save(model, path)` / `encode(model)` | `serialize` / `serialize_bytes` |
| Construct trees and metadata | `TreeBuilder` + `ModelBuilder` | `ModelBuilder` |
| Edit fields | Typed mutable fields | Header/tree field accessors |
| Validate structure | `validate(typed_model)` | No equivalent standalone Python operation |

Balsa keeps `Model[dtype]` and `Tree[dtype]` as the shared representation.
Builders handle redundant counts, parallel node arrays and payload offsets,
then return ordinary owned fields. Native framework importers can use these
builders or populate those same fields in bulk, with final structural validation.
Balsa's builder uses dense node IDs and one call per node definition instead of
copying Treelite's start/end-node state machine. It accepts definitions in any
order, supports forward child references and preserves those IDs.

## Precision comes from the checkpoint

The v4 header contains separate `threshold_type` and `leaf_output_type` tags.
The supported pairs are float32/float32 and float64/float64. The enum also lists
UInt32, but v4 does not permit integer leaf output. Precision applies to the
whole model, not independently to each node. Some other fields have fixed types:
base scores and Hessian/gain statistics are float64; postprocessor parameters
are float32. See the [v4 specification](https://treelite.readthedocs.io/en/latest/serialization/v4.html).

`load_auto` and `decode_auto` return `AnyModel`, a
`Variant[Model[DType.float32], Model[DType.float64]]`. This discovers storage
precision at runtime without widening, rounding or changing checkpoint bytes.
Callers inspect the active type once before using a typed model; `save` and
`encode` accept the variant directly. The existing `load[dtype]` and
`decode[dtype]` stay available and reject a mismatched file. Their default is
still float32, preserving existing callers.

`checkpoint_dtype(bytes)` checks the version and both tags, but is only header
inspection, not full model validation. The CLI uses this shared helper.

## Framework import direction

Direct XGBoost, LightGBM, scikit-learn and CatBoost support is the intended
frontend direction, with the builder also serving custom tree libraries.
**These native framework importers are not implemented yet.** This change
establishes their common destination and construction tools, without adding
unverified parsers or a runtime Treelite dependency.

For now, Treelite can convert its supported XGBoost, LightGBM and sklearn models
to checkpoints that Balsa reads. Its documented frontend does not provide a
CatBoost loader; do not assume CatBoost support through this route. CatBoost
will need a separately verified importer and explicit handling of its feature
and categorical semantics. A [test-only numeric symmetric-tree adapter](framework-testing.md)
now supplies a verified CatBoost checkpoint fixture; it is not a native or
general-purpose importer.

Future importers should preserve source precision and model semantics, declare
their supported source versions/model kinds, and verify their field conversion
against source-library fixtures. They should not introduce prediction execution
into Balsa. See the [usage guide](usage.md) for the current construction and
borrowing interface.
