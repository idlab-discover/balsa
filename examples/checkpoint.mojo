"""Native checkpoint inspection and roundtrip tool."""

from std.sys import argv
from balsa import decode, save, checkpoint_dtype
from balsa.codec import read_file


def execute[dtype: DType](var bytes: List[UInt8], args: List[String]) raises:
    var model = decode[dtype](bytes^)
    var command = args[1]
    if command == "inspect":
        print("Treelite", model.major, model.minor, model.patch)
        print("trees:", model.num_tree, "features:", model.num_feature)
        print("precision:", "float32" if dtype == DType.float32 else "float64")
        return
    if command == "roundtrip":
        save(model, args[3])
        return


def main() raises:
    var args = List[String]()
    for argument in argv():
        args.append(String(argument))
    if len(args) < 3:
        raise Error("Usage: balsa inspect MODEL | roundtrip MODEL OUT")
    var command = args[1]
    if not (
        (command == "inspect" and len(args) == 3)
        or (command == "roundtrip" and len(args) == 4)
    ):
        raise Error("Invalid command or argument count")
    var bytes = read_file(args[2])
    var dtype = checkpoint_dtype(bytes)
    if dtype == DType.float32:
        execute[DType.float32](bytes^, args)
    else:
        execute[DType.float64](bytes^, args)
