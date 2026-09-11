# Optional automatic model validation

Balsa separates bounded wire parsing from validation of the resulting model.
Automatic model validation is enabled by default. Callers handling trusted or
previously validated data can explicitly skip it through the public options:

```mojo
from balsa import load, save, validate, ValidationOptions

var options = ValidationOptions(enabled=False)
var model = load("trusted.tl", options=options)
validate(model)  # Always checks, independently of the automatic policy.
save(model, "copy.tl", options=options)
```

## Contract

`ValidationOptions.enabled` is a runtime Bool, defaulting to True. Its constructor
argument is keyword-only, preserving existing positional concurrency arguments.
The policy applies per call to typed and automatic-precision decode/load and
encode/save, plus `ModelBuilder.build`. It is neither global state nor a durable
validated property on the mutable model.

With `enabled=False`, these entry points omit their whole-model `validate` call.
This skips metadata consistency, required array lengths, boolean and enum values,
feature and annotation ranges, topology, and category/leaf segment checks.
Returned models retain the same owned typed representation and can be checked
later. Callers must establish the invariants their consumers need, including
after mutation.

Explicit `validate(model, limits, options)` always validates. It uses concurrency
settings but ignores `enabled`: asking directly for validation must not silently
succeed without checking. Concurrency settings are checked when validation runs;
they do not affect a call that skips automatic validation.

## Checks that remain

Decoding retains Reader bounds and allocation checks, supported version/dtype
checks, declared tree and cumulative node limits, positive node counts, array
and extension limits, truncation detection, and trailing-byte rejection. Turning
model validation off does not enable out-of-bounds reads or change wire layout.

Encoding still traverses owned containers and uses the bounded Writer, including
its byte, array and extension checks. Model-level tree/node limits and semantic
consistency checks are part of the skipped validation pass. It can therefore
emit a semantically invalid checkpoint, which default decoding will reject.
Save completes encoding before opening its destination for replacement.

Builder constructors and mutation methods retain their local checks.
`TreeBuilder.build` still requires every slot to be defined; only the final
whole-model pass in `ModelBuilder.build` is optional.

## Rationale and scope

The profiling in [decode optimization](decode-optimization.md) distinguished
parsing cost from Balsa's additional validation work. This policy makes that
distinction available to applications and benchmarks through the existing public
options object. No separate unchecked model type, global switch, configurable
matrix of individual checks, or validation cache is needed.

This does not claim equivalence to every native Treelite check. Benchmarks should
label Balsa validation as enabled or disabled and retain validation of their
fixtures outside the measured loop.

`tools/validation_policy_worker.mojo` accepts an optional final `no-validation`
argument. The original decode worker stays compatible with historical source
snapshots used by the optimization benchmark. Setup and
byte-parity checks remain validated outside timing. Its explicit `validate`
operation still validates even when that argument is supplied.

## Verification

Core regression tests exercise skipped metadata, array-length and topology
checks; default rejection; explicit deferred validation; typed and automatic
file APIs; float32/float64; and builder finalization. Every truncated prefix of
a representative checkpoint still fails with validation disabled, as do bad
headers, trailing bytes, and parser resource-limit violations.

`pixi run check` passed: 25 core tests, 8 framework tests, package compilation,
CLI smoke test and construction example.

## Evidence behind the policy

A four-case paired check on Ryzen 5950X, CPU 0, used seven randomized process
batches and eight operation warmups. Disabling validation reduced serial decode
time 15–22%. For 100,020-node XGBoost, checked/unchecked decode measured
7.75/6.60 ms; for RF multioutput, 9.23/7.72 ms. This isolates the policy's cost
within that session; it is not a universal estimate across tree shapes.
Raw samples and the measured worker hash remain in ignored
`build/validation-policy-benchmark.json`, with the local driver at
`build/benchmark-validation-policy.py`.

The subsequent [full controlled comparison](validation-opt-out-results.md)
replaces the small check as the native/Python Treelite comparison: all 12
checkpoints, encode and decode, 144 pyperf jobs. It reports large RF decode as
overlapping parity and large XGBoost as 4.3% slower than native; the smaller
pilot's point estimates should not be substituted for those results.

Build `tools/validation_policy_worker.mojo` with `mojo build -O3 -I src` and
supply `FILE WORKERS MIN_TREES MIN_NODES LOOPS CALLERS OP [no-validation]`.
Omit the final argument for checked measurements. This tracked worker retains
validated setup and byte-parity checks; the paired pilot preceded extraction
of its unchanged operation helper into a shared import, which was separately
compiled and smoke-tested.
