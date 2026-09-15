"""Matched fresh decode/destruction and validation-off encode measurements."""

from std.sys import argv
from std.time import perf_counter_ns
from std.benchmark import keep, clobber_memory
from balsa import (
    Model,
    decode_editable as decode,
    encode,
    Limits,
    ValidationOptions,
    checkpoint_dtype,
)
from balsa.codec import read_file
import balsa.packed as packed
import balsa


@no_inline
def once[
    dtype: DType
](
    data: List[UInt8],
    model: Model[dtype],
    stored: packed.PackedModel[dtype],
    limits: Limits,
    options: ValidationOptions,
    operation: String,
) raises -> UInt64:
    if operation == "default-decode":
        var decoded = balsa.decode[dtype](data.copy(), limits)
        keep(decoded)
        return 1
    elif operation == "checked-decode":
        var decoded = balsa.decode[dtype](data.copy(), limits, options)
        keep(decoded)
        return 1
    elif operation == "default-encode":
        var encoded = balsa.encode(stored)
        keep(encoded)
        return UInt64(len(encoded))
    elif operation == "packed-decode":
        var decoded = packed.decode[dtype](data.copy(), limits, options)
        keep(decoded)
        return 1
    elif operation == "decode":
        var decoded = decode[dtype](data.copy(), limits, options)
        keep(decoded)
        return 1
    elif operation == "borrowed":
        var decoded = decode[dtype](Span(data), limits, options)
        keep(decoded)
        return 1
    elif operation == "encode":
        var encoded = encode(model, limits, options)
        keep(encoded)
        return UInt64(len(encoded))
    elif operation == "packed-encode":
        if options.enabled:
            raise Error("Packed encoding is measured without revalidation")
        var encoded = packed.encode(stored)
        keep(encoded)
        return UInt64(len(encoded))
    raise Error("Unknown operation")


def execute[
    dtype: DType
](data: List[UInt8], args: List[String], limits: Limits) raises:
    var model = decode[dtype](
        Span(data), limits, ValidationOptions(1, enabled=True)
    )
    var stored = packed.decode[dtype](
        data.copy(), limits, ValidationOptions(1, enabled=True)
    )
    if encode(model, limits) != data or packed.encode(stored) != data:
        raise Error("Byte parity failed")
    var options = ValidationOptions(1, enabled=Int(args[3]) != 0)
    var loops = Int(args[4])
    if loops <= 0:
        raise Error("Positive loops required")
    for _ in range(8):
        _ = once(data, model, stored, limits, options, args[2])
    clobber_memory()
    var start = perf_counter_ns()
    var checksum = UInt64(0)
    for _ in range(loops):
        checksum += once(data, model, stored, limits, options, args[2])
    clobber_memory()
    var elapsed = perf_counter_ns() - start
    var expected = (
        UInt64(len(data)) if args[2] == "encode"
        or args[2] == "packed-encode"
        or args[2] == "default-encode" else UInt64(1)
    )
    if checksum != expected * UInt64(loops):
        raise Error("Operation checksum failed")
    print(Float64(elapsed) / Float64(loops))


def main() raises:
    var args = List[String]()
    for arg in argv():
        args.append(String(arg))
    if len(args) != 5:
        raise Error("Usage: worker FILE OP VALIDATION LOOPS")
    var limits = Limits(max_bytes=512 * 1024 * 1024, max_nodes=4_000_000)
    var data = read_file(args[1], limits)
    if checkpoint_dtype(data, limits) == DType.float32:
        execute[DType.float32](data, args, limits)
    else:
        execute[DType.float64](data, args, limits)
