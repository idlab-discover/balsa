"""Compile against the installed package, without a source include path."""
from std.testing import assert_equal
from balsa import (
    version,
    ModelBuilder,
    TreeBuilder,
    PackedModel,
    ValidationOptions,
    decode,
    encode,
)


def main() raises:
    assert_equal(version(), "0.2.0")
    var builder = ModelBuilder(1)
    var tree = TreeBuilder(1)
    tree.leaf(0, 2.5)
    builder.add_tree(tree^.build())
    var editable = builder^.build()
    var data = encode(editable, options=ValidationOptions(enabled=True))
    var model: PackedModel[DType.float32] = decode(data.copy())
    model.validate()
    assert_equal(model.tree(0).leaf_value[0], Float32(2.5))
    assert_equal(encode(model), data)
    assert_equal(encode(model.to_model()), data)
