"""Construction helpers over the owned format model, with no inference policy."""

from .constants import NodeType, Operator, TaskType
from .model import Model, Tree
from .validation import require, validate, ValidationOptions
from .wire import Limits


struct TreeBuilder[dtype: DType = DType.float32](Movable):
    """Fill dense node IDs in any order; node 0 is the root.

    Each node must be defined exactly once. build() checks completeness;
    ModelBuilder.build() checks topology, features and output shapes.
    """

    comptime Scalar = SIMD[Self.dtype, 1]
    var _tree: Tree[Self.dtype]
    var _defined: List[Bool]
    var _limits: Limits

    def __init__(out self, num_nodes: Int, limits: Limits = Limits()) raises:
        """Allocate a tree with positive, bounded node count and undefined nodes.
        """
        limits.validate()
        require(
            num_nodes > 0
            and num_nodes <= limits.max_nodes
            and num_nodes <= limits.max_elements,
            "builder node count/limit",
        )
        self._tree = Tree[Self.dtype]()
        self._tree.num_nodes = Int32(num_nodes)
        self._defined = List[Bool]()
        self._limits = limits.copy()
        for _ in range(num_nodes):
            self._defined.append(False)
            self._tree.node_type.append(NodeType.LEAF)
            self._tree.cleft.append(-1)
            self._tree.cright.append(-1)
            self._tree.split_index.append(-1)
            self._tree.default_left.append(0)
            self._tree.leaf_value.append(0)
            self._tree.threshold.append(0)
            self._tree.cmp.append(Operator.NONE)
            self._tree.category_list_right_child.append(0)
            self._tree.leaf_vector_begin.append(0)
            self._tree.leaf_vector_end.append(0)
            self._tree.category_list_begin.append(0)
            self._tree.category_list_end.append(0)

    def _check_node(self, node: Int) raises:
        require(
            node >= 0 and node < len(self._defined),
            "builder node index " + String(node),
        )
        require(
            not self._defined[node], "builder duplicate node " + String(node)
        )

    def _check_split(
        self, node: Int, feature: Int32, left: Int32, right: Int32
    ) raises:
        self._check_node(node)
        require(feature >= 0, "builder feature index")
        require(
            left >= 0
            and Int(left) < len(self._defined)
            and right >= 0
            and Int(right) < len(self._defined)
            and left != right
            and Int(left) != node
            and Int(right) != node,
            "builder children at node " + String(node),
        )

    def leaf(mut self, node: Int, value: Self.Scalar) raises:
        """Define a scalar leaf without parallel-array bookkeeping."""
        self._check_node(node)
        self._tree.leaf_value[node] = value
        self._defined[node] = True

    def leaf_vector(mut self, node: Int, values: List[Self.Scalar]) raises:
        """Define a vector leaf; shape is checked against model metadata."""
        self._check_node(node)
        require(len(values) > 0, "builder empty leaf vector")
        require(
            len(values)
            <= self._limits.max_elements - len(self._tree.leaf_vector),
            "builder leaf vector limit",
        )
        self._tree.leaf_vector_begin[node] = UInt64(len(self._tree.leaf_vector))
        for value in values:
            self._tree.leaf_vector.append(value)
        self._tree.leaf_vector_end[node] = UInt64(len(self._tree.leaf_vector))
        self._defined[node] = True

    def numerical_split(
        mut self,
        node: Int,
        *,
        feature: Int32,
        threshold: Self.Scalar,
        left: Int32,
        right: Int32,
        op: Int8 = Operator.LT,
        default_left: Bool = False,
    ) raises:
        """Define a numerical split; default_left chooses the missing-value branch.
        """
        self._check_split(node, feature, left, right)
        require(
            op >= Operator.EQ and op <= Operator.GE,
            "builder numerical operator",
        )
        self._tree.node_type[node] = NodeType.NUMERICAL
        self._tree.split_index[node] = feature
        self._tree.threshold[node] = threshold
        self._tree.cmp[node] = op
        self._tree.cleft[node] = left
        self._tree.cright[node] = right
        self._tree.default_left[node] = UInt8(default_left)
        self._defined[node] = True

    def categorical_split(
        mut self,
        node: Int,
        *,
        feature: Int32,
        categories: List[UInt32],
        left: Int32,
        right: Int32,
        default_left: Bool = False,
        categories_right: Bool = False,
    ) raises:
        """Define a categorical split, copying category IDs into tree storage.

        Membership selects the right child when categories_right is True,
        otherwise the left child. default_left selects the missing-value branch.
        """
        self._check_split(node, feature, left, right)
        require(
            len(categories)
            <= self._limits.max_elements - len(self._tree.category_list),
            "builder category limit",
        )
        self._tree.node_type[node] = NodeType.CATEGORICAL
        self._tree.has_categorical_split = 1
        self._tree.split_index[node] = feature
        self._tree.cleft[node] = left
        self._tree.cright[node] = right
        self._tree.default_left[node] = UInt8(default_left)
        self._tree.category_list_right_child[node] = UInt8(categories_right)
        self._tree.category_list_begin[node] = UInt64(
            len(self._tree.category_list)
        )
        for category in categories:
            self._tree.category_list.append(category)
        self._tree.category_list_end[node] = UInt64(
            len(self._tree.category_list)
        )
        self._defined[node] = True

    def build(deinit self) raises -> Tree[Self.dtype]:
        """Consume the builder, rejecting undefined nodes; no array copies."""
        for node in range(len(self._defined)):
            require(
                self._defined[node], "builder undefined node " + String(node)
            )
        return self._tree^


struct ModelBuilder[dtype: DType = DType.float32](Movable):
    """Build a model with derived tree/target counts and default scalar metadata.
    """

    var _model: Model[Self.dtype]
    var _limits: Limits

    def __init__(
        out self,
        num_feature: Int32,
        *,
        task_type: UInt8 = TaskType.REGRESSOR,
        average_tree_output: Bool = False,
        var num_class: List[Int32] = [1],
        var leaf_vector_shape: List[Int32] = [1, 1],
        var base_scores: List[Float64] = List[Float64](),
        postprocessor: String = "identity",
        sigmoid_alpha: Float32 = 1,
        ratio_c: Float32 = 1,
        attributes: String = "",
        limits: Limits = Limits(),
    ) raises:
        """Initialize and validate metadata for a model without trees.

        num_class defines one entry per target. Empty base_scores become zeros
        with num_target * max(num_class) entries. List arguments are consumed.
        Postprocessor settings are stored as metadata and never executed.
        """
        limits.validate()
        require(
            len(num_class) > 0 and len(num_class) <= limits.max_elements,
            "builder num_class length",
        )
        var max_class = 0
        for classes in num_class:
            require(classes > 0, "builder num_class value")
            if Int(classes) > max_class:
                max_class = Int(classes)
        require(
            len(num_class) <= limits.max_elements // max_class,
            "builder output shape limit",
        )
        if len(base_scores) == 0:
            for _ in range(len(num_class) * max_class):
                base_scores.append(0)
        self._model = Model[Self.dtype]()
        self._limits = limits.copy()
        self._model.num_feature = num_feature
        self._model.task_type = task_type
        self._model.average_tree_output = UInt8(average_tree_output)
        self._model.num_target = Int32(len(num_class))
        self._model.num_class = num_class^
        self._model.leaf_vector_shape = leaf_vector_shape^
        self._model.base_scores = base_scores^
        self._model.set_postprocessor_name(postprocessor)
        self._model.sigmoid_alpha = sigmoid_alpha
        self._model.ratio_c = ratio_c
        self._model.set_attributes_text(attributes)
        validate(self._model, limits)

    def add_tree(
        mut self,
        var tree: Tree[Self.dtype],
        *,
        target_id: Int32 = 0,
        class_id: Int32 = 0,
    ) raises:
        """Transfer tree ownership; annotation and topology checks run at build.
        """
        require(
            len(self._model.trees) < self._limits.max_trees,
            "builder tree limit",
        )
        self._model.trees.append(tree^)
        self._model.target_id.append(target_id)
        self._model.class_id.append(class_id)
        self._model.num_tree = UInt64(len(self._model.trees))

    def build(
        deinit self, options: ValidationOptions = ValidationOptions()
    ) raises -> Model[Self.dtype]:
        """Consume the builder, validating the model unless options disables it.
        """
        if options.enabled:
            validate(self._model, self._limits, options)
        return self._model^
