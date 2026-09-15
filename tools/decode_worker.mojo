"""Matched codec timing: serial setup, eight operation warmups, owned outputs."""
from std.sys import argv
from std.time import perf_counter_ns
from std.benchmark import keep, clobber_memory
from balsa import (
    Model,
    decode_editable as decode,
    decode_into,
    encode,
    validate,
    ValidationOptions,
    Limits,
    checkpoint_dtype,
)
from balsa.codec import read_file


@no_inline
def once[
    dtype: DType
](
    data: List[UInt8],
    mut model: Model[dtype],
    limits: Limits,
    options: ValidationOptions,
    operation: String,
) raises -> UInt64:
    if operation == "decode":
        var decoded = decode[dtype](data.copy(), limits, options)
        keep(decoded)
        return 1
    elif operation == "borrowed":
        var decoded = decode[dtype](Span(data), limits, options)
        keep(decoded)
        return 1
    elif operation == "reuse":
        decode_into(model, Span(data), limits, options)
        keep(model)
        return 1
    elif operation == "cold-into":
        var decoded = Model[dtype]()
        decode_into(decoded, Span(data), limits, options)
        keep(decoded)
        return 1
    elif operation == "encode":
        var encoded = encode(model, limits, options)
        keep(encoded)
        return UInt64(len(encoded))
    elif operation == "validate":
        validate(model, limits, options)
        keep(model)
        return 1
    raise Error("Unknown operation")


def execute[
    dtype: DType
](data: List[UInt8], args: List[String], limits: Limits) raises:
    var model = decode[dtype](
        data.copy(), limits, ValidationOptions(1, enabled=True)
    )
    if encode(model, limits, ValidationOptions(1, enabled=True)) != data:
        raise Error("Byte parity failed")
    var options = ValidationOptions(
        Int(args[2]), Int(args[3]), Int(args[4]), enabled=True
    )
    var loops = Int(args[5])
    if loops <= 0 or Int(args[6]) != 1:
        raise Error("Positive loops and exactly one caller required")
    var operation = args[7].copy()
    var cold = perf_counter_ns()
    validate(model, limits, options)
    cold = perf_counter_ns() - cold
    for _ in range(8):
        _ = once(data, model, limits, options, operation)
    clobber_memory()
    var start = perf_counter_ns()
    var checksum = UInt64(0)
    for _ in range(loops):
        checksum += once(data, model, limits, options, operation)
    clobber_memory()
    var elapsed = perf_counter_ns() - start
    var expected = UInt64(len(data)) if operation == "encode" else UInt64(1)
    if checksum != expected * UInt64(loops):
        raise Error("Operation checksum failed")
    print(cold, Float64(elapsed) / Float64(loops))


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
