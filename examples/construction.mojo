"""Build a stump, save it, and load it without specifying its precision."""

from balsa import (
    Model,
    ModelBuilder,
    TreeBuilder,
    Operator,
    load_auto_editable as load_auto,
    save,
)


def describe[dtype: DType](model: Model[dtype]) raises:
    print("Postprocessor:", model.postprocessor_name())
    for tree in model.trees:
        var thresholds = Span(tree.threshold)
        print("Root threshold:", thresholds[0])


def main() raises:
    var builder = ModelBuilder[DType.float64](num_feature=1, base_scores=[0.5])
    var tree = TreeBuilder[DType.float64](num_nodes=3)
    tree.numerical_split(
        0,
        feature=0,
        threshold=0.5,
        op=Operator.LT,
        left=1,
        right=2,
        default_left=True,
    )
    tree.leaf(1, -1.25)
    tree.leaf(2, 2.75)
    builder.add_tree(tree^.build())
    var model = builder^.build()
    save(model, "build/example-stump.tl")
    var loaded = load_auto("build/example-stump.tl")
    if loaded.isa[Model[DType.float32]]():
        describe(loaded[Model[DType.float32]])
    else:
        describe(loaded[Model[DType.float64]])
    save(loaded, "build/example-copy.tl")
