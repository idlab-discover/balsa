# Balsa

![Balsa: a flame mascot with a wooden decision tree](assets/branding/balsa-logo-169.png)

A native Mojo library for reading, editing, validating and writing Treelite v4
checkpoints. Supports float32 and float64 models; inference is out of scope.
Tested against Treelite 4.6.1, with no Python or libtreelite runtime dependency.

## Build

Requires Linux x86-64, Pixi and a C linker such as GCC. The locked environment
provides Mojo 1.0.0 and MAX core 26.5.0.

```sh
pixi install --locked
pixi run build      # CLI: build/balsa
pixi run package    # Library: build/balsa.mojoc
pixi run check      # Build, package, tests and examples
```

## Use

Save as `app.mojo` in the repository root:

```mojo
from balsa import load, save


def main() raises:
    var model = load("tests/fixtures/float32_op2_missing0.tl")
    print("Trees:", model.num_tree, "Features:", model.num_feature)
    save(model, "build/copy.tl")
```

`load` defaults to float32. Use `load[DType.float64](path)` for float64, or
`load_auto(path)` to discover precision. Loading and saving validate by default.

For an input buffer you want to retain, use `decode(Span(data))` or
`decode_auto(Span(data))`. The result owns its fields independently of the input.
The consuming `decode(data^)` and `decode_auto(data^)` APIs remain available.

For repeated loads, `decode_into(model, Span(data))` reuses the destination's
tree and field capacities. Its precision must match the checkpoint. On failure,
the model may contain partially updated fields: decode into it again or discard
it before using it as a model. Bounds, format and resource checks always apply;
model validation is enabled by default for all decoding APIs.

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

See [construction examples](examples/construction.mojo) and
[third-party notices](THIRD_PARTY_NOTICES.md).
Generate the API reference with `pixi run -e docs docs` (`docs/api.md`).

<p align="center">
  <img src="assets/branding/balsa-logo-square.png" alt="Balsa mascot" width="160">
</p>
