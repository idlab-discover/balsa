"""Owned Treelite v4 fields. Wire booleans and strings retain their exact bytes.

Field definitions follow the Treelite v4 specification; see docs/mvp-plan.md.
Only float32/float32 and float64/float64 are supported.
"""


from .constants import type_tag


@fieldwise_init
struct Extension(Copyable, Movable):
    """Opaque optional field retained in its original extension slot."""

    var name: List[UInt8]
    var element_size: UInt64
    var count: UInt64
    var payload: List[UInt8]


struct Tree[dtype: DType](Copyable, Movable):
    """Owned tree fields, validated by the codec."""

    comptime Scalar = SIMD[Self.dtype, 1]
    var num_nodes: Int32
    var has_categorical_split: UInt8
    var node_type: List[Int8]
    var cleft: List[Int32]
    var cright: List[Int32]
    var split_index: List[Int32]
    var default_left: List[UInt8]
    var leaf_value: List[Self.Scalar]
    var threshold: List[Self.Scalar]
    var cmp: List[Int8]
    var category_list_right_child: List[UInt8]
    var leaf_vector: List[Self.Scalar]
    var leaf_vector_begin: List[UInt64]
    var leaf_vector_end: List[UInt64]
    var category_list: List[UInt32]
    var category_list_begin: List[UInt64]
    var category_list_end: List[UInt64]
    var data_count: List[UInt64]
    var data_count_present: List[UInt8]
    var sum_hess: List[Float64]
    var sum_hess_present: List[UInt8]
    var gain: List[Float64]
    var gain_present: List[UInt8]
    var tree_extensions: List[Extension]
    var node_extensions: List[Extension]

    def __init__(out self):
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
    var minor: Int32
    var patch: Int32
    var threshold_type: UInt8
    var leaf_output_type: UInt8
    var num_tree: UInt64
    var num_feature: Int32
    var task_type: UInt8
    var average_tree_output: UInt8
    var num_target: Int32
    var num_class: List[Int32]
    var leaf_vector_shape: List[Int32]
    var target_id: List[Int32]
    var class_id: List[Int32]
    var postprocessor: List[UInt8]
    var sigmoid_alpha: Float32
    var ratio_c: Float32
    var base_scores: List[Float64]
    var attributes: List[UInt8]
    var extensions: List[Extension]
    var trees: List[Tree[Self.dtype]]

    def __init__(out self):
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
