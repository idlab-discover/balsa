"""Must fail: packed field views do not expose element mutation."""

import balsa.packed as packed


def main() raises:
    var model = packed.load("tests/fixtures/float32_leaf.tl")
    var tree = model.tree(0)
    tree.leaf_value[0] = Float32(1)
