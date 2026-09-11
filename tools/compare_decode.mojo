"""Differential malformed-input checks against a baseline_balsa source snapshot.

Compile with -I src -I PATH_CONTAINING_BASELINE_BALSA. Keep the snapshot outside
production src. Both decoders must accept the same limits and wire format.
"""
from std.testing import assert_equal
from balsa import decode, encode, Limits, ValidationOptions
from balsa.codec import read_file
from baseline_balsa import (
    decode as reference_decode,
    encode as reference_encode,
    Limits as ReferenceLimits,
    ValidationOptions as ReferenceOptions,
)


def outcome[dtype: DType](data: List[UInt8], workers: Int) raises -> String:
    try:
        var model = decode[dtype](
            data.copy(),
            Limits(max_trees=100, max_nodes=10000),
            ValidationOptions(workers, 0, 0),
        )
        assert_equal(encode(model), data)
    except err:
        return String(err)
    return "OK"


def reference_outcome[dtype: DType](data: List[UInt8]) raises -> String:
    try:
        var model = reference_decode[dtype](
            data.copy(),
            ReferenceLimits(max_trees=100, max_nodes=10000),
            ReferenceOptions(1),
        )
        assert_equal(reference_encode(model), data)
    except err:
        return String(err)
    return "OK"


def compare[dtype: DType](path: String) raises -> Int:
    var data = read_file(path)
    var checked = 0
    for offset in range(len(data)):
        var short = data.copy()
        short.resize(offset, 0)
        assert_equal(outcome[dtype](short, 1), reference_outcome[dtype](short))
        checked += 1
        for mask in [1, 128, 255]:
            var mutated = data.copy()
            mutated[offset] ^= UInt8(mask)
            var expected = reference_outcome[dtype](mutated)
            assert_equal(outcome[dtype](mutated, 1), expected)
            # Force parallel validation on the valid multi-tree cases too.
            assert_equal(outcome[dtype](mutated, 4), expected)
            checked += 2
    print(path, checked)
    return checked


def main() raises:
    var total = 0
    for suffix in ["op2_missing0", "category", "vector", "deep"]:
        total += compare[DType.float32](
            "tests/fixtures/float32_" + suffix + ".tl"
        )
        total += compare[DType.float64](
            "tests/fixtures/float64_" + suffix + ".tl"
        )
    total += compare[DType.float32](
        "tests/fixtures/frameworks/xgboost_regression.tl"
    )
    total += compare[DType.float64](
        "tests/fixtures/frameworks/sklearn_rf_multioutput_regression.tl"
    )
    print("Equivalent outcomes:", total)
