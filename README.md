# Balsa

A small, format-only Mojo library for Treelite v4 binary checkpoints.
Load, inspect, edit, validate and save model fields. Inference is out of scope.

Uses **Mojo 1.0.0**, with **Treelite 4.6.1** as the test oracle on `linux-64`.
The native library does not call Python or libtreelite.

## Getting started

Requires Pixi and a C linker such as GCC.

```sh
cd balsa
pixi install --locked
pixi run run
pixi run check
```

| Command | Purpose |
| --- | --- |
| `pixi run run` | Inspect a sample checkpoint |
| `pixi run build` | Compile the CLI to `build/balsa` |
| `pixi run package` | Precompile the library to `build/balsa.mojoc` |
| `pixi run test` | Run native format tests |
| `pixi run example` | Construct, save and automatically load a float64 stump |
| `pixi run check` | Build, inspect, precompile and test |
| `pixi run fmt` | Format Mojo sources |

## Library

```mojo
from balsa import load, save

def main() raises:
    var model = load("tests/fixtures/float32_op2_missing0.tl")
    print("Trees:", model.num_tree, "Features:", model.num_feature)
    save(model, "copy.tl")
```

Use `load_auto(path)` to discover precision from the checkpoint. It returns
`AnyModel`, a variant of the float32 and float64 model types; `save` and `encode`
accept it directly. `decode_auto(bytes^)` does the same for in-memory bytes.
For known precision, use `load[DType.float64](path)` or `decode[dtype](bytes^)`;
plain `load` and `decode` retain their float32 default.

`ModelBuilder` and `TreeBuilder` construct models without manual parallel-array
bookkeeping. `Operator`, `NodeType`, `TaskType`, and `TypeInfo` provide named
wire constants. Models expose postprocessor/attribute text accessors, and trees
provide checked borrowed category and vector-leaf spans. See the
[usage guide](docs/usage.md) and [runnable example](examples/construction.mojo).

The interface also exports `validate(model)`, `Model[dtype]`, `Tree[dtype]`,
`Extension`, and `Limits`.

Model and tree fields are mutable. Loading, decoding and encoding validate
structure; call `validate` explicitly after editing when useful. Builders maintain counts,
arrays and offsets; callers editing raw fields must keep them consistent.

## Format scope

- Little-endian v4 with Float32/Float32 or Float64/Float64 storage.
- All defined fields, including categorical splits, vector leaves, multi-target
  metadata, statistics, postprocessor settings and attributes.
- Exact preservation of floating-point bits, version triplets and opaque records
  in all three extension slots.
- Validation of types, dimensions, lengths, flags, indices, offsets and topology;
  rejection of truncated/trailing bytes and excessive counts.

Only producer **4.6.1** is verified. Other v4 minor/patch versions are accepted
when they follow the same layout, but are not claimed as tested. Newly constructed
models use checkpoint version 4.6.1 independently of Balsa's version.

Strings are stored as byte lists with optional strict UTF-8 text accessors. Attribute JSON and extension contents are
opaque; callers must supply valid attribute JSON (an object or an empty string).
Postprocessor settings are preserved as metadata, never executed.

Codec operations accept `Limits`. Defaults are 64 MiB checkpoint bytes,
8,388,608 elements per array, 100,000 trees, 1,000,000 total nodes and 1,024
extensions per slot. These are allocation/work caps, not an RSS guarantee.
`save` validates and encodes before replacing the destination contents; replacement
is not atomic.

## CLI

```sh
pixi run build
./build/balsa inspect tests/fixtures/float32_op2_missing0.tl
./build/balsa roundtrip tests/fixtures/float32_op2_missing0.tl build/copy.tl
```

The CLI discovers precision from the checkpoint. Its only commands are
`inspect` and `roundtrip`.

## Verification

Treelite is pinned in the separate `oracle` environment. Native tests use
saved fixtures and need no Python packages.

```sh
pixi install -e oracle --locked
pixi run -e oracle fixtures-check
pixi run -e oracle interop
```

The synthetic suite checks **14 byte-exact roundtrips and field comparisons**, upstream
loading of raw- and builder-created Mojo checkpoints, precision discovery,
borrowed slices, UTF-8 access, construction errors, extension retention, floating-point bit
preservation, malformed models, truncated prefixes and deterministic mutations.
Synthetic fixture generation and verification perform no inference.

`fixtures-check` regenerates fixtures temporarily and compares every artifact.
`pixi run -e oracle fixtures` intentionally regenerates the saved fixtures.
[The manifest](tests/fixtures/manifest.json) records producer/wheel hashes and
model fields; [the stump layout](tests/fixtures/stump-layout.json) independently
annotates wire offsets.

There are also **eight checkpoints from trained framework models**: XGBoost,
LightGBM, a numeric CatBoost model, and five sklearn ensembles. `pixi run test`
includes their native parsing and roundtrip checks without Python dependencies.
`pixi run -e oracle framework-interop` compares the Balsa outputs with Treelite.
The separate `frameworks` environment retrains and verifies their conversions
against source-library predictions; see [framework testing](docs/framework-testing.md)
for commands, pinned versions and the limited CatBoost adapter scope.

A [performance measurement proposal](docs/performance-plan.md) separates
in-memory codec, validation and file I/O costs for Balsa and Treelite.

The sibling Treelite checkout is not a build dependency. Precompiled packages
are compiler-version-specific; executables link Mojo runtime libraries from
their build environment. Portable distribution is outside this first version.

See [the API comparison](docs/api-comparison.md), [the format plan](docs/mvp-plan.md)
and [upstream attribution](THIRD_PARTY_NOTICES.md).
