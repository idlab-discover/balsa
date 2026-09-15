"""Matched codec timing: serial setup, eight operation warmups, owned outputs."""
from std.sys import argv
from std.time import perf_counter_ns
from std.benchmark import clobber_memory
from balsa import (
    decode_editable as decode,
    encode,
    validate,
    ValidationOptions,
    Limits,
    checkpoint_dtype,
)
from balsa.codec import read_file


from decode_worker import once


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
    if len(args) == 9:
        if args[8] != "no-validation":
            raise Error("Expected no-validation")
        options.enabled = False
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
    if encode(model, limits) != data:
        raise Error("Post-operation byte parity failed")
    var expected = UInt64(len(data)) if operation == "encode" else UInt64(1)
    if checksum != expected * UInt64(loops):
        raise Error("Operation checksum failed")
    print(cold, Float64(elapsed) / Float64(loops))


def main() raises:
    var args = List[String]()
    for arg in argv():
        args.append(String(arg))
    if len(args) != 8 and len(args) != 9:
        raise Error(
            "Usage: worker FILE WORKERS MIN_TREES MIN_NODES LOOPS CALLERS OP"
            " [no-validation]"
        )
    var limits = Limits(max_bytes=512 * 1024 * 1024, max_nodes=4_000_000)
    var data = read_file(args[1], limits)
    if checkpoint_dtype(data, limits) == DType.float32:
        execute[DType.float32](data, args, limits)
    else:
        execute[DType.float64](data, args, limits)
