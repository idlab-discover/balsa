"""Owned Treelite v4 fields. Wire booleans and strings retain their exact bytes.

Field definitions follow the Treelite v4 specification; see docs/mvp-plan.md.
Only float32/float32 and float64/float64 are supported.
"""


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
        self.threshold_type = UInt8(2 if Self.dtype == DType.float32 else 3)
        self.leaf_output_type = UInt8(2 if Self.dtype == DType.float32 else 3)
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
