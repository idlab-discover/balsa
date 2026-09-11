# How the codec optimizations work

Balsa still owns decoded arrays, returns owned encoded bytes, and fully validates
models. These changes reduce the work needed to deliver those guarantees.
Measurements and the independent verification are in
[optimization results](optimization-results.md); the original evidence is in
[benchmark results](benchmark-results.md).

## 1. Build diagnostic strings only when something fails

Previously, checking a boolean constructed a message such as
`"default_left boolean"` for every element, even when every element was valid.
The decoder also repeatedly assembled strings such as `"tree[1666].threshold"`.
String construction can allocate memory and copy characters. A compiled language
still performs that work if the program requests it.

The decoder now carries a static field name and an integer tree index. Validation
helpers borrow their field names. They assemble a complete message only inside
the failure branch. Errors retain the field, tree context and byte position;
successful reads carry only the information needed to produce a future error.

This is a useful general pattern for readers: keep inexpensive context while
parsing, then format a useful explanation at the point of failure.

## 2. Transfer whole arrays and plan the output allocation

The checkpoint is a sequence of typed fields, without alignment padding. An
array contains an eight-byte unsigned element count followed by its elements.
For example, three Float32 values occupy `8 + 3 × 4 = 20` bytes. The count means
**elements**, so it must be multiplied by the element width to get bytes.
Treelite 4.6.1 itself resizes its array and performs one stream read or write for
the payload. See its [array serializer](https://github.com/dmlc/treelite/blob/4.6.1/include/treelite/detail/serializer.h).

The old Balsa array reader called the scalar reader for each element. That scalar
reader checked the remaining extent and assembled the value byte by byte. The
array reader had already established that the whole payload fit, so the scalar
checks and repeated byte assembly were redundant on a little-endian CPU.

The new reader:

1. Reads the count and checks the configured element limit.
2. Checks `count <= remaining_bytes / element_width` before multiplying. This
   rejects truncation without allowing an attacker-controlled multiplication to
   overflow.
3. Allocates exactly that many typed elements, initially uninitialized.
4. Copies the proven byte range into the allocation and advances the cursor.

Uninitialized allocation avoids zeroing memory that will immediately be
completely overwritten. It carries a strict responsibility: every byte must be
initialized before a value can be observed. Here, the checked, non-overlapping
copy fills the entire allocation; empty arrays skip the copy. The destination
remains an ordinary owning Mojo List after initialization.

The copy uses byte pointers. A payload might begin at byte 13, which is unsuitable
for assuming four- or eight-byte alignment. We copy from that arbitrary byte
address into properly allocated typed storage, without loading a float through a
misaligned typed pointer. Mojo's [memory-copy primitive](https://mojolang.org/docs/std/memory/memory/unsafe_memcpy/)
lets the compiler/runtime implement the transfer efficiently for the CPU.

Raw copying is correct when the host's byte order matches the little-endian
format. A compile-time endian check selects that path; big-endian hosts retain
explicit scalar conversion. This fallback has not been exercised on big-endian
hardware. Raw transfer also preserves NaN payloads and negative zero exactly:
there is no numeric float conversion. Unknown extension payloads are copied as
opaque bytes after their size/count checks.

Encoding has a second allocation problem: appending bytes to a growing output
can repeatedly allocate larger buffers and move the earlier bytes. We now run
the serialization traversal once in **counting mode**, adding fixed scalar
widths, array prefixes and array payload sizes. It inspects lengths rather than
walking the array contents. Every addition is checked against the remaining byte
budget. Then the encoder reserves the exact final byte count and emits the data.

Counting and emitting use the same field-order function. A compile-time boolean
specializes the Writer into a counter or a byte writer, keeping the schema in one
place. This avoids a hand-maintained size formula that could silently miss a new
field or extension. It costs an extra traversal of field metadata, which the
benchmarks must justify against the eliminated buffer growth and copying.
Standalone Writers still support incremental use and enforce the byte limit.

The file does not put every tree's array lengths in a single directory at the
front. A decoder therefore learns each allocation size as it encounters that
array; a separate complete scan is unnecessary for these individually owned
arrays. The encoder already has all the arrays and can calculate its one output
size cheaply. This difference explains the two allocation strategies.

## 3. Reuse validation scratch and inline small checks

Validation still checks field lengths, node kinds, child indices, feature indices,
leaf/category segments, statistics, and output metadata. It then walks each tree
from its root. A `seen` array catches a node visited twice, which indicates a cycle
or shared child; comparing the visited count with the node count catches
unreachable nodes. None of these guarantees were removed.

Previously, every tree allocated a fresh `seen` list, appended zeros individually,
and allocated a fresh traversal stack. Validation now owns one pair of scratch
lists per call. Between trees it clears their contents and reuses their capacity;
the `seen` list is resized and filled with zeros, and the stack begins at the new
root. Capacity grows only when a later tree needs more. The stack grows with the
actual traversal demand rather than reserving an integer for every model node.

The tiny `require` helper is also explicitly inlined. The profile after the first
two changes still attributed noticeable work to calls into it. Inlining exposes
the condition directly in the caller while leaving message construction on the
failure path. This optimization and scratch reuse are measured together as the
third stage; their individual contributions are not isolated.

Scratch is released when validation returns. There is no cached validity flag:
editing public model fields between calls always triggers a fresh validation.
The scratch capacity tracks the largest demand during the call. The old code
also freed each tree's scratch before moving on; the improvement is avoiding
repeated allocation and deallocation, not eliminating simultaneously resident
scratch for every tree. Fewer allocations do not necessarily imply lower process
peak RSS, because the allocator may retain freed memory and model storage still
dominates some cases.

## Scope of verification

The native tests cover all supported wire dtypes, unaligned array starts, empty
arrays, NaN/negative-zero bits, exact output limits, truncated arrays and their
error context, zero-sized extensions, and scratch reuse across different tree
sizes and later mutations. Existing truncated-prefix, corruption, topology and
framework roundtrip checks remain in place. See the results report for upstream
interoperability, the complete timing comparison, and measurement limitations.
