"""Native-only parsing checks for checkpoints from trained framework models.

The pinned Python generator records upstream fields in the fixture manifest.
These assertions inspect selected fields independently of Balsa's writer.
"""

from std.testing import assert_equal, TestSuite
from balsa import (
    Model,
    Operator,
    NodeType,
    load_editable as load,
    load_auto_editable as load_auto,
    encode,
)
from balsa.codec import read_file


def check[
    dtype: DType
](
    name: String,
    nodes: List[Int32],
    classes: List[Int32],
    shape: List[Int32],
    postprocessor: String,
) raises -> Model[dtype]:
    var path = "tests/fixtures/frameworks/" + name + ".tl"
    var bytes = read_file(path)
    var model = load[dtype](path)
    assert_equal(model.num_feature, Int32(4))
    assert_equal(model.num_tree, UInt64(4))
    assert_equal(model.num_target, Int32(len(classes)))
    assert_equal(model.num_class, classes)
    assert_equal(model.leaf_vector_shape, shape)
    assert_equal(model.postprocessor_name(), postprocessor)
    for index in range(len(nodes)):
        assert_equal(model.trees[index].num_nodes, nodes[index])
    assert_equal(encode(model), bytes)
    var automatic = load_auto(path)
    assert_equal(automatic.isa[Model[dtype]](), True)
    assert_equal(encode(automatic), bytes)
    return model^


def test_xgboost_missing_regression() raises:
    var model = check[DType.float32](
        "xgboost_regression", [15, 15, 15, 15], [1], [1, 1], "identity"
    )
    assert_equal(model.trees[0].cmp[0], Operator.LT)
    assert_equal(model.trees[0].threshold[0], Float32(-0.01968405395746231))
    assert_equal(model.trees[0].default_left[0], UInt8(1))
    assert_equal(model.trees[0].gain[0], Float64(530.0990600585938))
    assert_equal(model.trees[0].sum_hess[0], Float64(256))
    assert_equal(model.trees[0].leaf_value[14], Float32(0.38912996649742126))


def test_lightgbm_categorical() raises:
    var model = check[DType.float64](
        "lightgbm_categorical", [7, 7, 7, 5], [1], [1, 1], "sigmoid"
    )
    assert_equal(model.trees[0].node_type[0], NodeType.CATEGORICAL)
    assert_equal(model.trees[0].category_list_right_child[0], UInt8(0))
    assert_equal(model.trees[0].default_left[0], UInt8(0))
    assert_equal(model.trees[0].cleft[0], Int32(6))
    assert_equal(model.trees[0].data_count[0], UInt64(256))
    assert_equal(
        List(model.trees[0].categories(0)), List[UInt32]([UInt32(0), UInt32(2)])
    )
    assert_equal(model.trees[0].leaf_value[6], Float64(0.4759083074564609))


def test_catboost_numeric_symmetric() raises:
    var model = check[DType.float64](
        "catboost_numeric_regression", [15, 15, 15, 15], [1], [1, 1], "identity"
    )
    assert_equal(model.base_scores[0], Float64(-0.75))
    assert_equal(model.trees[0].cmp[0], Operator.GT)
    assert_equal(model.trees[0].threshold[0], Float64(0.4014032483100891))
    assert_equal(model.trees[0].default_left[0], UInt8(0))
    assert_equal(model.trees[0].leaf_value[14], Float64(-0.05650943172049362))


def test_sklearn_rf_multioutput_regression() raises:
    var model = check[DType.float64](
        "sklearn_rf_multioutput_regression",
        [15, 15, 15, 15],
        [1, 1],
        [2, 1],
        "identity",
    )
    assert_equal(model.average_tree_output, UInt8(1))
    assert_equal(model.target_id[0], Int32(-1))
    assert_equal(model.trees[0].cmp[0], Operator.LE)
    assert_equal(model.trees[0].split_index[0], Int32(3))
    assert_equal(model.trees[0].threshold[0], Float64(0.20568173378705978))
    assert_equal(
        List(model.trees[0].leaf_values(14)),
        List[Float64]([2.866044484078884, -4.973901728789012]),
    )


def test_sklearn_rf_multiclass() raises:
    var model = check[DType.float64](
        "sklearn_rf_multiclass",
        [9, 13, 13, 15],
        [3],
        [1, 3],
        "identity_multiclass",
    )
    assert_equal(model.average_tree_output, UInt8(1))
    assert_equal(model.class_id[0], Int32(-1))
    assert_equal(model.trees[0].data_count[0], UInt64(166))
    assert_equal(
        List(model.trees[0].leaf_values(8)), List[Float64]([0.0, 0.0, 1.0])
    )


def test_sklearn_extra_unequal_class_counts() raises:
    var model = check[DType.float64](
        "sklearn_extra_multioutput_classification",
        [15, 15, 11, 13],
        [2, 3],
        [2, 3],
        "identity_multiclass",
    )
    assert_equal(model.target_id[0], Int32(-1))
    assert_equal(model.class_id[0], Int32(-1))
    assert_equal(len(model.base_scores), 6)
    assert_equal(
        List(model.trees[0].leaf_values(14)),
        List[Float64]([0.5, 0.5, 0, 0.5, 0.5, 0]),
    )


def test_sklearn_gradient_binary() raises:
    var model = check[DType.float64](
        "sklearn_gradient_binary", [15, 15, 15, 15], [1], [1, 1], "sigmoid"
    )
    assert_equal(model.base_scores[0], Float64(0.2354568115475667))
    assert_equal(model.trees[0].threshold[0], Float64(-0.08633752167224884))
    assert_equal(model.trees[0].leaf_value[14], Float64(0.12108245736564321))


def test_sklearn_hist_missing_regression() raises:
    var model = check[DType.float64](
        "sklearn_hist_missing_regression",
        [15, 15, 15, 15],
        [1],
        [1, 1],
        "identity",
    )
    assert_equal(model.trees[0].default_left[0], UInt8(1))
    assert_equal(model.trees[0].threshold[0], Float64(-0.028616735711693764))
    assert_equal(model.trees[0].data_count[0], UInt64(256))
    assert_equal(model.trees[0].leaf_value[14], Float64(0.20267185270786287))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
