# Codec optimization: retained design

The initial serial work through `737874f` reduced avoidable work while preserving
owned models/bytes and full validation. [Stage results](optimization-results.md)
summarize the measured gains; the [performance wrap-up](performance-plan.md)
connects this design to subsequent scalar-load, threading and policy changes.
Validation is now optional per call, but remains enabled by default.

## Lazy diagnostics

Successful reads retain a static field name and integer tree index. Validation
helpers borrow field names. Full messages are constructed only on failure,
retaining field, tree and byte-position context without allocating strings for
every successful element check. This removed work rather than changing errors.

## Bounded bulk transfers

An array's eight-byte count is in elements, not bytes. The reader checks the
element limit and `count <= remaining_bytes / element_width` before multiplying,
allocating or copying. It allocates an owned typed list without redundant
initialization, then fills the entire proven byte range before exposing it.
Empty arrays skip the copy. Unknown extension payloads stay opaque.

Payloads are not aligned in the wire format. Byte-aligned copying into typed
storage avoids an alignment assumption about the input. Bulk copies apply when
the host matches the little-endian wire order; the big-endian fallback retains
explicit conversion and has not been exercised on hardware. Raw transfer
preserves NaN payloads and negative zero without numeric conversion.

The later scalar optimization applies the same bounds-first principle to field
values and array counts, using explicitly unaligned fixed-width loads. See
[the decode decision](decode-optimization.md) for its proof and measurements.

## One schema, two writer modes

Encoding first traverses field metadata in counting mode, reserves exactly the
final byte count, then emits. A compile-time Writer parameter specializes one
shared field-order traversal into counting or writing, avoiding a separate size
formula that could omit fields. Every size addition respects the byte budget;
standalone Writers still support bounded incremental use.

The extra metadata pass paid for itself by eliminating output growth and copies.
Decoding does not need a preliminary full scan: it learns each individually owned
array's length as it arrives. A later bounded tree-list capacity hint removes
avoidable growth without trusting the declared tree count as an allocation size.

## Reusable validation scratch

Validation proves field lengths and semantic ranges, then traverses each tree.
A seen array detects repeated visits (cycles or shared children); the visited
count detects unreachable nodes. A stack grows with actual traversal demand.
Scratch lists reset their contents between trees and reuse capacity. Small
predicate helpers inline; diagnostic formatting stays on failure paths.

The initial design used scratch per validation call. MAX batching subsequently
gave each batch private scratch with the same reset rules. There is no cached
validity flag: explicit validation always checks the current model, and automatic
validation checks on each call unless the caller opts out. Later array-length
proofs remove redundant per-node bounds checks; dynamic traversal stays checked.

Scratch reuse and helper inlining were measured together, so their individual
contributions were not isolated. Reduced allocation frequency is not a promise
of reduced peak RSS: allocators can retain memory, and model storage remains.

## Verification boundary

Tests cover all wire dtypes, unaligned starts, empty arrays, floating bit
preservation, exact limits, truncation/error context, extensions, mutation and
scratch reset. Framework and upstream roundtrips check byte fidelity. These
changes did not alter the checkpoint format or switch to borrowed outputs.
The [policy contract](validation-policy.md) separately defines what callers
can now skip and which wire checks remain mandatory.
