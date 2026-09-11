# Balsa and Treelite

Balsa exposes the checkpoint representation directly through a small,
format-only interface. Compared with Treelite's Python interface (checked
against 4.6.1), the core operations map closely:

| Balsa | Treelite Python |
| --- | --- |
| `load(path)` | `Model.deserialize(path)` |
| `save(model, path)` | `model.serialize(path)` |
| `decode(bytes)` | `Model.deserialize_bytes(bytes)` |
| `encode(model)` | `model.serialize_bytes()` |
| `validate(model)` | No directly equivalent standalone operation |

The meaningful differences are:

- **Precision:** Balsa callers specify Float32 or Float64 when loading;
  Treelite discovers it from the checkpoint.
- **Field access:** Balsa exposes typed, mutable fields. Treelite provides
  model properties and field accessors for detailed inspection and editing.
- **Construction:** Balsa callers populate arrays and maintain their
  relationships. Treelite's builder manages more of that bookkeeping.
- **Representation:** Balsa owns Mojo arrays; Treelite's Python model holds
  a handle to C++ storage.

Free functions versus methods is mostly a style choice. The main tradeoff
is that Balsa callers need more knowledge of the format when creating or
editing trees.

Keep the first version small: explicit precision, raw fields and validation
are acceptable. Add convenience only for demonstrated caller friction.
Inference is outside the project's scope.

See [Balsa usage](../README.md) and the reference Treelite
[model interface](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/python/treelite/model.py)
and [builder](https://github.com/dmlc/treelite/blob/a2cd458e2140052a2234402835bd02815d11458e/python/treelite/model_builder.py).
