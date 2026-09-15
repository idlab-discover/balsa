# Balsa

![Balsa: a flame mascot with a wooden decision tree](assets/branding/balsa-logo-169.png)

A native Mojo library for reading, editing, validating and writing Treelite v4
checkpoints. Supports float32 and float64 models; inference is out of scope.
Tested against Treelite 4.6.1, with no Python or libtreelite runtime dependency.

## License

Balsa is licensed under [Apache-2.0](LICENSE), without LLVM exceptions.
See [third-party notices](THIRD_PARTY_NOTICES.md) for Treelite attribution.

## Build

Requires Linux x86-64, Pixi and a C linker such as GCC. The locked environment
provides Mojo 1.0.0 and MAX core 26.5.0.

```sh
pixi install --locked
pixi run build      # CLI: build/balsa
pixi run package    # Library: build/balsa.mojoc
pixi run check      # Build, package, tests and examples
```

## Use: performance-first storage

**Balsa 0.2 skips automatic semantic validation by default.** Bounds, format,
precision, truncation, trailing-byte and resource checks remain active, but they
cannot establish valid metadata, field relationships or tree topology. Use
`ValidationOptions(enabled=True)` for untrusted or uncertain checkpoints.
Unchecked saving can preserve or emit semantic errors. Library calls are silent;
there is no runtime warning or warning-suppression setting.

Save as `app.mojo` in the repository root:

```mojo
from balsa import load, save, ValidationOptions


def main() raises:
    var model = load("tests/fixtures/float32_op2_missing0.tl")
    print("Trees:", model.num_trees(), "Features:", model.num_features())
    save(model, "build/copy.tl")

    # Safety-first loading uses the same packed representation.
    var checked = load(
        "tests/fixtures/float32_op2_missing0.tl",
        options=ValidationOptions(enabled=True),
    )
    checked.validate()  # Explicit validation always runs.
```

`load` and `decode` return a read-only `PackedModel`, with float32 precision by
default. Use `load[DType.float64](path)` for float64, or `load_auto(path)` to
return an `AnyPackedModel` precision variant. `save` and `encode` accept both
packed and editable models and their precision variants.

`decode(data^)` consumes and retains the input list. `decode(Span(data))` and
`decode_auto(Span(data))` copy borrowed input once to own it. Packed `encode`
copies retained bytes; packed `save` writes them directly. Neither repeats
semantic validation: validate during loading or call `model.validate()` before
saving when semantic safety matters.

### Editing and migration from 0.1

Root `load`, `decode`, `load_auto` and `decode_auto` now return packed owners.
The editable `Model` type has not changed. Existing code that accesses mutable
fields should import `load_editable`, `decode_editable`, `load_auto_editable`
or `decode_auto_editable` from `balsa` (or use `balsa.codec`). For example:

```mojo
from balsa import load_editable, save, validate


def main() raises:
    var model = load_editable("tests/fixtures/float32_op2_missing0.tl")
    model.trees[0].threshold[0] = 0.75
    validate(model)
    save(model, "build/edited.tl")
```

Alternatively, `packed_model.to_model()` makes an independent editable copy and
validates by default. Builders also retain checked construction by default.
Direct editable codec calls and `ValidationOptions()` now default to unchecked;
pass `ValidationOptions(enabled=True)` to retain 0.1 codec validation behavior.
Revalidate after edits when invariants matter.

`decode_into(model, Span(data))` retains editable capacity reuse. On failure,
its fields may be partially updated: decode into it again or discard it.
See [packed storage](docs/packed-storage.md) and the
[0.2 migration guide](docs/release-0.2.0.md) for the contracts and rationale.

For the Conda recipe and GitHub Actions setup, see
[packaging and CI](docs/distribution.md).

## Import and link

```sh
pixi run mojo run -I src app.mojo                         # From source
pixi run mojo run -I build app.mojo                       # Precompiled package
pixi run mojo build -O3 -I build app.mojo -o build/app     # Compile a consumer
./build/app
```

`-I` points to the directory containing `balsa/` or `balsa.mojoc`; use absolute
paths from other projects. Build consumers with the same Mojo toolchain and
rebuild the package after library changes. Executables use the Mojo runtime
libraries from their build environment.

For a quick CLI example:

```sh
./build/balsa inspect tests/fixtures/float32_op2_missing0.tl
```

## Documentation

- [API reference](docs/api.md) — exported types, functions and options.
- [Construction example](examples/construction.mojo) — build and save a model.
- [Packed storage](docs/packed-storage.md) — ownership and validation details.
- [0.2 migration guide](docs/release-0.2.0.md) — changed defaults and compatibility.
- [Release benchmarks](docs/benchmarks/release-0.2.0.md) — measurements and limits.
- [Packaging and CI](docs/distribution.md) — builds, checks and distribution.

Regenerate the API reference with `pixi run -e docs docs`.

<p align="center">
  <img src="assets/branding/balsa-logo-square.png" alt="Balsa mascot" width="160">
</p>
