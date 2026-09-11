# Performance work: decisions and results

Wrap-up updated 2026-09-12. The completed work progressed from avoidable codec
work, through parallel validation, to an explicit choice about validation cost.
Full validation remains the default. The latest native/Python comparison uses
an explicit opt-out and is not a measurement of default loading.

## Paths taken

| Stage | Decision and reason | Evidence retained |
| --- | --- | --- |
| Initial baseline | Profile before changing representation: eager diagnostics, scalar array I/O, output growth and per-tree scratch dominated. | [Baseline findings](benchmark-results.md) |
| Serial codec, through `737874f` | Keep lazy diagnostics, bounded bulk copies, exact output reservation and reusable validation scratch with inlined checks. | [Implementation](codec-optimization.md); [stage results](optimization-results.md): decode 2.47–3.68× and encode 2.43–4.00× faster than the original baseline. |
| Parallel validation, `06ee661` | Keep MAX CPU batching with conservative activation, deterministic errors and explicit worker limits. Parsing and encoding remain serial. | [Threading decision](threading-results.md): large-forest validation 2.3–2.4× faster; encode time 24–25% and decode time 5–11% lower at that stage. |
| Serial decode, `c00ca17` | Keep bounded unaligned scalar loads, bounded tree reservation and removal of checks already proven by array lengths. | [Profiling decision](decode-optimization.md): serial decode time 23–34% lower; serial validation 22–29% lower, with all validation enabled. |
| Validation policy, `b2765e8` | Make automatic model validation optional per call; keep bounded parsing and an explicit validator that always checks. | [Policy](validation-policy.md): a paired four-case check reduced serial decode time another 15–22%. |

Stage improvements were measured in different sessions and should not be
multiplied into a claimed aggregate speedup. The earlier changes preserve the
validation contract; the final option deliberately changes it for trusted data.

## Latest comparison

The [full validation-opt-out report](validation-opt-out-results.md) retains all
24 encode/decode comparisons: 12 checkpoints, three engines, two reversed
blocks, 144 completed jobs and 2,160 measured batches on a Ryzen 5950X.
Against native Treelite 4.6.1, opt-out Balsa encodes faster on all 12 cases
(7–45% lower latency). Decode is faster on 10 cases (8.5–16.7% lower), overlaps
parity on large RF, and remains 4.3% slower on large XGBoost. It is faster than
the Python API on all 24 comparisons. Confidence intervals and stability
warnings are included in the report.

## Paths not adopted, and limits

- The experimental C++ thread pool established potential but was replaced by
  MAX's supported executor. Its eight-worker speedup was not a production claim.
- Eight workers were not consistently better than four. Dispatch costs hurt
  small forests; a dominant tree defeated tree-level balancing and could hurt
  concurrent throughput. Defaults retain both size thresholds and an imbalance
  guard. The roughly 294 MiB MAX installation cost remains a real tradeoff.
- Parallel encoding showed prototype potential but was deferred. Neither
  encoding nor parsing was parallelized; no production conclusion was drawn
  from the encoding prototype.
- Allocation frequency alone did not explain the serial gap: Balsa and Treelite
  made almost the same number of calls. Scalar parsing and redundant checks were
  more useful targets. Reservation chiefly reduced requested allocation volume.
- Diagnostic parse-only measurements exposed validation cost; they led to a
  documented opt-out, not removal of validation from the default path. Treelite
  does perform format/type/stream checks, but no comparable full structural pass
  on checkpoint deserialization.
- No validation cache, global bypass, borrowed output representation, or custom
  allocator was introduced. Large individual trees, other hardware, and diverse
  production forests remain unproven. Big-endian execution was not tested.

Historical reports below summarize decisions rather than prescribe further work.
Their full earlier text is in Git history. Source-controlled benchmark tools are
under `tools/`; bulky raw results and the older controlled harness remain in
ignored `build/` and `benchmarking/` directories and are absent from fresh clones.
