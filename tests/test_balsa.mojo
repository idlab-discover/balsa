"""Native codec, malformed input and model behavior tests."""

from std.testing import assert_equal, assert_raises, TestSuite
from balsa.codec import load, decode, encode, read_file, save
from balsa import (
    ModelBuilder,
    TreeBuilder,
    Operator,
    NodeType,
    TaskType,
    TypeInfo,
    load_auto,
    decode_auto,
    checkpoint_dtype,
)
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


def test_builder_matches_raw_stump() raises:
    var builder = ModelBuilder(num_feature=1, base_scores=[0.5])
    var tree = TreeBuilder(num_nodes=3)
    # Forward references and out-of-order definitions retain node IDs.
    tree.leaf(2, 2.75)
    tree.numerical_split(
        0,
        feature=0,
        threshold=0.5,
        left=1,
        right=2,
        op=Operator.LT,
        default_left=True,
    )
    tree.leaf(1, -1.25)
    builder.add_tree(tree^.build())
    var model = builder^.build()
    assert_equal(encode(model), encode(make_stump()))
    assert_equal(model.task_type, TaskType.REGRESSOR)
    assert_equal(model.trees[0].node_type[0], NodeType.NUMERICAL)
    save(model, "build/builder-stump.tl")


def test_builder_vector_categories_and_borrowed_fields() raises:
    var builder = ModelBuilder[DType.float64](
        num_feature=2,
        task_type=TaskType.MULTI_CLF,
        num_class=[2, 2],
        leaf_vector_shape=[2, 2],
        postprocessor="softmax",
        average_tree_output=True,
    )
    var tree = TreeBuilder[DType.float64](3)
    tree.categorical_split(
        0,
        feature=1,
        categories=[1, 7, 42],
        left=1,
        right=2,
        categories_right=True,
        default_left=True,
    )
    tree.leaf_vector(1, [0.1, 0.2, 0.3, 0.4])
    tree.leaf_vector(2, [0.5, 0.6, 0.7, 0.8])
    builder.add_tree(tree^.build(), target_id=-1, class_id=-1)
    var model = builder^.build()
    assert_equal(model.num_target, Int32(2))
    assert_equal(len(model.base_scores), 4)
    assert_equal(model.threshold_type, TypeInfo.FLOAT64)
    # Function arguments and for iteration borrow without copying trees.
    for tree in model.trees:
        var categories = tree.categories(0)
        assert_equal(len(categories), 3)
        assert_equal(categories[2], UInt32(42))
        var values = tree.leaf_values(2)
        assert_equal(values[3], Float64(0.8))
        assert_equal(len(tree.leaf_values(0)), 0)
    var model2 = decode_auto(encode(model))
    assert_equal(encode(model2), encode(model))
    save(model2, "build/builder-vector.tl")
    # Views also work safely after direct field edits, with checked errors.
    with assert_raises():
        _ = model.trees[0].categories(-1)
    with assert_raises():
        _ = model.trees[0].leaf_values(3)
    model.trees[0].category_list_end[0] = UInt64(0xFFFFFFFFFFFFFFFF)
    with assert_raises():
        _ = model.trees[0].categories(0)
    model.trees[0].leaf_vector_begin[1] = 5
    with assert_raises():
        _ = model.trees[0].leaf_values(1)
    model.trees[0].leaf_vector_end = []
    with assert_raises():
        _ = model.trees[0].leaf_values(0)


def test_text_access_preserves_bytes() raises:
    var model = make_stump()
    assert_equal(model.postprocessor_name(), "identity")
    model.set_postprocessor_name("future_é🔥")
    model.set_attributes_text('{"name":"é🔥"}')
    var restored = decode(encode(model))
    assert_equal(restored.postprocessor_name(), "future_é🔥")
    assert_equal(restored.attributes_text(), '{"name":"é🔥"}')
    model.postprocessor = [255]
    model.attributes = [192, 128]
    with assert_raises():
        _ = model.postprocessor_name()
    with assert_raises():
        _ = model.attributes_text()
    # Text errors never prevent lossless raw-byte transport.
    var bytes = encode(model)
    var raw = decode(bytes.copy())
    assert_equal(encode(raw), bytes)
    model.set_postprocessor_name("")
    assert_equal(model.postprocessor_name(), "")


def test_auto_precision_and_limits() raises:
    for precision in ["float32", "float64"]:
        for fixture in [
            "op2_missing0",
            "leaf",
            "category",
            "vector",
            "deep",
            "sigmoid",
            "multi_target",
        ]:
            var path = "tests/fixtures/" + precision + "_" + fixture + ".tl"
            var bytes = read_file(path)
            var model = load_auto(path)
            assert_equal(encode(model), bytes)
            assert_equal(
                model.isa[Model[DType.float32]](), precision == "float32"
            )
            assert_equal(
                checkpoint_dtype(bytes) == DType.float64, precision == "float64"
            )
    var bytes = read_file("tests/fixtures/float32_leaf.tl")
    with assert_raises():
        _ = decode_auto(bytes.copy(), Limits(max_bytes=14))
    with assert_raises():
        _ = load_auto("tests/fixtures/float32_leaf.tl", Limits(max_bytes=14))
    with assert_raises():
        _ = decode_auto(bytes.copy(), Limits(max_nodes=0))
    var prefix = List[UInt8]()
    for i in range(14):
        with assert_raises():
            _ = decode_auto(prefix.copy())
        prefix.append(bytes[i])
    bytes[13] = TypeInfo.FLOAT64
    with assert_raises():
        _ = decode_auto(bytes.copy())
    bytes[12] = TypeInfo.UINT32
    bytes[13] = TypeInfo.UINT32
    with assert_raises():
        _ = decode_auto(bytes.copy())
    bytes[12] = TypeInfo.FLOAT32
    bytes[13] = TypeInfo.FLOAT32
    bytes[0] = 3
    with assert_raises():
        _ = decode_auto(bytes.copy())
    with assert_raises():
        _ = load[DType.float32]("tests/fixtures/float64_leaf.tl")


def test_builder_rejects_invalid_construction() raises:
    with assert_raises():
        _ = TreeBuilder(0)
    with assert_raises():
        _ = TreeBuilder(3, Limits(max_nodes=2))
    with assert_raises():
        _ = ModelBuilder(1, num_class=[0])
    with assert_raises():
        _ = ModelBuilder(1, num_class=[2], base_scores=[1.0])
    with assert_raises():
        _ = ModelBuilder(1, num_class=[3], limits=Limits(max_elements=2))
    var tree = TreeBuilder(3)
    with assert_raises():
        tree.leaf(-1, 1.0)
    with assert_raises():
        tree.numerical_split(
            0, feature=0, threshold=1, left=1, right=2, op=Operator.NONE
        )
    with assert_raises():
        tree.numerical_split(0, feature=0, threshold=1, left=0, right=2)
    tree.leaf(1, 1)
    with assert_raises():
        tree.leaf(1, 2)
    with assert_raises():
        _ = tree^.build()
    # All slots defined, but disconnected nodes still fail final validation.
    var builder = ModelBuilder(1)
    var disconnected = TreeBuilder(2)
    disconnected.leaf(0, 1)
    disconnected.leaf(1, 2)
    builder.add_tree(disconnected^.build())
    with assert_raises():
        _ = builder^.build()
    var vector_model = ModelBuilder(1, num_class=[2], leaf_vector_shape=[1, 2])
    var vector_tree = TreeBuilder(1)
    vector_tree.leaf_vector(0, [1.0])
    vector_model.add_tree(vector_tree^.build(), class_id=-1)
    with assert_raises():
        _ = vector_model^.build()


def check_bulk_array[dtype: DType](values: List[SIMD[dtype, 1]]) raises:
    # The scalar encoder is independent of the bulk copy path. A one-byte
    # prefix deliberately makes every multi-byte payload unaligned.
    var bulk = Writer(Limits())
    var scalar = Writer(Limits())
    bulk.scalar[DType.uint8](42)
    scalar.scalar[DType.uint8](42)
    bulk.array[dtype](values)
    scalar.scalar[DType.uint64](UInt64(len(values)))
    for value in values:
        scalar.scalar[dtype](value)
    var bytes = bulk^.finish()
    assert_equal(bytes, scalar^.finish())
    var reader = Reader(bytes.copy(), Limits())
    assert_equal(reader.scalar[DType.uint8](), UInt8(42))
    var restored = reader.array[dtype]()
    var roundtrip = Writer(Limits())
    roundtrip.scalar[DType.uint8](42)
    roundtrip.array[dtype](restored)
    assert_equal(roundtrip^.finish(), bytes)
    assert_equal(reader.pos, len(bytes))


def test_bulk_arrays_unaligned_and_bits() raises:
    check_bulk_array[DType.uint8]([0, 255])
    check_bulk_array[DType.int8]([-128, 127])
    check_bulk_array[DType.int32]([-2147483648, 2147483647])
    check_bulk_array[DType.uint32]([0, 0xFFFFFFFF])
    check_bulk_array[DType.uint64]([0, 0xFFFFFFFFFFFFFFFF])
    check_bulk_array[DType.float32](
        [
            Float32(from_bits=UInt32(0x7FC01234)),
            Float32(from_bits=UInt32(0x80000000)),
            Float32(from_bits=UInt32(0x7F800000)),
        ]
    )
    check_bulk_array[DType.float64](
        [
            Float64(from_bits=UInt64(0x7FF8000000001234)),
            Float64(from_bits=UInt64(0x8000000000000000)),
            Float64(from_bits=UInt64(0xFFF0000000000000)),
        ]
    )
    check_bulk_array[DType.float64]([])


def test_bulk_limits_and_error_context() raises:
    var writer = Writer(Limits(max_bytes=16, max_elements=2))
    writer.array[DType.uint32]([1, 2])
    assert_equal(len(writer.data), 16)
    with assert_raises():
        writer.scalar[DType.uint8](0)
    var short_writer = Writer(Limits(max_bytes=15))
    with assert_raises():
        short_writer.array[DType.uint32]([1, 2])
    var too_many = Writer(Limits(max_elements=1))
    with assert_raises():
        too_many.array[DType.uint8]([1, 2])
    var bytes = writer^.finish()
    _ = bytes.pop()
    var reader = Reader(bytes^, Limits())
    reader.tree_id = 7
    reader.field = "threshold"
    var failed = False
    try:
        _ = reader.array[DType.uint32]()
    except err:
        failed = True
        assert_equal(
            String(err),
            (
                "Malformed checkpoint at byte 8 (tree[7].threshold): truncated"
                " array"
            ),
        )
    assert_equal(failed, True)
    var model = make_stump()
    var encoded = encode(model)
    assert_equal(encode(model, Limits(max_bytes=len(encoded))), encoded)
    with assert_raises():
        _ = encode(model, Limits(max_bytes=len(encoded) - 1))


def test_validation_scratch_resets_between_trees_and_calls() raises:
    var model = make_stump()
    var leaf = load("tests/fixtures/float32_leaf.tl")
    model.trees.append(leaf.trees[0].copy())
    model.trees.append(model.trees[0].copy())
    model.num_tree = 3
    model.target_id = [0, 0, 0]
    model.class_id = [0, 0, 0]
    validate(model)
    validate(model)
    # A later tree must still reject shared children after scratch reuse.
    model.trees[2].cleft[0] = 2
    with assert_raises():
        validate(model)
    model.trees[2].cleft[0] = 0
    with assert_raises():
        validate(model)
    model.trees[2].cleft[0] = 1
    validate(model)


def test_zero_sized_extensions() raises:
    var model = make_stump()
    model.extensions.append(Extension([], 0, 7, []))
    model.trees[0].node_extensions.append(
        Extension(bytes_of("empty"), 8, 0, [])
    )
    var bytes = encode(model)
    var restored = decode(bytes.copy())
    assert_equal(encode(restored), bytes)
    assert_equal(restored.extensions[0].count, UInt64(7))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
