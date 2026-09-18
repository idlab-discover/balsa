"""Owned Treelite v4 fields. Wire booleans and strings retain their exact bytes.

Field definitions follow the Treelite v4 specification; see THIRD_PARTY_NOTICES.md.
Only float32/float32 and float64/float64 are supported.
"""


from .constants import type_tag


@fieldwise_init
struct Extension(Copyable, Movable):
    """Opaque optional field retained in its original extension slot."""

    var name: List[UInt8]
    """Opaque field name bytes."""
    var element_size: UInt64
    """Bytes per payload element."""
    var count: UInt64
    """Number of payload elements; payload length must equal count * element_size."""
    var payload: List[UInt8]
    """Opaque bytes preserved without interpretation."""


struct Tree[dtype: DType](Copyable, Movable):
    """Owned tree fields, validated by the codec."""

    comptime Scalar = SIMD[Self.dtype, 1]
    var num_nodes: Int32
    """Number of nodes; node zero is the root."""
    var has_categorical_split: UInt8
    """Wire boolean indicating whether the tree contains categorical splits."""
    var node_type: List[Int8]
    """Per-node NodeType code."""
    var cleft: List[Int32]
    """Per-node left child index; -1 for leaves."""
    var cright: List[Int32]
    """Per-node right child index; -1 for leaves."""
    var split_index: List[Int32]
    """Per-node feature index for split nodes."""
    var default_left: List[UInt8]
    """Per-node wire boolean selecting the left branch for missing values."""
    var leaf_value: List[Self.Scalar]
    """Per-node scalar leaf value."""
    var threshold: List[Self.Scalar]
    """Per-node numerical split threshold."""
    var cmp: List[Int8]
    """Per-node Operator code for numerical splits."""
    var category_list_right_child: List[UInt8]
    """Per-node wire boolean: category membership selects the right child."""
    var leaf_vector: List[Self.Scalar]
    """Concatenated vector-leaf values."""
    var leaf_vector_begin: List[UInt64]
    """Per-node inclusive offset into leaf_vector."""
    var leaf_vector_end: List[UInt64]
    """Per-node exclusive offset into leaf_vector."""
    var category_list: List[UInt32]
    """Concatenated categorical split IDs."""
    var category_list_begin: List[UInt64]
    """Per-node inclusive offset into category_list."""
    var category_list_end: List[UInt64]
    """Per-node exclusive offset into category_list."""
    var data_count: List[UInt64]
    """Optional per-node sample counts, paired with data_count_present."""
    var data_count_present: List[UInt8]
    """Presence flags for data_count; both arrays may be empty."""
    var sum_hess: List[Float64]
    """Optional per-node Hessian sums, paired with sum_hess_present."""
    var sum_hess_present: List[UInt8]
    """Presence flags for sum_hess; both arrays may be empty."""
    var gain: List[Float64]
    """Optional per-node gains, paired with gain_present."""
    var gain_present: List[UInt8]
    """Presence flags for gain; both arrays may be empty."""
    var tree_extensions: List[Extension]
    """Opaque records in the tree extension slot."""
    var node_extensions: List[Extension]
    """Opaque records in the node extension slot."""

    def __init__(out self):
        """Create empty tree storage; use TreeBuilder for a complete tree."""
        comptime assert (
            Self.dtype == DType.float32 or Self.dtype == DType.float64
        ), "Unsupported model precision"
        self.num_nodes = 0
        self.has_categorical_split = 0
        self.node_type = List[Int8]()
        self.cleft = List[Int32]()
        self.cright = List[Int32]()
        self.split_index = List[Int32]()
        self.default_left = List[UInt8]()
        self.leaf_value = List[Self.Scalar]()
        self.threshold = List[Self.Scalar]()
        self.cmp = List[Int8]()
        self.category_list_right_child = List[UInt8]()
        self.leaf_vector = List[Self.Scalar]()
        self.leaf_vector_begin = List[UInt64]()
        self.leaf_vector_end = List[UInt64]()
        self.category_list = List[UInt32]()
        self.category_list_begin = List[UInt64]()
        self.category_list_end = List[UInt64]()
        self.data_count = List[UInt64]()
        self.data_count_present = List[UInt8]()
        self.sum_hess = List[Float64]()
        self.sum_hess_present = List[UInt8]()
        self.gain = List[Float64]()
        self.gain_present = List[UInt8]()
        self.tree_extensions = List[Extension]()
        self.node_extensions = List[Extension]()

    def leaf_values(
        self, node: Int
    ) raises -> Span[Self.Scalar, origin_of(self.leaf_vector)]:
        """Borrow a node's vector leaf payload (empty for a scalar leaf).

        Checks node and offset bounds even after raw field edits. The view is
        immutable and cannot outlive the tree or coexist with its mutation.
        """
        return _segment(
            self.leaf_vector,
            self.leaf_vector_begin,
            self.leaf_vector_end,
            node,
            Int(self.num_nodes),
            "leaf_vector",
        )

    def categories(
        self, node: Int
    ) raises -> Span[UInt32, origin_of(self.category_list)]:
        """Borrow a node's category payload, checking node and offset bounds."""
        return _segment(
            self.category_list,
            self.category_list_begin,
            self.category_list_end,
            node,
            Int(self.num_nodes),
            "category_list",
        )


struct Model[dtype: DType](Copyable, Movable):
    """Owned model fields, validated by the codec."""

    comptime Scalar = SIMD[Self.dtype, 1]
    var major: Int32
    """Treelite checkpoint major version, independent of Balsa version."""
    var minor: Int32
    """Treelite checkpoint minor version."""
    var patch: Int32
    """Treelite checkpoint patch version."""
    var threshold_type: UInt8
    """TypeInfo tag matching the model dtype."""
    var leaf_output_type: UInt8
    """TypeInfo tag matching the model dtype."""
    var num_tree: UInt64
    """Number of trees; must equal the trees list length."""
    var num_feature: Int32
    """Number of input features."""
    var task_type: UInt8
    """TaskType code preserved as model metadata."""
    var average_tree_output: UInt8
    """Wire boolean indicating averaged tree output."""
    var num_target: Int32
    """Number of output targets."""
    var num_class: List[Int32]
    """Class count for each target."""
    var leaf_vector_shape: List[Int32]
    """Two dimensions describing a vector leaf output."""
    var target_id: List[Int32]
    """Per-tree target annotation; -1 denotes all targets."""
    var class_id: List[Int32]
    """Per-tree class annotation; -1 denotes all classes."""
    var postprocessor: List[UInt8]
    """Postprocessor name bytes; Balsa never executes the postprocessor."""
    var sigmoid_alpha: Float32
    """Stored postprocessor coefficient."""
    var ratio_c: Float32
    """Stored postprocessor coefficient."""
    var base_scores: List[Float64]
    """Base score array with num_target * max(num_class) entries."""
    var attributes: List[UInt8]
    """Opaque attribute JSON bytes; not parsed or validated as JSON."""
    var extensions: List[Extension]
    """Opaque records in the model extension slot."""
    var trees: List[Tree[Self.dtype]]
    """Owned trees in serialization order."""

    def __init__(out self):
        """Create raw storage with checkpoint version 4.6.1 and matching dtype tags.

        The empty metadata is incomplete; use ModelBuilder for valid defaults.
        """
        comptime assert (
            Self.dtype == DType.float32 or Self.dtype == DType.float64
        ), "Unsupported model precision"
        self.major = 4
        self.minor = 6
        self.patch = 1
        self.threshold_type = type_tag[Self.dtype]()
        self.leaf_output_type = type_tag[Self.dtype]()
        self.num_tree = 0
        self.num_feature = 0
        self.task_type = 0
        self.average_tree_output = 0
        self.num_target = 0
        self.num_class = List[Int32]()
        self.leaf_vector_shape = List[Int32]()
        self.target_id = List[Int32]()
        self.class_id = List[Int32]()
        self.postprocessor = List[UInt8]()
        self.sigmoid_alpha = 1
        self.ratio_c = 1
        self.base_scores = List[Float64]()
        self.attributes = List[UInt8]()
        self.extensions = List[Extension]()
        self.trees = List[Tree[Self.dtype]]()

    def postprocessor_name(self) raises -> String:
        """Decode UTF-8 strictly; unknown names are allowed and bytes untouched.
        """
        return String(from_utf8=Span(self.postprocessor))

    def set_postprocessor_name(mut self, name: String):
        """Store UTF-8 text without restricting postprocessor names."""
        self.postprocessor = List(name.as_bytes())

    def attributes_text(self) raises -> String:
        """Decode UTF-8 strictly; does not parse or validate attribute JSON."""
        return String(from_utf8=Span(self.attributes))

    def set_attributes_text(mut self, text: String):
        """Store text; the caller remains responsible for valid attribute JSON.
        """
        self.attributes = List(text.as_bytes())


def _segment[
    T: Copyable
](
    values: List[T],
    begins: List[UInt64],
    ends: List[UInt64],
    node: Int,
    nodes: Int,
    field: String,
) raises -> Span[T, origin_of(values)]:
    if node < 0 or node >= nodes or node >= len(begins) or node >= len(ends):
        raise Error(field + " node index out of bounds: " + String(node))
    var begin = begins[node]
    var end = ends[node]
    if begin > end or end > UInt64(len(values)):
        raise Error(field + " offsets out of bounds at node " + String(node))
    return Span(values)[Int(begin) : Int(end)]
