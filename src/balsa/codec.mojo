"""Native Treelite v4 binary checkpoint codec.

Sequence follows the pinned specification and serializer listed in
 docs/mvp-plan.md. No Python or libtreelite runtime dependency.
"""

from std.utils import Variant
from .constants import type_tag, TypeInfo
from .model import Model, Tree
from .wire import Limits, Reader, Writer
from .validation import validate


def decode[
    dtype: DType = DType.float32
](var data: List[UInt8], limits: Limits = Limits()) raises -> Model[dtype]:
    """Decode and validate a checkpoint; precision must match the file tags."""
    var reader = Reader(data^, limits)
    var model = Model[dtype]()
    reader.field = "major"
    model.major = reader.scalar[DType.int32]()
    reader.field = "minor"
    model.minor = reader.scalar[DType.int32]()
    reader.field = "patch"
    model.patch = reader.scalar[DType.int32]()
    if model.major != 4 or model.minor < 0 or model.patch < 0:
        raise Error(
            "Unsupported checkpoint version: expected v4 with nonnegative"
            " minor/patch"
        )
    reader.field = "threshold_type"
    model.threshold_type = reader.scalar[DType.uint8]()
    reader.field = "leaf_output_type"
    model.leaf_output_type = reader.scalar[DType.uint8]()
    if (
        model.threshold_type != model.leaf_output_type
        or model.threshold_type != type_tag[dtype]()
    ):
        raise Error(
            "Unsupported checkpoint precision or mismatched decode dtype"
        )
    reader.field = "num_tree"
    model.num_tree = reader.scalar[DType.uint64]()
    if model.num_tree > UInt64(limits.max_trees):
        reader.fail("tree count limit exceeded")
    reader.field = "num_feature"
    model.num_feature = reader.scalar[DType.int32]()
    reader.field = "task_type"
    model.task_type = reader.scalar[DType.uint8]()
    reader.field = "average_tree_output"
    model.average_tree_output = reader.scalar[DType.uint8]()
    reader.field = "num_target"
    model.num_target = reader.scalar[DType.int32]()
    reader.field = "num_class"
    model.num_class = reader.array[DType.int32]()
    reader.field = "leaf_vector_shape"
    model.leaf_vector_shape = reader.array[DType.int32]()
    reader.field = "target_id"
    model.target_id = reader.array[DType.int32]()
    reader.field = "class_id"
    model.class_id = reader.array[DType.int32]()
    reader.field = "postprocessor"
    model.postprocessor = reader.array[DType.uint8]()
    reader.field = "sigmoid_alpha"
    model.sigmoid_alpha = reader.scalar[DType.float32]()
    reader.field = "ratio_c"
    model.ratio_c = reader.scalar[DType.float32]()
    reader.field = "base_scores"
    model.base_scores = reader.array[DType.float64]()
    reader.field = "attributes"
    model.attributes = reader.array[DType.uint8]()
    reader.field = "extensions"
    model.extensions = reader.extensions()
    var total_nodes = 0
    for tree_id in range(Int(model.num_tree)):
        reader.tree_id = tree_id
        var tree = Tree[dtype]()
        reader.field = "num_nodes"
        tree.num_nodes = reader.scalar[DType.int32]()
        if (
            tree.num_nodes <= 0
            or Int(tree.num_nodes) > limits.max_nodes - total_nodes
        ):
            reader.fail("invalid node count or total node limit exceeded")
        total_nodes += Int(tree.num_nodes)
        reader.field = "has_categorical_split"
        tree.has_categorical_split = reader.scalar[DType.uint8]()
        reader.field = "node_type"
        tree.node_type = reader.array[DType.int8]()
        reader.field = "cleft"
        tree.cleft = reader.array[DType.int32]()
        reader.field = "cright"
        tree.cright = reader.array[DType.int32]()
        reader.field = "split_index"
        tree.split_index = reader.array[DType.int32]()
        reader.field = "default_left"
        tree.default_left = reader.array[DType.uint8]()
        reader.field = "leaf_value"
        tree.leaf_value = reader.array[dtype]()
        reader.field = "threshold"
        tree.threshold = reader.array[dtype]()
        reader.field = "cmp"
        tree.cmp = reader.array[DType.int8]()
        reader.field = "category_list_right_child"
        tree.category_list_right_child = reader.array[DType.uint8]()
        reader.field = "leaf_vector"
        tree.leaf_vector = reader.array[dtype]()
        reader.field = "leaf_vector_begin"
        tree.leaf_vector_begin = reader.array[DType.uint64]()
        reader.field = "leaf_vector_end"
        tree.leaf_vector_end = reader.array[DType.uint64]()
        reader.field = "category_list"
        tree.category_list = reader.array[DType.uint32]()
        reader.field = "category_list_begin"
        tree.category_list_begin = reader.array[DType.uint64]()
        reader.field = "category_list_end"
        tree.category_list_end = reader.array[DType.uint64]()
        reader.field = "data_count"
        tree.data_count = reader.array[DType.uint64]()
        reader.field = "data_count_present"
        tree.data_count_present = reader.array[DType.uint8]()
        reader.field = "sum_hess"
        tree.sum_hess = reader.array[DType.float64]()
        reader.field = "sum_hess_present"
        tree.sum_hess_present = reader.array[DType.uint8]()
        reader.field = "gain"
        tree.gain = reader.array[DType.float64]()
        reader.field = "gain_present"
        tree.gain_present = reader.array[DType.uint8]()
        reader.field = "tree_extensions"
        tree.tree_extensions = reader.extensions()
        reader.field = "node_extensions"
        tree.node_extensions = reader.extensions()
        model.trees.append(tree^)
    if reader.pos != len(reader.data):
        reader.fail("trailing bytes")
    validate(model, limits)
    return model^


def encode[
    dtype: DType
](model: Model[dtype], limits: Limits = Limits()) raises -> List[UInt8]:
    """Encode owned fields, retaining version, extensions and floating bits."""
    validate(model, limits)
    # One shared field traversal, specialized to count or emit at compile time.
    var counter = Writer[True](limits)
    write_model(model, counter)
    var writer = Writer(limits)
    writer.data.reserve(counter.size())
    write_model(model, writer)
    return writer^.finish()


def write_model[
    dtype: DType, count_only: Bool
](model: Model[dtype], mut writer: Writer[count_only]) raises:
    writer.scalar[DType.int32](model.major)
    writer.scalar[DType.int32](model.minor)
    writer.scalar[DType.int32](model.patch)
    writer.scalar[DType.uint8](model.threshold_type)
    writer.scalar[DType.uint8](model.leaf_output_type)
    writer.scalar[DType.uint64](model.num_tree)
    writer.scalar[DType.int32](model.num_feature)
    writer.scalar[DType.uint8](model.task_type)
    writer.scalar[DType.uint8](model.average_tree_output)
    writer.scalar[DType.int32](model.num_target)
    writer.array[DType.int32](model.num_class)
    writer.array[DType.int32](model.leaf_vector_shape)
    writer.array[DType.int32](model.target_id)
    writer.array[DType.int32](model.class_id)
    writer.array[DType.uint8](model.postprocessor)
    writer.scalar[DType.float32](model.sigmoid_alpha)
    writer.scalar[DType.float32](model.ratio_c)
    writer.array[DType.float64](model.base_scores)
    writer.array[DType.uint8](model.attributes)
    writer.extensions(model.extensions)
    for tree in model.trees:
        writer.scalar[DType.int32](tree.num_nodes)
        writer.scalar[DType.uint8](tree.has_categorical_split)
        writer.array[DType.int8](tree.node_type)
        writer.array[DType.int32](tree.cleft)
        writer.array[DType.int32](tree.cright)
        writer.array[DType.int32](tree.split_index)
        writer.array[DType.uint8](tree.default_left)
        writer.array[dtype](tree.leaf_value)
        writer.array[dtype](tree.threshold)
        writer.array[DType.int8](tree.cmp)
        writer.array[DType.uint8](tree.category_list_right_child)
        writer.array[dtype](tree.leaf_vector)
        writer.array[DType.uint64](tree.leaf_vector_begin)
        writer.array[DType.uint64](tree.leaf_vector_end)
        writer.array[DType.uint32](tree.category_list)
        writer.array[DType.uint64](tree.category_list_begin)
        writer.array[DType.uint64](tree.category_list_end)
        writer.array[DType.uint64](tree.data_count)
        writer.array[DType.uint8](tree.data_count_present)
        writer.array[DType.float64](tree.sum_hess)
        writer.array[DType.uint8](tree.sum_hess_present)
        writer.array[DType.float64](tree.gain)
        writer.array[DType.uint8](tree.gain_present)
        writer.extensions(tree.tree_extensions)
        writer.extensions(tree.node_extensions)


def read_file(path: String, limits: Limits = Limits()) raises -> List[UInt8]:
    """Read a regular checkpoint with a byte cap before allocation."""
    limits.validate()
    with open(path, "r") as file:
        var size = file.seek(0, 2)
        if size > UInt64(limits.max_bytes):
            raise Error("Checkpoint exceeds byte limit")
        _ = file.seek(0)
        var data = file.read_bytes(Int(size) + 1)
        if len(data) != Int(size):
            raise Error("Checkpoint changed while reading")
        return data^


def load[
    dtype: DType = DType.float32
](path: String, limits: Limits = Limits()) raises -> Model[dtype]:
    """Load a checkpoint of the specified precision (float32 by default)."""
    return decode[dtype](read_file(path, limits), limits)


def save[
    dtype: DType
](model: Model[dtype], path: String, limits: Limits = Limits()) raises:
    """Validate and encode before opening the destination for replacement."""
    var bytes = encode(model, limits)
    with open(path, "w") as file:
        file.write_all(Span(bytes))


comptime AnyModel = Variant[Model[DType.float32], Model[DType.float64]]


def checkpoint_dtype(
    data: List[UInt8], limits: Limits = Limits()
) raises -> DType:
    """Inspect the v4 header and both dtype tags; does not validate the body."""
    limits.validate()
    if len(data) > limits.max_bytes:
        raise Error("Checkpoint exceeds byte limit")
    if len(data) < 14:
        raise Error("Truncated checkpoint header")
    # Reuse bounded version decoding, copying only the fixed-size header.
    var header = List[UInt8]()
    for i in range(14):
        header.append(data[i])
    var reader = Reader(header^, limits)
    var major = reader.scalar[DType.int32]()
    var minor = reader.scalar[DType.int32]()
    var patch = reader.scalar[DType.int32]()
    if major != 4 or minor < 0 or patch < 0:
        raise Error(
            "Unsupported checkpoint version: expected v4 with nonnegative"
            " minor/patch"
        )
    if data[12] != data[13]:
        raise Error(
            "Unsupported checkpoint precision: threshold and leaf tags must"
            " match"
        )
    if data[12] == TypeInfo.FLOAT32:
        return DType.float32
    if data[12] == TypeInfo.FLOAT64:
        return DType.float64
    raise Error("Unsupported checkpoint precision: expected float32 or float64")


def decode_auto(
    var data: List[UInt8], limits: Limits = Limits()
) raises -> AnyModel:
    """Discover precision from the checkpoint, preserving its typed storage."""
    if checkpoint_dtype(data, limits) == DType.float32:
        return AnyModel(decode[DType.float32](data^, limits))
    return AnyModel(decode[DType.float64](data^, limits))


def load_auto(path: String, limits: Limits = Limits()) raises -> AnyModel:
    """Load either supported precision without converting its values."""
    return decode_auto(read_file(path, limits), limits)


def encode(model: AnyModel, limits: Limits = Limits()) raises -> List[UInt8]:
    """Encode an automatically loaded model in its original precision."""
    if model.isa[Model[DType.float32]]():
        return encode(model[Model[DType.float32]], limits)
    return encode(model[Model[DType.float64]], limits)


def save(model: AnyModel, path: String, limits: Limits = Limits()) raises:
    """Save an automatically loaded model without changing precision."""
    if model.isa[Model[DType.float32]]():
        save(model[Model[DType.float32]], path, limits)
    else:
        save(model[Model[DType.float64]], path, limits)
