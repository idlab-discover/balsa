"""Pinned Python reference; resident input, owned output, destruction timed."""

import sys
from pathlib import Path
from time import perf_counter_ns
import treelite


def decode_once(data):
    model = treelite.Model.deserialize_bytes(data)
    del model
    return 1


def encode_once(model):
    data = model.serialize_bytes()
    size = len(data)
    del data
    return size


def main():
    path, operation, loops = sys.argv[1:]
    loops = int(loops)
    assert loops > 0 and treelite.__version__ == "4.6.1"
    data = Path(path).read_bytes()
    model = treelite.Model.deserialize_bytes(data)
    assert model.serialize_bytes() == data
    function, value = {"decode": (decode_once, data), "encode": (encode_once, model)}[operation]
    for _ in range(8):
        function(value)
    checksum = 0
    start = perf_counter_ns()
    for _ in range(loops):
        checksum += function(value)
    elapsed = perf_counter_ns() - start
    print(elapsed / 1e9, checksum)


if __name__ == "__main__":
    main()
