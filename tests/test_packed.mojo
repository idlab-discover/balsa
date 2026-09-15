"""Packed storage ownership, typed views, format checks and semantic parity."""

from std.testing import assert_equal, assert_raises, TestSuite
import balsa.packed as packed
from balsa import decode, encode, ValidationOptions, Limits
from balsa.codec import read_file


def test_packed_roundtrip() raises:
    var data = read_file("tests/fixtures/float32_op2_missing0.tl")
    var model = packed.decode(Span(data))
    assert_equal(packed.encode(model), data)
    var automatic = packed.decode_auto(data.copy())
    packed.save(automatic, "build/packed-auto.tl")
    assert_equal(read_file("build/packed-auto.tl"), data)
    assert_equal(encode(model.to_model()), data)
    assert_equal(model.num_trees(), 1)
    var tree = model.tree(0)
    var editable = decode(data.copy())
    assert_equal(tree.threshold.to_list(), editable.trees[0].threshold)
    assert_equal(tree.cleft.to_list(), editable.trees[0].cleft)
    data.clear()
    assert_equal(tree.num_nodes, editable.trees[0].num_nodes)
    with assert_raises():
        _ = tree.threshold[-1]
    with assert_raises():
        _ = tree.threshold[len(tree.threshold)]
    with assert_raises():
        _ = model.tree(1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


def check_fields[dtype: DType](prefix: String) raises:
    for shape in [
        "deep",
        "leaf",
        "vector",
        "category",
        "multi_target",
        "sigmoid",
    ]:
        var path = "tests/fixtures/" + prefix + "_" + shape + ".tl"
        var bytes = read_file(path)
        var model = packed.load[dtype](path)
        var editable = decode[dtype](bytes.copy())
        assert_equal(packed.encode(model), bytes)
        assert_equal(packed.encode(packed.load_auto(path)), bytes)
        for i in range(model.num_trees()):
            var tree = model.tree(i)
            assert_equal(tree.node_type.to_list(), editable.trees[i].node_type)
            assert_equal(tree.cleft.to_list(), editable.trees[i].cleft)
            assert_equal(tree.cright.to_list(), editable.trees[i].cright)
            assert_equal(
                tree.split_index.to_list(), editable.trees[i].split_index
            )
            assert_equal(
                tree.default_left.to_list(), editable.trees[i].default_left
            )
            assert_equal(
                tree.leaf_value.to_list(), editable.trees[i].leaf_value
            )
            assert_equal(tree.threshold.to_list(), editable.trees[i].threshold)
            assert_equal(tree.cmp.to_list(), editable.trees[i].cmp)
            assert_equal(
                tree.category_list_right_child.to_list(),
                editable.trees[i].category_list_right_child,
            )
            assert_equal(
                tree.leaf_vector.to_list(), editable.trees[i].leaf_vector
            )
            assert_equal(
                tree.leaf_vector_begin.to_list(),
                editable.trees[i].leaf_vector_begin,
            )
            assert_equal(
                tree.leaf_vector_end.to_list(),
                editable.trees[i].leaf_vector_end,
            )
            assert_equal(
                tree.category_list.to_list(), editable.trees[i].category_list
            )
            assert_equal(
                tree.category_list_begin.to_list(),
                editable.trees[i].category_list_begin,
            )
            assert_equal(
                tree.category_list_end.to_list(),
                editable.trees[i].category_list_end,
            )
            assert_equal(
                tree.data_count.to_list(), editable.trees[i].data_count
            )
            assert_equal(
                tree.data_count_present.to_list(),
                editable.trees[i].data_count_present,
            )
            assert_equal(tree.sum_hess.to_list(), editable.trees[i].sum_hess)
            assert_equal(
                tree.sum_hess_present.to_list(),
                editable.trees[i].sum_hess_present,
            )
            assert_equal(tree.gain.to_list(), editable.trees[i].gain)
            assert_equal(
                tree.gain_present.to_list(), editable.trees[i].gain_present
            )
        packed.save(model, "build/packed-roundtrip.tl")
        assert_equal(read_file("build/packed-roundtrip.tl"), bytes)
        var moved = model^
        var independent = moved.to_model()
        independent.trees[0].leaf_value[0] = 123
        assert_equal(packed.encode(moved), bytes)


def test_all_fields_and_precisions() raises:
    check_fields[DType.float32]("float32")
    check_fields[DType.float64]("float64")


def test_packed_extensions() raises:
    from balsa import Extension

    var original = decode(read_file("tests/fixtures/float32_leaf.tl"))
    var extension = Extension([65, 66], 2, 2, [1, 2, 3, 4])
    original.extensions.append(extension.copy())
    original.trees[0].tree_extensions.append(extension.copy())
    original.trees[0].node_extensions.append(extension.copy())
    original.trees[0].node_extensions.append(Extension([], 0, 7, []))
    var bytes = encode(original)
    var model = packed.decode(Span(bytes))
    assert_equal(packed.encode(model), bytes)
    var tree = model.tree(0)
    assert_equal(len(tree.tree_extensions), 1)
    assert_equal(len(tree.node_extensions), 2)
    var node_extension = tree.node_extensions[0]
    assert_equal(node_extension.name.to_list(), extension.name)
    assert_equal(node_extension.payload.to_list(), extension.payload)
    assert_equal(node_extension.count, 2)
    assert_equal(node_extension.element_size, 2)
    assert_equal(len(tree.node_extensions[1].payload), 0)
    with assert_raises():
        _ = tree.node_extensions[2]


def test_packed_floating_bits() raises:
    var single = decode(read_file("tests/fixtures/float32_leaf.tl"))
    for bits in [UInt32(0x80000000), UInt32(0x7FC12345)]:
        single.trees[0].threshold[0] = Float32(from_bits=bits)
        var model = packed.decode(encode(single))
        assert_equal(model.tree(0).threshold[0].to_bits[DType.uint32](), bits)
    var double_model = decode[DType.float64](
        read_file("tests/fixtures/float64_leaf.tl")
    )
    for bits in [UInt64(0x8000000000000000), UInt64(0x7FF8123456789ABC)]:
        double_model.trees[0].threshold[0] = Float64(from_bits=bits)
        var model = packed.decode[DType.float64](encode(double_model))
        assert_equal(model.tree(0).threshold[0].to_bits[DType.uint64](), bits)


def compare_errors(
    data: List[UInt8], limits: Limits, options: ValidationOptions
) raises:
    var ordinary_error = String()
    var packed_error = String()
    try:
        _ = decode(data.copy(), limits, options)
    except err:
        ordinary_error = String(err)
    try:
        _ = packed.decode(data.copy(), limits, options)
    except err:
        packed_error = String(err)
    assert_equal(packed_error, ordinary_error)


def test_packed_truncations_and_limits() raises:
    var data = read_file("tests/fixtures/float32_op2_missing0.tl")
    for enabled in [False, True]:
        var options = ValidationOptions(enabled=enabled)
        for length in range(len(data)):
            var prefix = data.copy()
            prefix.resize(length, 0)
            compare_errors(prefix, Limits(), options)
        compare_errors(data, Limits(max_bytes=14), options)
        compare_errors(data, Limits(max_nodes=1), options)
        compare_errors(data, Limits(max_elements=1), options)
        var trailing = data.copy()
        trailing.append(0)
        compare_errors(trailing, Limits(), options)
    var double_bytes = read_file("tests/fixtures/float64_leaf.tl")
    with assert_raises():
        _ = packed.decode(double_bytes^)


def test_packed_semantic_validation_and_corruption() raises:
    var bytes = read_file("tests/fixtures/float32_op2_missing0.tl")
    var original = decode(bytes.copy())
    var unchecked = ValidationOptions(enabled=False)
    original.trees[0].cleft[0] = 0
    var invalid = encode(original, options=unchecked)
    compare_errors(invalid, Limits(), ValidationOptions())
    var model = packed.decode(invalid.copy(), options=unchecked)
    assert_equal(packed.encode(model), invalid)
    with assert_raises():
        model.validate(unchecked)
    for i in range(len(bytes)):
        var mutated = bytes.copy()
        mutated[i] ^= UInt8(255)
        compare_errors(mutated, Limits(), ValidationOptions(1))
