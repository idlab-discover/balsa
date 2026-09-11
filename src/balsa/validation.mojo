"""Structural validation of Treelite checkpoint fields."""

from .model import Model, Tree, Extension
from .constants import NodeType, Operator, TaskType, type_tag
from .wire import Limits


def require(condition: Bool, field: String) raises:
    if not condition:
        raise Error("Malformed model: " + field)


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


def check_bool(values: List[UInt8], field: String) raises:
    for value in values:
        require(value <= 1, field + " boolean")


def check_stat[
    dtype: DType
](
    values: List[SIMD[dtype, 1]],
    present: List[UInt8],
    nodes: Int,
    field: String,
) raises:
    require(len(values) == len(present), field + " presence length")
    require(len(values) == 0 or len(values) == nodes, field + " length")
    check_bool(present, field)


def validate[
    dtype: DType
](model: Model[dtype], limits: Limits = Limits()) raises:
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
    var total_nodes = 0
    for tree_id in range(len(model.trees)):
        var target = Int(model.target_id[tree_id])
        var cls = Int(model.class_id[tree_id])
        require(
            target >= -1 and target < Int(model.num_target), "target_id value"
        )
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
        try:
            validate_tree(model.trees[tree_id], model, tree_id, limits)
        except err:
            raise Error("tree[" + String(tree_id) + "]: " + String(err))


def validate_tree[
    dtype: DType
](tree: Tree[dtype], model: Model[dtype], tree_id: Int, limits: Limits) raises:
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
    var seen = List[UInt8]()
    for _ in range(n):
        seen.append(0)
    var stack: List[Int] = [0]
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
