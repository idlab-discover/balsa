"""One operation per process; no parity setup contaminates peak RSS."""
from std.sys import argv
from std.time import perf_counter_ns
from std.benchmark import keep, clobber_memory
from balsa import load, load_editable, save, Limits, ValidationOptions


def execute[dtype: DType](args: List[String]) raises:
    var path = args[1].copy()
    var operation = args[2].copy()
    var options = ValidationOptions(1, enabled=Int(args[3]) != 0)
    var limits = Limits(max_bytes=512 * 1024 * 1024, max_nodes=4_000_000)
    if operation == "load-packed":
        clobber_memory()
        var start = perf_counter_ns()
        var model = load[dtype](path, limits, options)
        clobber_memory()
        var elapsed = perf_counter_ns() - start
        keep(model)
        print(elapsed)
    elif operation == "load-editable":
        clobber_memory()
        var start = perf_counter_ns()
        var model = load_editable[dtype](path, limits, options)
        clobber_memory()
        var elapsed = perf_counter_ns() - start
        keep(model)
        print(elapsed)
    elif operation == "save-editable":
        var model = load_editable[dtype](path, limits, options)
        clobber_memory()
        var start = perf_counter_ns()
        save(model, args[4], limits, options)
        clobber_memory()
        print(perf_counter_ns() - start)
        keep(model)
    elif operation == "save-packed":
        var model = load[dtype](path, limits, options)
        clobber_memory()
        var start = perf_counter_ns()
        save(model, args[4])
        clobber_memory()
        print(perf_counter_ns() - start)
        keep(model)
    elif operation == "convert" or operation == "verify-convert":
        var model = load[dtype](path, limits, ValidationOptions(1, enabled=False))
        clobber_memory()
        var start = perf_counter_ns()
        var editable = model.to_model(options)
        clobber_memory()
        var elapsed = perf_counter_ns() - start
        keep(editable)
        keep(model)
        print(elapsed)
        if operation == "verify-convert":
            save(editable, args[4], limits, options)
    elif operation == "roundtrip-packed":
        var start = perf_counter_ns()
        var model = load[dtype](path, limits, options)
        save(model, args[4])
        clobber_memory()
        print(perf_counter_ns() - start)
        keep(model)
    elif operation == "roundtrip-editable":
        var start = perf_counter_ns()
        var model = load_editable[dtype](path, limits, options)
        save(model, args[4], limits, options)
        clobber_memory()
        print(perf_counter_ns() - start)
        keep(model)
    else:
        raise Error("Unknown operation")


def main() raises:
    var args = List[String]()
    for arg in argv():
        args.append(String(arg))
    if len(args) != 6:
        raise Error("FILE OP CHECKED OUTPUT DTYPE required")
    if args[5] == "float32":
        execute[DType.float32](args)
    elif args[5] == "float64":
        execute[DType.float64](args)
    else:
        raise Error("Unsupported dtype")
