# Initial codec optimization: completed stage

Historical results from 2026-09-11, through `737874f`, before MAX validation,
scalar-load optimization and the validation opt-out. See the
[performance wrap-up](performance-plan.md) and
[latest opt-out comparison](validation-opt-out-results.md) for the final state.

## Decisions that paid off

| Change retained | Reason and observed effect |
| --- | --- |
| Lazy diagnostic strings | Build detailed errors only on failure; remove successful-read string construction and allocation. |
| Bounded bulk array I/O | Prove a payload fits once and transfer it into owned storage. Dense-array diagnostics improved roughly 17–40× for reads and 22–28× for writes; these are not public decode/encode speedups. |
| Exact output reservation | Count and emit with one shared schema traversal, avoiding output growth and copies. |
| Reused validation scratch and inlined checks | Reuse traversal capacity between trees and expose small predicates to the compiler. Combined validation diagnostics improved 5.15–5.80×; their individual contributions were not isolated. |

The controlled 12-checkpoint comparison retained full validation. Public decode
improved **2.47–3.68×**, encode **2.43–4.00×** versus the original baseline.
It used 144 pyperf jobs in two reversed blocks, three process groups per block,
five measured batches per group, and CPU 14 affinity. Each worker had eight
operation warmups. Required copies and output destruction were timed; startup,
file I/O and setup were excluded. Before/after sessions were separate, not
simultaneous trials. Host: Ryzen 5950X, Mojo 1.0.0, Treelite 4.6.1, powersave
policy without isolation.

## Allocation findings and paths ruled out

On the 100,020-node XGBoost / RF cases, decode allocation calls fell from
352,396 / 372,400 to 113,382 / 133,386; encode calls fell from 166,725 to five.
These are intercepted Mojo allocator calls, measured separately from timing.
Encode peak RSS fell about 16 MiB. Decode peak RSS stayed roughly unchanged
for XGBoost and rose about 2 MiB for RF: fewer calls did not guarantee a lower
process peak. Raw-byte copying itself barely changed in component tests, so
optimizing the required input copy was not the productive path at this stage.

Early ablation runs overlapped other work and were excluded; clean sequential
ablations supported retaining all three stages. No float conversion, borrowed
model storage, wire-format change or validation bypass was introduced.
[The implementation note](codec-optimization.md) preserves the bounds and
ownership reasoning.

## Verification and evidence

At this stage, 17 core and eight framework tests passed, plus package/CLI/example
checks, 14 upstream byte-exact roundtrips, trained-framework interoperability,
and the 12-case native/Python benchmark verifier. Big-endian execution, cold
file loading and prediction throughput were not measured. Large forests repeat
small trees, so those results do not establish all-topology performance.

Ignored `benchmarking/controlled/optimized/` retains the complete pyperf table,
intervals, schedule and logs. `optimized-diagnostics/`, `optimization-ablation/`
and `optimization-verification/` retain component timings, allocation/RSS probes,
source/binary provenance and checks. Full historical tables remain in Git history.
