# Release status

As of 2026-09-18, Balsa 0.2.0 has completed its scoped Treelite v4 checkpoint
milestone on Linux x86-64: reading, inspection, editing, validation and writing,
with float32/float32 and float64/float64 models. Compatibility is tested against
Treelite 4.6.1. This is not a claim of full Treelite API or producer-version parity.

## Completed

- Packed public defaults, explicit editable APIs, migration documentation and
  checked construction/conversion. Semantic codec validation is opt-in.
- Core, framework, ownership and public API acceptance tests, oracle roundtrips,
  generated API documentation, Linux CI and isolated Conda installation tests.
- Apache-2.0 licensing and separate Treelite attribution in source and package.
- Current-revision benchmark selection, with explicit historical revision options.
- A [larger trained-forest storage study](benchmarks/storage-workload-2026-09-18.md)
  covering actual file APIs, packed conversion and fresh-worker peak RSS.

The [September 15 report](benchmarks/final-report.md) is historical evidence.
Its unmerged packed branch, missing CI and unselected license are no longer
outstanding tasks. Its performance results remain tied to its named revisions.

## Remaining release and compatibility work

- Confirm channel publication separately. A local recipe and CI artifact do not
  establish that a package is available to install from modular-community.
  Follow the [distribution instructions](distribution.md); use a licensed commit
  for a submission because the original v0.2.0 tag predates the licensing change.
- Native macOS ARM measurements and installation tests precede any platform
  support claim. Linux ARM is a separate target. Neither is covered by Linux
  x86-64 measurements or the current recipe/CI.
- More producer versions need their own compatibility fixtures if advertised.
- The new corpus contains independently trained trees on generated data, not
  production datasets. Cold disk, durable writes, concurrent serving, and broad
  deployment performance remain outside the measured claim.

Further codec optimization is optional unless a target workload requires it.
Native framework importers, inference and Python buffer-frame interop remain
outside the checkpoint-format milestone.
