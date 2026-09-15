"""Native Treelite v4 binary checkpoint codec.

Sequence follows the pinned specification and serializer listed in
 docs/mvp-plan.md. No Python or libtreelite runtime dependency.
"""

from std.utils import Variant
from std.sys import size_of
from .constants import type_tag, TypeInfo
from .model import Model, Tree
from .wire import Limits, Reader, Writer
from .validation import validate, ValidationOptions


def decode[
    dtype: DType = DType.float32
](
    var data: List[UInt8],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> Model[dtype]:
    """Decode a checkpoint, validating its model unless options disables it.

    Wire bounds, format checks and parser limits always apply. Precision must
    match the file tags. A skipped validation pass can be run with validate().
    """
    return decode[dtype](Span(data), limits, options)


def decode[
    origin: Origin[mut=False], //, dtype: DType = DType.float32
](
    data: Span[UInt8, origin],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> Model[dtype]:
    """Borrow checkpoint bytes and return independently owned model fields."""
    var model = Model[dtype]()
    decode_into(model, data, limits, options)
    return model^


def decode_into[
    dtype: DType, origin: Origin[mut=False]
](
    mut model: Model[dtype],
    data: Span[UInt8, origin],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises:
    """Decode into owned storage, reusing existing field capacities.

    On failure fields may be partially updated and must not be used as a valid
    model. The destination remains safe to destroy or pass to decode_into again.
    Input bytes are borrowed only for this call. All parser checks still apply.
    """
    var reader = Reader(data, limits)
    read_header(model, reader)
    read_trees(model, reader)
    if reader.pos != len(reader.data):
        reader.fail("trailing bytes")
    if options.enabled:
        validate(model, limits, options)


def read_header[
    dtype: DType, origin: Origin[mut=False]
](mut model: Model[dtype], mut reader: Reader[origin]) raises:
    reader.read["major"](model.major)
    reader.read["minor"](model.minor)
    reader.read["patch"](model.patch)
    if model.major != 4 or model.minor < 0 or model.patch < 0:
        raise Error(
            "Unsupported checkpoint version: expected v4 with nonnegative"
            " minor/patch"
        )
    reader.read["threshold_type"](model.threshold_type)
    reader.read["leaf_output_type"](model.leaf_output_type)
    if (
        model.threshold_type != model.leaf_output_type
        or model.threshold_type != type_tag[dtype]()
    ):
        raise Error(
            "Unsupported checkpoint precision or mismatched decode dtype"
        )
    reader.read["num_tree"](model.num_tree)
    if model.num_tree > UInt64(reader.limits.max_trees):
        reader.fail("tree count limit exceeded")
    reader.read["num_feature"](model.num_feature)
    reader.read["task_type"](model.task_type)
    reader.read["average_tree_output"](model.average_tree_output)
    reader.read["num_target"](model.num_target)
    reader.read["num_class"](model.num_class)
    reader.read["leaf_vector_shape"](model.leaf_vector_shape)
    reader.read["target_id"](model.target_id)
    reader.read["class_id"](model.class_id)
    reader.read["postprocessor"](model.postprocessor)
    reader.read["sigmoid_alpha"](model.sigmoid_alpha)
    reader.read["ratio_c"](model.ratio_c)
    reader.read["base_scores"](model.base_scores)
    reader.read["attributes"](model.attributes)
    reader.read["extensions"](model.extensions)


def read_trees[
    dtype: DType, origin: Origin[mut=False]
](mut model: Model[dtype], mut reader: Reader[origin]) raises:
    # Bound the capacity hint by actual input bytes, not just an untrusted count.
    model.trees.reserve(
        min(
            Int(model.num_tree),
            (len(reader.data) - reader.pos) // size_of[Tree[dtype]](),
        )
    )
    var total_nodes = 0
    for tree_id in range(Int(model.num_tree)):
        reader.tree_id = tree_id
        if tree_id == len(model.trees):
            model.trees.append(Tree[dtype]())
        read_tree(model.trees[tree_id], reader, total_nodes)
    while len(model.trees) > Int(model.num_tree):
        _ = model.trees.pop()


def read_tree[
    dtype: DType, origin: Origin[mut=False]
](
    mut tree: Tree[dtype], mut reader: Reader[origin], mut total_nodes: Int
) raises:
    reader.read["num_nodes"](tree.num_nodes)
    if (
        tree.num_nodes <= 0
        or Int(tree.num_nodes) > reader.limits.max_nodes - total_nodes
    ):
        reader.fail("invalid node count or total node limit exceeded")
    total_nodes += Int(tree.num_nodes)
    reader.read["has_categorical_split"](tree.has_categorical_split)
    reader.read["node_type"](tree.node_type)
    reader.read["cleft"](tree.cleft)
    reader.read["cright"](tree.cright)
    reader.read["split_index"](tree.split_index)
    reader.read["default_left"](tree.default_left)
    reader.read["leaf_value"](tree.leaf_value)
    reader.read["threshold"](tree.threshold)
    reader.read["cmp"](tree.cmp)
    reader.read["category_list_right_child"](tree.category_list_right_child)
    reader.read["leaf_vector"](tree.leaf_vector)
    reader.read["leaf_vector_begin"](tree.leaf_vector_begin)
    reader.read["leaf_vector_end"](tree.leaf_vector_end)
    reader.read["category_list"](tree.category_list)
    reader.read["category_list_begin"](tree.category_list_begin)
    reader.read["category_list_end"](tree.category_list_end)
    reader.read["data_count"](tree.data_count)
    reader.read["data_count_present"](tree.data_count_present)
    reader.read["sum_hess"](tree.sum_hess)
    reader.read["sum_hess_present"](tree.sum_hess_present)
    reader.read["gain"](tree.gain)
    reader.read["gain_present"](tree.gain_present)
    reader.read["tree_extensions"](tree.tree_extensions)
    reader.read["node_extensions"](tree.node_extensions)


def encode[
    dtype: DType
](
    model: Model[dtype],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> List[UInt8]:
    """Encode owned fields, retaining version, extensions and floating bits.

    options.enabled=False skips model validation; writer bounds still apply.
    """
    if options.enabled:
        validate(model, limits, options)
    # One shared field traversal, specialized to count or emit at compile time.
    var counter = Writer[True](limits)
    write_model(model, counter)
    var writer = Writer[False, True](limits, counter.size())
    write_model(model, writer)
    return writer^.finish()


def write_model[
    dtype: DType, count_only: Bool, fixed_size: Bool
](model: Model[dtype], mut writer: Writer[count_only, fixed_size]) raises:
    write_header(model, writer)
    for tree in model.trees:
        write_tree(tree, writer)


def write_header[
    dtype: DType, count_only: Bool, fixed_size: Bool
](model: Model[dtype], mut writer: Writer[count_only, fixed_size]) raises:
    writer.scalar(model.major)
    writer.scalar(model.minor)
    writer.scalar(model.patch)
    writer.scalar(model.threshold_type)
    writer.scalar(model.leaf_output_type)
    writer.scalar(model.num_tree)
    writer.scalar(model.num_feature)
    writer.scalar(model.task_type)
    writer.scalar(model.average_tree_output)
    writer.scalar(model.num_target)
    writer.array(model.num_class)
    writer.array(model.leaf_vector_shape)
    writer.array(model.target_id)
    writer.array(model.class_id)
    writer.array(model.postprocessor)
    writer.scalar(model.sigmoid_alpha)
    writer.scalar(model.ratio_c)
    writer.array(model.base_scores)
    writer.array(model.attributes)
    writer.extensions(model.extensions)


def write_tree[
    dtype: DType, count_only: Bool, fixed_size: Bool
](tree: Tree[dtype], mut writer: Writer[count_only, fixed_size]) raises:
    writer.scalar(tree.num_nodes)
    writer.scalar(tree.has_categorical_split)
    writer.array(tree.node_type)
    writer.array(tree.cleft)
    writer.array(tree.cright)
    writer.array(tree.split_index)
    writer.array(tree.default_left)
    writer.array(tree.leaf_value)
    writer.array(tree.threshold)
    writer.array(tree.cmp)
    writer.array(tree.category_list_right_child)
    writer.array(tree.leaf_vector)
    writer.array(tree.leaf_vector_begin)
    writer.array(tree.leaf_vector_end)
    writer.array(tree.category_list)
    writer.array(tree.category_list_begin)
    writer.array(tree.category_list_end)
    writer.array(tree.data_count)
    writer.array(tree.data_count_present)
    writer.array(tree.sum_hess)
    writer.array(tree.sum_hess_present)
    writer.array(tree.gain)
    writer.array(tree.gain_present)
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
](
    path: String,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> Model[dtype]:
    """Load a checkpoint of the specified precision (float32 by default)."""
    return decode[dtype](read_file(path, limits), limits, options)


def save[
    dtype: DType
](
    model: Model[dtype],
    path: String,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises:
    """Encode (and by default validate) before replacing the destination."""
    var bytes = encode(model, limits, options)
    with open(path, "w") as file:
        file.write_all(Span(bytes))


comptime AnyModel = Variant[Model[DType.float32], Model[DType.float64]]
"""Owned model with discovered float32 or float64 precision; accepted by encode and save."""


def checkpoint_dtype(
    data: List[UInt8], limits: Limits = Limits()
) raises -> DType:
    """Inspect the v4 header and both dtype tags; does not validate the body."""
    return checkpoint_dtype(Span(data), limits)


def checkpoint_dtype[
    origin: Origin[mut=False]
](data: Span[UInt8, origin], limits: Limits = Limits()) raises -> DType:
    """Inspect precision directly from borrowed checkpoint bytes."""
    limits.validate()
    if len(data) > limits.max_bytes:
        raise Error("Checkpoint exceeds byte limit")
    if len(data) < 14:
        raise Error("Truncated checkpoint header")
    var reader = Reader(data, limits)
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
    var data: List[UInt8],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> AnyModel:
    """Discover precision from the checkpoint, preserving its typed storage."""
    return decode_auto(Span(data), limits, options)


def decode_auto[
    origin: Origin[mut=False]
](
    data: Span[UInt8, origin],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> AnyModel:
    """Discover precision from borrowed bytes and return owned model fields."""
    if checkpoint_dtype(data, limits) == DType.float32:
        return AnyModel(decode[DType.float32](data, limits, options))
    return AnyModel(decode[DType.float64](data, limits, options))


def load_auto(
    path: String,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> AnyModel:
    """Load either supported precision without converting its values."""
    return decode_auto(read_file(path, limits), limits, options)


def encode(
    model: AnyModel,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> List[UInt8]:
    """Encode an automatically loaded model in its original precision."""
    if model.isa[Model[DType.float32]]():
        return encode(model[Model[DType.float32]], limits, options)
    return encode(model[Model[DType.float64]], limits, options)


def save(
    model: AnyModel,
    path: String,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises:
    """Save an automatically loaded model without changing precision."""
    if model.isa[Model[DType.float32]]():
        save(model[Model[DType.float32]], path, limits, options)
    else:
        save(model[Model[DType.float64]], path, limits, options)
