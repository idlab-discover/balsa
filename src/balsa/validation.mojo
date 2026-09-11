"""Structural validation of Treelite checkpoint fields."""

from max.algorithm import parallelize

from .model import Model, Tree, Extension
from .constants import NodeType, Operator, TaskType, type_tag
from .wire import Limits


struct ValidationOptions(Copyable, Movable):
    """Bound validation concurrency per call; one worker forces serial execution.

    Thresholds apply together. The shared runtime may use fewer workers.
    """

    var max_workers: Int
    var min_trees: Int
    var min_nodes: Int

    def __init__(
        out self,
        max_workers: Int = 4,
        min_trees: Int = 4096,
        min_nodes: Int = 65536,
    ):
        self.max_workers = max_workers
        self.min_trees = min_trees
        self.min_nodes = min_nodes


@always_inline
def require(condition: Bool, field: StringSlice) raises:
    if not condition:
        raise Error("Malformed model: " + String(field))


def check_extensions(values: List[Extension], limits: Limits) raises:
    require(len(values) <= limits.max_extensions, "extension count")
    for value in values:
        require(
            value.element_size <= UInt64(limits.max_bytes),
            "extension element size",
        )
        require(value.count <= UInt64(limits.max_elements), "extension count")
        # Bounds above make multiplication safe in UInt64.
        require(
            value.element_size * value.count == UInt64(len(value.payload)),
            "extension payload size",
        )


def check_bool(values: List[UInt8], field: StringSlice) raises:
    for value in values:
        if value > 1:
            raise Error("Malformed model: " + String(field) + " boolean")


def check_stat[
    dtype: DType
](
    values: List[SIMD[dtype, 1]],
    present: List[UInt8],
    nodes: Int,
    field: StringSlice,
) raises:
    if len(values) != len(present):
        raise Error("Malformed model: " + String(field) + " presence length")
    if len(values) != 0 and len(values) != nodes:
        raise Error("Malformed model: " + String(field) + " length")
    check_bool(present, field)


def validate[
    dtype: DType
](
    model: Model[dtype],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises:
    """Reject malformed metadata, lengths, topology and segment offsets."""
    limits.validate()
    require(
        model.major == 4 and model.minor >= 0 and model.patch >= 0, "version"
    )
    var tag = type_tag[dtype]()
    require(
        model.threshold_type == tag and model.leaf_output_type == tag,
        "dtype tags",
    )
    require(model.num_tree == UInt64(len(model.trees)), "num_tree")
    require(len(model.trees) <= limits.max_trees, "tree limit")
    require(model.num_feature >= 0, "num_feature")
    require(model.num_target > 0, "num_target")
    require(model.task_type <= TaskType.ISOLATION_FOREST, "task_type")
    require(model.average_tree_output <= 1, "average_tree_output")
    require(len(model.num_class) == Int(model.num_target), "num_class length")
    var max_class = 0
    for classes in model.num_class:
        require(classes > 0, "num_class value")
        if Int(classes) > max_class:
            max_class = Int(classes)
    require(
        Int(model.num_target) <= limits.max_elements // max_class,
        "output shape limit",
    )
    require(
        len(model.base_scores) == Int(model.num_target) * max_class,
        "base_scores shape",
    )
    require(len(model.leaf_vector_shape) == 2, "leaf_vector_shape length")
    require(
        model.leaf_vector_shape[0] == 1
        or model.leaf_vector_shape[0] == model.num_target,
        "leaf_vector_shape targets",
    )
    require(
        model.leaf_vector_shape[1] == 1
        or Int(model.leaf_vector_shape[1]) == max_class,
        "leaf_vector_shape classes",
    )
    require(len(model.target_id) == len(model.trees), "target_id length")
    require(len(model.class_id) == len(model.trees), "class_id length")
    check_extensions(model.extensions, limits)
    require(options.max_workers > 0, "validation max_workers")
    require(
        options.min_trees >= 0 and options.min_nodes >= 0,
        "validation thresholds",
    )
    if options.max_workers > 1 and len(model.trees) >= options.min_trees:
        var total_nodes = 0
        var largest_tree = 0
        for tree in model.trees:
            var nodes = Int(tree.num_nodes)
            if nodes <= 0 or nodes > limits.max_nodes - total_nodes:
                _validate_serial(model, limits, max_class)
                return
            total_nodes += nodes
            largest_tree = max(largest_tree, nodes)
        # One dominant tree cannot benefit from tree-level parallelism.
        if (
            total_nodes >= options.min_nodes
            and len(model.trees) > 1
            and largest_tree <= total_nodes // 2
        ):
            var checked_nodes = 0
            try:
                for tree_id in range(len(model.trees)):
                    _check_tree_metadata(
                        model, tree_id, limits, max_class, checked_nodes
                    )
            except:
                # Earlier structural errors outrank later metadata/limit errors.
                _validate_serial(model, limits, max_class)
                return
            _validate_parallel(model, limits, total_nodes, options.max_workers)
            return
    _validate_serial(model, limits, max_class)


def _check_tree_metadata[
    dtype: DType
](
    model: Model[dtype],
    tree_id: Int,
    limits: Limits,
    max_class: Int,
    mut total_nodes: Int,
) raises:
    var target = Int(model.target_id[tree_id])
    var cls = Int(model.class_id[tree_id])
    require(target >= -1 and target < Int(model.num_target), "target_id value")
    require(cls >= -1 and cls < max_class, "class_id value")
    if target >= 0 and cls >= 0:
        require(cls < Int(model.num_class[target]), "class_id for target")
    if target < 0 and cls >= 0:
        for classes in model.num_class:
            require(cls < Int(classes), "class_id across targets")
    var nodes = Int(model.trees[tree_id].num_nodes)
    require(
        nodes > 0 and nodes <= limits.max_nodes - total_nodes,
        "node count/limit",
    )
    total_nodes += nodes


def _validate_serial[
    dtype: DType
](model: Model[dtype], limits: Limits, max_class: Int,) raises:
    var total_nodes = 0
    var seen = List[UInt8]()
    var stack = List[Int]()
    for tree_id in range(len(model.trees)):
        _check_tree_metadata(model, tree_id, limits, max_class, total_nodes)
        try:
            _validate_tree(
                model.trees[tree_id], model, tree_id, limits, seen, stack
            )
        except err:
            raise Error("tree[" + String(tree_id) + "]: " + String(err))


def _validate_parallel[
    dtype: DType
](
    model: Model[dtype],
    limits: Limits,
    total_nodes: Int,
    max_workers: Int,
) raises:
    var workers = min(max_workers, len(model.trees))
    # Contiguous ranges preserve ordering. A large tree is never split.
    var boundaries = List[Int]()
    boundaries.append(0)
    var accumulated = 0
    for i in range(len(model.trees)):
        accumulated += Int(model.trees[i].num_nodes)
        if len(boundaries) < workers and accumulated >= (
            total_nodes // workers
        ) * len(boundaries):
            boundaries.append(i + 1)
    if boundaries[len(boundaries) - 1] != len(model.trees):
        boundaries.append(len(model.trees))
    var batches = len(boundaries) - 1
    var errors = List[String](length=batches, fill=String())
    # Each task owns one error slot; lists stay allocated until the join.
    var error_ptr = errors.unsafe_ptr()

    def work(batch: Int) {model, limits, boundaries, error_ptr}:
        var seen = List[UInt8]()
        var stack = List[Int]()
        for tree_id in range(boundaries[batch], boundaries[batch + 1]):
            try:
                _validate_tree(
                    model.trees[tree_id], model, tree_id, limits, seen, stack
                )
            except err:
                error_ptr[unsafe_offset=batch] = (
                    "tree[" + String(tree_id) + "]: " + String(err)
                )
                return

    parallelize(work, batches, workers)
    for error in errors:
        if error.byte_length() != 0:
            raise Error(error)


def validate_tree[
    dtype: DType
](tree: Tree[dtype], model: Model[dtype], tree_id: Int, limits: Limits) raises:
    var seen = List[UInt8]()
    var stack = List[Int]()
    _validate_tree(tree, model, tree_id, limits, seen, stack)


def _validate_tree[
    dtype: DType
](
    tree: Tree[dtype],
    model: Model[dtype],
    tree_id: Int,
    limits: Limits,
    mut seen: List[UInt8],
    mut stack: List[Int],
) raises:
    var n = Int(tree.num_nodes)
    require(len(tree.node_type) == n, "node_type length")
    require(len(tree.cleft) == n and len(tree.cright) == n, "children lengths")
    require(len(tree.split_index) == n, "split_index length")
    require(len(tree.default_left) == n, "default_left length")
    require(
        len(tree.leaf_value) == n and len(tree.threshold) == n,
        "leaf/threshold lengths",
    )
    require(len(tree.cmp) == n, "cmp length")
    require(
        len(tree.category_list_right_child) == n, "category direction length"
    )
    require(
        len(tree.leaf_vector_begin) == n and len(tree.leaf_vector_end) == n,
        "leaf offsets lengths",
    )
    require(
        len(tree.category_list_begin) == n and len(tree.category_list_end) == n,
        "category offsets lengths",
    )
    require(tree.has_categorical_split <= 1, "has_categorical_split boolean")
    check_bool(tree.default_left, "default_left")
    check_bool(tree.category_list_right_child, "category_list_right_child")
    check_stat(tree.data_count, tree.data_count_present, n, "data_count")
    check_stat(tree.sum_hess, tree.sum_hess_present, n, "sum_hess")
    check_stat(tree.gain, tree.gain_present, n, "gain")
    check_extensions(tree.tree_extensions, limits)
    check_extensions(tree.node_extensions, limits)
    var has_categories = False
    var vector_size = UInt64(model.leaf_vector_shape[0]) * UInt64(
        model.leaf_vector_shape[1]
    )
    for i in range(n):
        var kind = tree.node_type[i]
        require(
            kind >= NodeType.LEAF and kind <= NodeType.CATEGORICAL,
            "node_type value",
        )
        var lb = tree.leaf_vector_begin[i]
        var le = tree.leaf_vector_end[i]
        var cb = tree.category_list_begin[i]
        var ce = tree.category_list_end[i]
        require(
            lb <= le and le <= UInt64(len(tree.leaf_vector)), "leaf offsets"
        )
        require(
            cb <= ce and ce <= UInt64(len(tree.category_list)),
            "category offsets",
        )
        if kind == NodeType.LEAF:
            require(
                tree.cleft[i] == -1 and tree.cright[i] == -1, "leaf children"
            )
            require(tree.split_index[i] == -1, "leaf split_index")
            if le > lb:
                require(le - lb == vector_size, "leaf vector shape")
            else:
                require(
                    model.target_id[tree_id] >= 0
                    and model.class_id[tree_id] >= 0,
                    "scalar leaf target/class",
                )
        else:
            require(lb == le, "internal node leaf vector")
            require(tree.cleft[i] >= 0 and Int(tree.cleft[i]) < n, "left child")
            require(
                tree.cright[i] >= 0 and Int(tree.cright[i]) < n, "right child"
            )
            require(
                tree.split_index[i] >= 0
                and tree.split_index[i] < model.num_feature,
                "feature index",
            )
        if kind == NodeType.NUMERICAL:
            require(
                tree.cmp[i] >= Operator.EQ and tree.cmp[i] <= Operator.GE,
                "numerical operator",
            )
        if kind == NodeType.CATEGORICAL:
            has_categories = True
        else:
            require(cb == ce, "noncategorical category segment")
    require(
        Bool(tree.has_categorical_split) == has_categories,
        "categorical flag mismatch",
    )
    # Iterative traversal rejects cycles, shared children and unreachable nodes.
    # Reuse capacity across trees, but reset contents on every traversal.
    # No validity state survives a public validate() call.
    seen.clear()
    seen.resize(n, 0)
    stack.clear()
    stack.append(0)
    var visited = 0
    while len(stack) > 0:
        var node = stack.pop()
        require(seen[node] == 0, "cycle or shared child")
        seen[node] = 1
        visited += 1
        if tree.node_type[node] != NodeType.LEAF:
            stack.append(Int(tree.cleft[node]))
            stack.append(Int(tree.cright[node]))
    require(visited == n, "unreachable node")
