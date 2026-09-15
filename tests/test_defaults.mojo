"""Public 0.2 storage defaults and explicit semantic safety contracts."""

from std.testing import assert_equal, assert_raises, TestSuite
from balsa import (
    decode,
    decode_auto,
    load,
    load_auto,
    encode,
    save,
    load_editable,
    decode_editable,
    decode_into,
    Model,
    PackedModel,
    ValidationOptions,
    Limits,
    validate,
    version,
)
from balsa.codec import read_file


def check_precision[dtype: DType](path: String) raises:
    var data = read_file(path)
    var model: PackedModel[dtype] = load[dtype](path)
    assert_equal(encode(model), data)
    var borrowed: PackedModel[dtype] = decode[dtype](Span(data))
    var consumed: PackedModel[dtype] = decode[dtype](data.copy())
    assert_equal(encode(borrowed), data)
    assert_equal(encode(consumed), data)
    var automatic = decode_auto(Span(data))
    assert_equal(automatic.isa[PackedModel[dtype]](), True)
    assert_equal(encode(automatic), data)
    var owned_auto = decode_auto(data.copy())
    assert_equal(encode(owned_auto), data)
    save(automatic, "build/default-auto.tl")
    assert_equal(encode(load_auto("build/default-auto.tl")), data)
    var editable: Model[dtype] = model.to_model()
    editable.trees[0].leaf_value[0] = 123
    assert_equal(encode(model), data)
    var safety = ValidationOptions(enabled=True)
    var checked = load[dtype](path, options=safety)
    checked.validate()
    assert_equal(encode(checked), data)
    save(editable, "build/default-edited.tl", options=safety)
    assert_equal(
        encode(load[dtype]("build/default-edited.tl")), encode(editable)
    )


def test_public_storage_defaults() raises:
    assert_equal(version(), "0.2.0")
    assert_equal(ValidationOptions().enabled, False)
    check_precision[DType.float32]("tests/fixtures/float32_leaf.tl")
    check_precision[DType.float64]("tests/fixtures/float64_leaf.tl")


def test_default_semantics_are_explicit() raises:
    var checked = ValidationOptions(enabled=True)
    for fault in range(3):
        var editable = load_editable("tests/fixtures/float32_op2_missing0.tl")
        if fault == 0:
            editable.num_feature = -1
        elif fault == 1:
            editable.trees[0].default_left.clear()
        else:
            editable.trees[0].cleft[0] = 0
        # Default editable output and packed storage preserve semantic errors.
        var invalid = encode(editable)
        var model = decode(invalid.copy())
        assert_equal(encode(model), invalid)
        save(model, "build/default-invalid.tl")
        assert_equal(encode(load("build/default-invalid.tl")), invalid)
        var fields = decode_editable(invalid.copy())
        assert_equal(encode(fields), invalid)
        decode_into(fields, Span(invalid))
        with assert_raises():
            _ = decode(invalid.copy(), options=checked)
        with assert_raises():
            _ = decode_auto(Span(invalid), options=checked)
        with assert_raises():
            _ = load_auto("build/default-invalid.tl", options=checked)
        with assert_raises():
            _ = encode(editable, options=checked)
        with assert_raises():
            validate(fields)
        with assert_raises():
            model.validate()
        with assert_raises():
            _ = model.to_model()
        var unchecked_copy = model.to_model(ValidationOptions(enabled=False))
        assert_equal(encode(unchecked_copy), invalid)


def test_default_wire_protections() raises:
    var data = read_file("tests/fixtures/float32_op2_missing0.tl")
    for length in range(len(data)):
        var prefix = data.copy()
        prefix.resize(length, 0)
        with assert_raises():
            _ = decode(prefix^)
    for offset in [0, 12, 13]:
        var invalid = data.copy()
        invalid[offset] = 255
        with assert_raises():
            _ = decode_auto(invalid^)
    var trailing = data.copy()
    trailing.append(0)
    with assert_raises():
        _ = decode(trailing^)
    for limits in [
        Limits(max_bytes=14),
        Limits(max_elements=1),
        Limits(max_nodes=1),
        Limits(max_trees=0),
        Limits(max_bytes=-1),
    ]:
        with assert_raises():
            _ = decode(data.copy(), limits)
        with assert_raises():
            _ = decode_auto(Span(data), limits)
    with assert_raises():
        _ = load("tests/fixtures/float64_leaf.tl")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
