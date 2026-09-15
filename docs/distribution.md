# Packaging and CI

## Reproducible development

Use Pixi with the stable Modular channel and the checked-in `pixi.lock`:

```sh
pixi install --locked
pixi run --locked check
pixi run --locked -e docs docs-check
pixi run --locked -e oracle fixtures-check
pixi run --locked -e oracle interop
pixi run --locked -e frameworks framework-fixtures-check
pixi run --locked -e frameworks framework-interop
pixi run --locked -e packaging conda-build
```

The supported platform is Linux x86-64. A C linker such as GCC is needed for
consumer compilation. Mojo 1.0.0 and MAX core 26.5.0 come from the same stable
channel; their version numbers intentionally differ. MAX core supplies parallel
validation primitives; the Python framework packages are test-only dependencies.

The CI workflow runs on Ubuntu 24.04 for pushes, pull requests and version tags.
It uses pinned `setup-pixi`, checkout and artifact actions, installs locked
environments, and tests the package in a separate environment. No GPU or
publishing credentials are required. Conda artifacts are retained by Actions.
Performance benchmarks stay local because shared runners give noisy timings.

## Conda package

`pixi run -e packaging conda-build` runs rattler-build and writes
`build/conda/linux-64/balsa-0.2.0-*.conda`. The package installs
`lib/mojo/balsa.mojoc`, where Mojo discovers it automatically. Its recipe test
imports Balsa without a source include path, constructs a model, roundtrips it
through the public packed API, validates it, and converts it back for editing.

The recipe pins Mojo compiler 1.0.0 and MAX core 26.5.0 for both compilation and
installation: precompiled Mojo packages are tied to their toolchain. Rebuild
with a new recipe build number when updating the compiler for the same Balsa
version. No cross-platform claim is made. The CLI remains a source-build example;
the Conda artifact distributes the library.

The repository recipe reads only selected files from the local checkout, so CI
packages exactly the revision under test. For a community submission, replace
`source.path` and `source.filter` with a Git source and the full release commit
SHA. Keep `test.mojo` next to the recipe. This avoids a self-referential commit
SHA inside the released repository's own build recipe.

## modular-community publication

Balsa has not yet selected a license for its original contributions. Select one
and add its metadata/license text before submitting a community recipe. The
existing Treelite attribution does not license Balsa itself.

The channel is community maintained; writing a local recipe does not publish
Balsa there. The documented route is a pull request to
[modular/modular-community](https://github.com/modular/modular-community), adding
`recipes/balsa/recipe.yaml` and `recipes/balsa/test.mojo`. Package availability
depends on that repository accepting and building the recipe.

Once accepted and published, consumers can add
`https://repo.prefix.dev/modular-community` to their Pixi workspace channels
alongside `https://conda.modular.com/max` and `conda-forge`, then run
`pixi add balsa=0.2.0`. Do not advertise that command as working before the
package is actually available.

References: [Mojo packaging](https://mojolang.org/docs/tools/packaging/),
[Pixi GitHub Actions](https://pixi.prefix.dev/latest/integration/ci/github_actions/),
[community channel](https://prefix.dev/channels/modular-community).
