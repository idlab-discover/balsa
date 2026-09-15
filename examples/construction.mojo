"""Build, save, and reload a one-split tree. Run with `pixi run example`."""

from balsa import ModelBuilder, TreeBuilder, Operator, load, save


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
    var loaded = load[DType.float64]("build/example-stump.tl")
    print("Trees:", loaded.num_trees(), "Features:", loaded.num_features())
