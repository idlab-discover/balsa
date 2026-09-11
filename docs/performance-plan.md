# Performance work completed — 2026-09-11

The original plan led to a controlled twelve-checkpoint Balsa/Treelite baseline,
then lazy diagnostics, bounded bulk array I/O with exact output sizing, and
validation scratch reuse with helper inlining. Full validation and byte-exact
roundtrips remained enabled throughout.

See [the implementation explanation](codec-optimization.md) and
[the verified results and measurement conditions](optimization-results.md).
Local runners, raw evidence and the archived protocol live in the ignored
`benchmarking/` workspace (`benchmarking/CONTROLLED.md` and
`benchmarking/archive/performance-plan.md`); they are absent from fresh clones.
