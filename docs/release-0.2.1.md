# Balsa 0.2.1

Native Mojo storage and editing for Treelite v4 checkpoints. Target: Linux
x86-64, Mojo/compiler 1.2.0 with MAX core 26.7.0. This release is a compiler
migration and the first version intended for the modular-community channel.
The public API, checkpoint bytes and packed defaults are unchanged from 0.2.0;
see the [0.2 migration guide](release-0.2.0.md) for those contracts.

## Compiler compatibility

| Library version | Mojo compiler | MAX core | Source | Distribution |
|---|---|---|---|---|
| 0.2.0 build 0 | 1.0.0 | 26.5.0 | `v0.2.0` (`3547975`) | CI artifact |
| 0.2.0 build 1 | 1.0.0 | 26.5.0 | `ccd68c6` (Apache-2.0 licensing) | CI artifact |
| 0.2.0 build 2 | 1.1.0 | 26.6.0 | `b32c4a3` | CI artifact |
| 0.2.1 build 0 | 1.2.0 | 26.7.0 | `v0.2.1` | modular-community (pending review) |

From 0.2.1 on, each compiler migration gets a new library version and tag. A
build number increment is reserved for recipe-only rebuilds of the same source.

## Changes

- Following the [Mojo 1.2.0 changelog](https://mojolang.org/releases/v1.2.0/),
  little-endian fast paths in `wire` and `packed_views` test
  `Endian.native() == .little` instead of the deprecated `is_little_endian()`.
- Apache-2.0 licensing with separate Treelite license and attribution, carried
  over from 0.2.0 build 1. The `v0.2.0` tag predates it; `v0.2.1` includes it.
- `rattler-build` is pinned in the packaging environment. CI records
  `SHA256SUMS` and `SOURCE_COMMIT` with the Conda artifact, and `v*` tags
  create a draft GitHub release from the artifact CI tested.

## Verification

Core, packed, defaults, ownership and framework tests pass, along with the
generated API reference check, byte-for-byte Treelite and trained-framework
fixture regeneration, and Treelite 4.6.1 interoperability. The Conda package
passes its isolated installation test without a source include path.
