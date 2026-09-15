"""Native codec, malformed input and model behavior tests."""

from std.testing import assert_equal, assert_raises, TestSuite
from std.sys import simd_width_of
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
    decode_into,
    checkpoint_dtype,
)
from balsa.model import Model, Tree, Extension
from balsa.validation import validate, check_bool
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
    var input_bytes = writer^.finish()
    var reader = Reader(Span(input_bytes), Limits())
    with assert_raises():
        _ = reader.extensions()
    var negative: List[UInt8] = [255, 255, 255, 255]
    var reader2 = Reader(Span(negative), Limits())
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
    var reader = Reader(Span(bytes), Limits())
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
    var reader = Reader(Span(bytes), Limits())
    reader.tree_id = 7
    var destination: List[UInt32] = [99]
    var failed = False
    try:
        reader.read["threshold"](destination)
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
    assert_equal(len(destination), 1)
    assert_equal(destination[0], 99)
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


def check_borrowed_reuse[dtype: DType](prefix: String) raises:
    var destination = Model[dtype]()
    for shape in ["deep", "leaf", "vector", "category", "multi_target", "deep"]:
        var data = read_file("tests/fixtures/" + prefix + "_" + shape + ".tl")
        var borrowed = decode[dtype](Span(data))
        assert_equal(encode(borrowed), data)
        assert_equal(encode(decode_auto(Span(data))), data)
        assert_equal(checkpoint_dtype(Span(data)), dtype)
        decode_into(destination, Span(data))
        assert_equal(encode(destination), data)
        # Repeating a shape must preserve the existing payload allocation.
        var address = Int(destination.trees[0].leaf_value.unsafe_ptr())
        var capacity = destination.trees[0].leaf_value.capacity()
        decode_into(destination, Span(data))
        assert_equal(Int(destination.trees[0].leaf_value.unsafe_ptr()), address)
        assert_equal(destination.trees[0].leaf_value.capacity(), capacity)
        assert_equal(encode(destination), data)
        var expected = data.copy()
        data.clear()
        assert_equal(encode(borrowed), expected)
        assert_equal(encode(destination), expected)
    # The last input has gone out of scope; both storage and origins are owned.
    validate(destination)


def test_borrowed_decoding_and_reused_storage() raises:
    check_borrowed_reuse[DType.float32]("float32")
    check_borrowed_reuse[DType.float64]("float64")


def test_reuse_extensions_and_tree_counts() raises:
    var model = make_stump()
    model.extensions.append(Extension(bytes_of("name"), 1, 4, bytes_of("data")))
    model.trees[0].tree_extensions = model.extensions.copy()
    model.trees[0].node_extensions = model.extensions.copy()
    var data = encode(model)
    var destination = decode(Span(data))
    var address = Int(destination.extensions[0].payload.unsafe_ptr())
    decode_into(destination, Span(data))
    assert_equal(Int(destination.extensions[0].payload.unsafe_ptr()), address)
    assert_equal(encode(destination), data)
    for count in [3, 1, 4, 2]:
        while len(model.trees) < count:
            model.trees.append(model.trees[0].copy())
        while len(model.trees) > count:
            _ = model.trees.pop()
        model.num_tree = UInt64(count)
        model.target_id.resize(count, 0)
        model.class_id.resize(count, 0)
        model.extensions.clear()
        model.trees[0].tree_extensions.clear()
        model.trees[0].node_extensions.clear()
        data = encode(model)
        decode_into(destination, Span(data))
        assert_equal(encode(destination), data)


def test_reuse_failure_diagnostics_and_recovery() raises:
    from balsa import ValidationOptions

    var model = make_stump()
    model.extensions.append(Extension(bytes_of("name"), 1, 4, bytes_of("data")))
    var data = encode(model)
    var destination = make_stump()
    for enabled in [True, False]:
        var options = ValidationOptions(enabled=enabled)
        for length in range(len(data)):
            var prefix = data.copy()
            prefix.resize(length, 0)
            var expected = String()
            try:
                _ = decode(prefix.copy(), options=options)
            except err:
                expected = String(err)
            assert_equal(expected != "", True)
            var actual = String()
            try:
                decode_into(destination, Span(prefix), options=options)
            except err:
                actual = String(err)
            assert_equal(actual, expected)
            decode_into(destination, Span(data), options=options)
            assert_equal(encode(destination), data)
        with assert_raises():
            decode_into(destination, Span(data), Limits(max_bytes=14), options)
        with assert_raises():
            decode_into(destination, Span(data), Limits(max_nodes=1), options)
    model.num_feature = -1
    var invalid = encode(model, options=ValidationOptions(enabled=False))
    with assert_raises():
        decode_into(destination, Span(invalid))
    decode_into(destination, Span(data))
    assert_equal(encode(destination), data)


def validation_error(
    model: Model[DType.float32], workers: Int, limits: Limits = Limits()
) raises -> String:
    from balsa import ValidationOptions

    try:
        validate(model, limits, ValidationOptions(workers, 0, 0))
    except err:
        return String(err)
    return ""


def test_parallel_validation_error_precedence() raises:
    # Force the executor even for small forests, including incomplete last batches.
    from balsa import ValidationOptions

    for count in [2, 3, 7, 16]:
        var valid = make_stump()
        for _ in range(1, count):
            valid.trees.append(valid.trees[0].copy())
            valid.target_id.append(0)
            valid.class_id.append(0)
        valid.num_tree = UInt64(count)
        for workers in [2, 4, 8]:
            var options = ValidationOptions(workers, 0, 0)
            validate(valid, Limits(), options)
            var bytes = encode(valid, Limits(), options)
            var decoded = decode(bytes.copy(), Limits(), options)
            assert_equal(encode(decoded), bytes)
            for scenario in range(9):
                var model = valid.copy()
                if scenario == 0:
                    model.trees[0].cleft[0] = 0  # cycle
                    model.target_id[count - 1] = 999
                elif scenario == 1:
                    model.trees[0].node_type.clear()
                    model.trees[count - 1].num_nodes = 0
                elif scenario == 2:
                    model.target_id[0] = 999
                    model.trees[count - 1].node_type.clear()
                elif scenario == 3:
                    model.trees[0].default_left[0] = 2
                    model.trees[count - 1].node_type.clear()
                elif scenario == 4:
                    model.trees[count - 1].category_list_end[0] = 1
                elif scenario == 5:
                    model.trees[count - 1].cright[0] = 1  # shared child
                elif scenario == 6:
                    model.trees[0].node_type.clear()
                    model.num_feature = -1  # global metadata always first
                elif scenario == 7:
                    model.class_id[count - 1] = 999
                else:
                    model.trees[count - 1].gain_present.append(1)
                var expected = validation_error(model, 1)
                assert_equal(expected.byte_length() > 0, True)
                for _ in range(10):
                    assert_equal(validation_error(model, workers), expected)
            var limited = valid.copy()
            limited.trees[0].node_type.clear()
            var limits = Limits(max_nodes=3)
            assert_equal(
                validation_error(limited, workers, limits),
                validation_error(limited, 1, limits),
            )
            assert_equal(
                validation_error(valid, workers, limits),
                validation_error(valid, 1, limits),
            )
            # No error or traversal state survives the previous invalid calls.
            validate(valid, Limits(), options)


def test_validation_options() raises:
    from balsa import ValidationOptions

    var model = make_stump()
    with assert_raises():
        validate(model, Limits(), ValidationOptions(0))
    with assert_raises():
        validate(model, Limits(), ValidationOptions(2, -1, 0))
    with assert_raises():
        validate(model, Limits(), ValidationOptions(2, 0, -1))

    for workers in [1, 4]:
        var builder = ModelBuilder(1)
        builder.add_tree(model.trees[0].copy())
        builder.add_tree(model.trees[0].copy())
        var built = builder^.build(ValidationOptions(workers, 0, 0))
        assert_equal(len(built.trees), 2)
    var builder = ModelBuilder(1)
    with assert_raises():
        _ = builder^.build(ValidationOptions(0))


def test_parallel_validation_precisions_and_shapes() raises:
    from balsa import ValidationOptions

    for path in [
        "tests/fixtures/frameworks/xgboost_regression.tl",
        "tests/fixtures/frameworks/sklearn_rf_multioutput_regression.tl",
        "tests/fixtures/frameworks/sklearn_rf_multiclass.tl",
        "tests/fixtures/frameworks/lightgbm_categorical.tl",
    ]:
        var data = read_file(path)
        for workers in [2, 4, 8]:
            var options = ValidationOptions(workers, 0, 0)
            var model = decode_auto(data.copy(), Limits(), options)
            assert_equal(encode(model, Limits(), options), data)
            save(model, "build/parallel-roundtrip.tl", Limits(), options)
            var loaded = load_auto(
                "build/parallel-roundtrip.tl", Limits(), options
            )
            assert_equal(encode(loaded), data)


def test_parallel_validation_simultaneous_callers() raises:
    from max.algorithm import parallelize

    var model = make_stump()
    for _ in range(31):
        model.trees.append(model.trees[0].copy())
        model.target_id.append(0)
        model.class_id.append(0)
    model.num_tree = 32
    model.trees[5].node_type.clear()
    model.trees[20].default_left[0] = 2
    var expected = validation_error(model, 1)
    var errors = List[String](length=4, fill=String())
    var error_ptr = errors.unsafe_ptr()

    def work(caller: Int) {model, expected, error_ptr}:
        try:
            for _ in range(20):
                var actual = validation_error(model, 2)
                if actual != expected:
                    error_ptr[unsafe_offset=caller] = (
                        "Unexpected validation result: " + actual
                    )
                    return
        except err:
            error_ptr[unsafe_offset=caller] = String(err)

    parallelize(work, 4, 4)
    for error in errors:
        assert_equal(error, "")


def check_scalar_reads[dtype: DType]() raises:
    from balsa.wire import width

    comptime n = width[dtype]()
    # Includes signed extrema, negative zero and NaN payload bit patterns.
    var patterns: List[UInt64] = [
        0,
        0xFFFFFFFFFFFFFFFF,
        0x8000000080000000,
        0x7FF800007FC01234,
        0x7FF000007F800001,
    ]
    for bits in patterns:
        var value: SIMD[dtype, 1]
        comptime if n == 1:
            value = SIMD[dtype, 1](from_bits=UInt8(bits))
        elif n == 4:
            value = SIMD[dtype, 1](from_bits=UInt32(bits))
        else:
            value = SIMD[dtype, 1](from_bits=bits)
        for offset in range(16):
            var writer = Writer(Limits())
            for _ in range(offset):
                writer.scalar[DType.uint8](0xA5)
            writer.scalar[dtype](value)
            var bytes = writer^.finish()
            var reader = Reader(Span(bytes), Limits())
            reader.pos = offset
            var restored = reader.scalar[dtype]()
            assert_equal(reader.pos, offset + n)
            var output = Writer(Limits())
            for _ in range(offset):
                output.scalar[DType.uint8](0xA5)
            output.scalar[dtype](restored)
            assert_equal(output^.finish(), bytes)
            for available in range(n):
                var short = bytes.copy()
                short.resize(offset + available, 0)
                var truncated = Reader(Span(short), Limits())
                truncated.pos = offset
                truncated.field = "threshold"
                truncated.tree_id = 3
                var failed = False
                try:
                    _ = truncated.scalar[dtype]()
                except err:
                    failed = True
                    assert_equal(
                        String(err),
                        "Malformed checkpoint at byte "
                        + String(offset)
                        + " (tree[3].threshold): truncated payload",
                    )
                assert_equal(failed, True)
                assert_equal(truncated.pos, offset)


def test_scalar_reads_alignment_bits_and_truncation() raises:
    check_scalar_reads[DType.uint8]()
    check_scalar_reads[DType.int8]()
    check_scalar_reads[DType.uint32]()
    check_scalar_reads[DType.int32]()
    check_scalar_reads[DType.uint64]()
    check_scalar_reads[DType.float32]()
    check_scalar_reads[DType.float64]()


def test_reader_rejects_invalid_cursor() raises:
    for position in [-1, 2]:
        var bytes: List[UInt8] = [0]
        var reader = Reader(Span(bytes), Limits())
        reader.pos = position
        with assert_raises():
            reader.require(1)
        with assert_raises():
            _ = reader.scalar[DType.uint8]()


def test_validation_opt_out_and_deferred_validation() raises:
    from balsa import ValidationOptions

    var unchecked = ValidationOptions(enabled=False)
    # Metadata, array lengths and topology are all part of the optional pass.
    for fault in range(3):
        var model = make_stump()
        if fault == 0:
            model.num_feature = -1
        elif fault == 1:
            model.trees[0].default_left.clear()
        else:
            model.trees[0].cleft[0] = 0
        with assert_raises():
            _ = encode(model)
        var data = encode(model, options=unchecked)
        with assert_raises():
            _ = decode(data.copy())
        var restored = decode(data.copy(), options=unchecked)
        assert_equal(encode(restored, options=unchecked), data)
        with assert_raises():
            validate(restored, options=unchecked)
        var automatic = decode_auto(data.copy(), options=unchecked)
        assert_equal(encode(automatic, options=unchecked), data)
        save(automatic, "build/unchecked.tl", options=unchecked)
        with assert_raises():
            _ = load_auto("build/unchecked.tl")
        var loaded = load_auto("build/unchecked.tl", options=unchecked)
        assert_equal(encode(loaded, options=unchecked), data)
        var typed = load("build/unchecked.tl", options=unchecked)
        assert_equal(encode(typed, options=unchecked), data)
    var builder = ModelBuilder(1)
    var tree = TreeBuilder(2)
    tree.leaf(0, 1)
    tree.leaf(1, 2)
    builder.add_tree(tree^.build())
    var disconnected = builder^.build(unchecked)
    with assert_raises():
        validate(disconnected)


def test_validation_opt_out_preserves_wire_checks() raises:
    from balsa import ValidationOptions

    var unchecked = ValidationOptions(enabled=False)
    var data = read_file("tests/fixtures/float32_op2_missing0.tl")
    var prefix = List[UInt8]()
    for byte in data:
        with assert_raises():
            _ = decode(prefix.copy(), options=unchecked)
        prefix.append(byte)
    for offset in [0, 12, 13]:
        var bad = data.copy()
        bad[offset] = 255
        with assert_raises():
            _ = decode_auto(bad^, options=unchecked)
    var trailing = data.copy()
    trailing.append(0)
    with assert_raises():
        _ = decode(trailing^, options=unchecked)
    for limits in [
        Limits(max_bytes=20),
        Limits(max_elements=2),
        Limits(max_nodes=2),
        Limits(max_bytes=-1),
    ]:
        with assert_raises():
            _ = decode(data.copy(), limits, unchecked)
    var model = make_stump()
    with assert_raises():
        _ = encode(model, Limits(max_bytes=20), unchecked)
    with assert_raises():
        _ = encode(model, Limits(max_elements=2), unchecked)
    var two = make_stump()
    two.trees.append(two.trees[0].copy())
    two.target_id.append(0)
    two.class_id.append(0)
    two.num_tree = 2
    var two_bytes = encode(two)
    with assert_raises():
        _ = decode(two_bytes^, Limits(max_trees=1), unchecked)
    var double_model = load[DType.float64]("tests/fixtures/float64_leaf.tl")
    double_model.num_feature = -1
    var double_bytes = encode(double_model, options=unchecked)
    var restored = decode_auto(double_bytes.copy(), options=unchecked)
    assert_equal(encode(restored, options=unchecked), double_bytes)
    with assert_raises():
        _ = decode[DType.float64](double_bytes^)


def test_named_reader_scalar_and_extension_errors() raises:
    # A failed named read retains the destination and identifies the wire field.
    var empty = List[UInt8]()
    var reader = Reader(Span(empty), Limits())
    var scalar = Int32(99)
    var failed = False
    try:
        reader.read["num_nodes"](scalar)
    except err:
        failed = True
        assert_equal(
            String(err),
            "Malformed checkpoint at byte 0 (num_nodes): truncated payload",
        )
    assert_equal(failed, True)
    assert_equal(scalar, 99)

    var writer = Writer(Limits())
    writer.scalar(Int32(-1))
    var input_bytes = writer^.finish()
    var extensions_reader = Reader(Span(input_bytes), Limits())
    extensions_reader.tree_id = 2
    var extensions = List[Extension]()
    extensions.append(Extension(bytes_of("kept"), 1, 1, bytes_of("x")))
    failed = False
    try:
        extensions_reader.read["tree_extensions"](extensions)
    except err:
        failed = True
        assert_equal(
            String(err),
            (
                "Malformed checkpoint at byte 4 (tree[2].tree_extensions):"
                " invalid extension count"
            ),
        )
    assert_equal(failed, True)
    assert_equal(len(extensions), 1)
    assert_equal(extensions[0].name, bytes_of("kept"))


def test_boolean_simd_boundaries() raises:
    comptime lanes = simd_width_of[DType.uint8]()
    # Empty, short, exact-vector, multiple-vector and remainder lengths.
    for length in range(3 * lanes + 2):
        var values = List[UInt8](length=length, fill=0)
        for i in range(length):
            values[i] = UInt8(i % 2)
        check_bool(values, "flags")
        # Exercise every lane and remainder position, including unsigned values
        # that would pass an incorrect signed comparison.
        for i in range(length):
            for invalid in [2, 128, 255]:
                values[i] = UInt8(invalid)
                var failed = False
                try:
                    check_bool(values, "flags")
                except err:
                    failed = True
                    assert_equal(String(err), "Malformed model: flags boolean")
                assert_equal(failed, True)
            values[i] = UInt8(i % 2)
