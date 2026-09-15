"""Validation-only executor benchmark; setup is excluded, first call is reported."""
from std.sys import argv
from std.time import perf_counter_ns
from std.benchmark import keep
from max.algorithm import parallelize
from balsa import (
    Model,
    decode_editable as decode,
    encode,
    validate,
    ValidationOptions,
    Limits,
    checkpoint_dtype,
)
from balsa.codec import read_file


def execute[
    dtype: DType
](data: List[UInt8], args: List[String], limits: Limits) raises:
    var model = decode[dtype](
        data.copy(), limits, ValidationOptions(1, enabled=True)
    )
    var options = ValidationOptions(
        Int(args[2]), Int(args[3]), Int(args[4]), enabled=True
    )
    var loops = Int(args[5])
    var callers = Int(args[6])
    var operation = String(args[7])
    var errors = List[Int](length=callers, fill=0)
    var error_ptr = errors.unsafe_ptr()

    def work(
        caller: Int,
    ) {model, data, limits, options, loops, operation, error_ptr}:
        try:
            for _ in range(loops):
                if operation == "validate":
                    validate(model, limits, options)
                    keep(model)
                elif operation == "encode":
                    var encoded = encode(model, limits, options)
                    keep(encoded)
                else:
                    var decoded = decode[dtype](data.copy(), limits, options)
                    keep(decoded)
        except:
            error_ptr[unsafe_offset=caller] = 1

    var cold = perf_counter_ns()
    validate(model, limits, options)
    cold = perf_counter_ns() - cold
    for _ in range(8):
        validate(model, limits, options)
    var start = perf_counter_ns()
    if callers == 1:
        work(0)
    else:
        parallelize(work, callers, callers)
    var elapsed = perf_counter_ns() - start
    for error in errors:
        if error != 0:
            raise Error("Benchmark validation/codec failed")
    # Verify byte parity outside timing.
    if encode(model, limits, options) != data:
        raise Error("Byte parity failed")
    print(cold, Float64(elapsed) / Float64(loops * callers))


def main() raises:
    var args = List[String]()
    for arg in argv():
        args.append(String(arg))
    if len(args) != 8:
        raise Error(
            "Usage: worker FILE WORKERS MIN_TREES MIN_NODES LOOPS CALLERS OP"
        )
    var limits = Limits(max_bytes=512 * 1024 * 1024, max_nodes=4_000_000)
    var data = read_file(args[1], limits)
    if checkpoint_dtype(data, limits) == DType.float32:
        execute[DType.float32](data, args, limits)
    else:
        execute[DType.float64](data, args, limits)
