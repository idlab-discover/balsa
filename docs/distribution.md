# Packaging and release

## Build and validate

Use the checked-in lockfile and Pixi 0.80.0, matching CI:

```sh
pixi install --locked -e default -e docs -e oracle -e frameworks -e packaging
pixi run --locked check
pixi run --locked -e docs docs-check
pixi run --locked -e oracle fixtures-check
pixi run --locked -e oracle interop
pixi run --locked -e frameworks framework-fixtures-check
pixi run --locked -e frameworks framework-interop
pixi run --locked -e packaging conda-build
```

The supported platform is Linux x86-64. A C linker such as GCC is needed for
consumer compilation. Mojo 1.2.0 and MAX core 26.7.0 come from the same stable
channel; their version numbers intentionally differ. The stable `max-core 26.7.0`
package metadata requires exactly `mojo-compiler ==1.2.0`. MAX core supplies
parallel validation primitives; the Python framework packages are test-only
dependencies. Balsa has no `mojo-snappy` dependency.

The release recipe builds from the checkout, includes the Apache license and the
separate Treelite license and attribution, and installs `lib/mojo/balsa.mojoc`,
where Mojo discovers it automatically. Its test environment contains the built
package and compiler, with no checkout source include path. The test constructs
a model, roundtrips it through the public packed API, validates it, and converts
it back for editing. Build outputs are under `build/conda/linux-64/`.

The recipe pins Mojo compiler 1.2.0 and MAX core 26.7.0 for both compilation and
installation: precompiled Mojo packages are tied to their toolchain. No
cross-platform claim is made. The CLI remains a source-build example; the Conda
artifact distributes the library.

The repository recipe reads selected files from the local checkout, so CI
packages exactly the revision under test. The community recipe replaces
`source.path` and `source.filter` with a Git source pinned to the release tag's
full commit SHA and keeps `test.mojo` next to the recipe. This avoids a
self-referential commit SHA inside the released repository's own recipe.
Channel publication runs through
[modular/modular-community](https://github.com/modular/modular-community/tree/main/recipes/balsa).
The recipe lists [Str-Gen](https://github.com/Str-Gen) as maintainer.

Current verification status is recorded in [release status](release-status.md).

## Versions and build numbers

A Conda artifact is identified by name, version and build string. This recipe
has no variant keys, so the build string is always `hb0f4dca_<build number>`
and the build number alone separates artifacts of one version. The
modular-community CI builds with `--skip-existing=all`: an unchanged
name/version/build is skipped, not rebuilt.

- New source or a new compiler pin: new library version and tag, build number 0.
- Same tagged source, recipe-only fix (metadata, tests, license files):
  same version, build number + 1.

Builds 0–3 of 0.2.0 were local and CI artifacts only; none reached the
community channel. See the table in the [0.2.1 release notes](release-0.2.1.md).

## Release sequence

1. Merge the release commit to `main` after both GitHub CI jobs pass. Workspace,
   recipe and `balsa.__version__` versions must all equal the release version,
   with build 0.
2. Tag that merge commit with an annotated `v<version>` tag and push the tag.
   The Release workflow checks that the tag is on `main` and matches the
   versions, build number 0 and `docs/release-<version>.md`. It runs the full
   CI, checks the artifact's `SOURCE_COMMIT` and `SHA256SUMS`, and creates a
   draft GitHub release with the notes, `.conda` file, checksum file and
   source-commit record.
3. Review the draft release and publish it.
4. Update `recipes/balsa/recipe.yaml` in a fork
   of `modular/modular-community`: version, compiler pins, build number 0 and
   the tag's commit as `rev`. The recipe tests the tagged `conda.recipe/test.mojo`. Run the **Validate community recipe** workflow
   (manual dispatch) with the fork's repository and commit. It builds the exact
   recipe with upstream's Rattler-Build version, variants and channel order and
   installs the result into a clean workspace. Then open the PR with the
   upstream checklist. The package reaches `modular-community` only after a
   maintainer merges it and the upload job runs.

Do not move an existing release tag. A local package, CI artifact or GitHub
release does not mean that the package is available through a public Conda
channel. Once it is published, consumers add
`https://repo.prefix.dev/modular-community` to their Pixi channels alongside
`https://conda.modular.com/max` and `conda-forge`, then run `pixi add balsa`.

## CI behavior

CI runs on branch pushes, pull requests and manual dispatch. It uses pinned
GitHub action revisions, locked Pixi environments, read-only repository
permission, and uploads the Conda artifact with SHA256 checksums and the exact
checkout commit. No GPU or publishing credentials are required. Performance
benchmarks stay local because shared runners give noisy timings.

`v*` tag pushes run the Release workflow instead. It calls CI and releases the
artifact that CI tested. Only its draft-release job has write permission. It
does not publish the release, overwrite an existing one, or upload to a Conda
channel.

References: [Mojo packaging](https://mojolang.org/docs/tools/packaging/),
[setup-pixi](https://github.com/prefix-dev/setup-pixi),
[Rattler recipe/tests](https://rattler-build.prefix.dev/latest/reference/recipe_file/),
[community channel](https://prefix.dev/channels/modular-community).
