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

## Public-policy timing check

On the Ryzen 5950X, seven randomized process batches per configuration pinned
to CPU 0 gave these median decode times in microseconds. Balsa's checked mode
uses one validation worker. Each process performs eight operation warmups;
measured loops are 1,500 for medium forests and 20 for large forests. Native is
the existing Treelite 4.6.1 worker. These are fresh within-session comparisons,
not timing differences against the earlier report's separate session.

| Forest | Balsa checked | Balsa unchecked | Native Treelite |
| --- | ---: | ---: | ---: |
| XGBoost, 960 nodes | 56.19 | 43.64 | 51.35 |
| RF multioutput, 960 nodes | 59.73 | 47.42 | 62.99 |
| XGBoost, 100,020 nodes | 7,751.74 | 6,602.46 | 6,162.17 |
| RF multioutput, 100,020 nodes | 9,230.78 | 7,723.12 | 7,984.23 |

Skipping model validation lowers time by 15–22% in this sample. Large XGBoost
remains about 7% slower than native; large RF is about 3% faster. This is a
targeted confirmation, not evidence of universal parity across tree shapes.
Raw samples, commands, fixture hashes and worker hash are in the ignored
`build/validation-policy-benchmark.json`; the local driver is
`build/benchmark-validation-policy.py`.

Build and invoke the policy worker with:

```sh
pixi run mojo build -O3 -I src tools/validation_policy_worker.mojo -o build/validation-policy-worker
taskset -c 0 build/validation-policy-worker build/decode-confirmation/xgboost_regression_x1667.tl 1 4096 65536 20 1 decode no-validation
```

Omit the final argument for checked serial decoding. The measured binary was
built before extracting its unchanged operation function into a shared import
from `decode_worker`; the source with that extraction is compiled and smoke-tested
separately.
