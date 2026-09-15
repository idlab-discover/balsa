"""Must fail: a tree view cannot outlive its checkpoint owner."""

import balsa.packed as packed
from balsa.packed_views import PackedTree


def escape() raises -> PackedTree[DType.float32, ImmStaticOrigin]:
    var model = packed.load("tests/fixtures/float32_leaf.tl")
    return model.tree(0)


def main() raises:
    _ = escape()
