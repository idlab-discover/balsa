"""Native codec, malformed input and model behavior tests."""

from std.testing import assert_equal, assert_raises, TestSuite
from balsa.codec import load, decode, encode, read_file, save
from balsa.model import Model, Tree, Extension
from balsa.validation import validate
from balsa.wire import Reader, Writer, Limits


def bytes_of(text: String) -> List[UInt8]:
    var result = List[UInt8]()
    for byte in text.as_bytes():
        result.append(byte)
    return result^


def make_stump() -> Model[DType.float32]:
    var model = Model[DType.float32]()
    model.num_tree = 1
    model.num_feature = 1
    model.task_type = 1
    model.num_target = 1
    model.num_class = [1]
    model.leaf_vector_shape = [1, 1]
    model.target_id = [0]
    model.class_id = [0]
    model.postprocessor = bytes_of("identity")
    model.base_scores = [0.5]
    var tree = Tree[DType.float32]()
    tree.num_nodes = 3
    tree.node_type = [1, 0, 0]
    tree.cleft = [1, -1, -1]
    tree.cright = [2, -1, -1]
    tree.split_index = [0, -1, -1]
    tree.default_left = [1, 0, 0]
    tree.leaf_value = [0.0, -1.25, 2.75]
    tree.threshold = [0.5, 0.0, 0.0]
    tree.cmp = [2, 0, 0]
    tree.category_list_right_child = [0, 0, 0]
    tree.leaf_vector_begin = [0, 0, 0]
    tree.leaf_vector_end = [0, 0, 0]
    tree.category_list_begin = [0, 0, 0]
    tree.category_list_end = [0, 0, 0]
    model.trees.append(tree^)
    return model^


def test_native_model_roundtrip() raises:
    var model = make_stump()
    var bytes = encode(model)
    var restored = decode(bytes.copy())
    assert_equal(encode(restored), bytes)
    save(model, "build/native-stump.tl")


def test_upstream_stump_and_bit_preservation() raises:
    var model = load("tests/fixtures/float32_op2_missing0.tl")
    assert_equal(model.num_tree, UInt64(1))
    assert_equal(model.trees[0].threshold[0], Float32(0.5))
    model.trees[0].leaf_value[1] = Float32(from_bits=UInt32(0x7FC01234))
    model.trees[0].leaf_value[2] = Float32(from_bits=UInt32(0x80000000))
    var bytes = encode(model)
    var restored = decode(bytes.copy())
    assert_equal(
        restored.trees[0].leaf_value[1].to_bits[DType.uint32](),
        UInt32(0x7FC01234),
    )
    assert_equal(
        restored.trees[0].leaf_value[2].to_bits[DType.uint32](),
        UInt32(0x80000000),
    )
    assert_equal(encode(restored), bytes)
    var double_model = load[DType.float64]("tests/fixtures/float64_leaf.tl")
    double_model.trees[0].leaf_value[0] = Float64(
        from_bits=UInt64(0x7FF8000000001234)
    )
    var double_bytes = encode(double_model)
    var double_restored = decode[DType.float64](double_bytes.copy())
    assert_equal(encode(double_restored), double_bytes)


def test_all_truncated_prefixes() raises:
    var bytes = read_file("tests/fixtures/float32_op2_missing0.tl")
    var prefix = List[UInt8]()
    for byte in bytes:
        with assert_raises():
            _ = decode(prefix.copy())
        prefix.append(byte)
    _ = decode(prefix^)


def test_bad_wire_header_and_limits() raises:
    var bytes = read_file("tests/fixtures/float32_op2_missing0.tl")
    var bad = bytes.copy()
    bad[0] = 3
    with assert_raises():
        _ = decode(bad.copy())
    bad = bytes.copy()
    bad[13] = 3
    with assert_raises():
        _ = decode(bad.copy())
    bad = bytes.copy()
    # UInt64 num_tree at byte 14: malicious maximum unsigned count.
    for i in range(14, 22):
        bad[i] = 255
    with assert_raises():
        _ = decode(bad.copy())
    bad = bytes.copy()
    bad.append(0)
    with assert_raises():
        _ = decode(bad.copy())
    with assert_raises():
        _ = decode(bytes.copy(), Limits(max_bytes=20))
    with assert_raises():
        _ = load("tests/fixtures/float32_op2_missing0.tl", Limits(max_bytes=20))
    with assert_raises():
        _ = decode(bytes.copy(), Limits(max_nodes=2))
    with assert_raises():
        _ = decode(bytes.copy(), Limits(max_elements=2))
    with assert_raises():
        _ = decode(bytes.copy(), Limits(max_bytes=-1))
    # num_class count starts at byte 32, independently annotated from v4.
    bad = bytes.copy()
    for i in range(32, 40):
        bad[i] = 255
    with assert_raises():
        _ = decode(bad.copy())


def test_malformed_models() raises:
    var model = make_stump()
    model.trees[0].cleft[0] = 0
    with assert_raises():
        _ = encode(model)
    model.trees[0].cleft[0] = 2
    with assert_raises():
        validate(model)
    model.trees[0].cleft[0] = 5
    with assert_raises():
        validate(model)
    model.trees[0].cleft[0] = 1
    model.trees[0].split_index[0] = 1
    with assert_raises():
        validate(model)
    model.trees[0].split_index[0] = 0
    model.trees[0].default_left[0] = 2
    with assert_raises():
        validate(model)
    model.trees[0].default_left[0] = 1
    model.trees[0].leaf_vector_end[0] = 1
    with assert_raises():
        validate(model)
    model.trees[0].leaf_vector_end[0] = 0
    model.trees[0].cmp[0] = 0
    with assert_raises():
        validate(model)
    model.trees[0].cmp[0] = 2
    model.base_scores = []
    with assert_raises():
        validate(model)


def test_extensions_survive_all_slots() raises:
    var model = make_stump()
    var extension = Extension(bytes_of("future"), 2, 2, bytes_of("abcd"))
    model.extensions.append(extension.copy())
    model.trees[0].tree_extensions.append(extension.copy())
    model.trees[0].node_extensions.append(extension.copy())
    var bytes = encode(model)
    var restored = decode(bytes.copy())
    assert_equal(encode(restored), bytes)
    assert_equal(restored.extensions[0].payload, bytes_of("abcd"))
    save(restored, "build/native-extensions.tl")
    assert_equal(restored.trees[0].tree_extensions[0].count, UInt64(2))
    assert_equal(restored.trees[0].node_extensions[0].element_size, UInt64(2))
    model.extensions[0].count = 3
    with assert_raises():
        _ = encode(model)


def test_extension_overflow_and_negative_count() raises:
    var writer = Writer(Limits())
    writer.scalar[DType.int32](1)
    writer.array[DType.uint8](bytes_of("x"))
    writer.scalar[DType.uint64](UInt64(0xFFFFFFFFFFFFFFFF))
    writer.scalar[DType.uint64](UInt64(0xFFFFFFFFFFFFFFFF))
    var reader = Reader(writer^.finish(), Limits())
    with assert_raises():
        _ = reader.extensions()
    var negative: List[UInt8] = [255, 255, 255, 255]
    var reader2 = Reader(negative^, Limits())
    with assert_raises():
        _ = reader2.extensions()


def test_mutated_checkpoints_are_bounded() raises:
    var bytes = read_file("tests/fixtures/float32_op2_missing0.tl")
    # Deterministic corruption sweep: accepted mutations must remain encodable.
    for offset in range(len(bytes)):
        var mutated = bytes.copy()
        mutated[offset] ^= 128
        var model: Model[DType.float32]
        try:
            model = decode(mutated^)
        except:
            continue
        _ = encode(model)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
