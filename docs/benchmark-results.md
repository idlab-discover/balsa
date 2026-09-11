# Baseline superseded — 2026-09-11

The initial baseline found Balsa decode 3.72–5.49× and encode 2.82–5.19×
slower than the native Treelite reference. Profiling identified eager error
strings, scalar array I/O, output growth and repeated validation allocations.

Those findings led to lazy diagnostics → bounded bulk transfers and exact
output reservation → reused validation scratch and inlined checks.

[Current results](optimization-results.md) retain the before/after measurements;
[the implementation explanation](codec-optimization.md) describes the changes.
The original detailed baseline is archived locally at
`benchmarking/archive/benchmark-results.md` in the ignored benchmark workspace.
