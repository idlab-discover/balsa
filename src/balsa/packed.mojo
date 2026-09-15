"""Owned, read-only checkpoints optimized for storage and occasional inspection.

Tree payloads stay in wire layout with byte-aligned typed access. Model-header
arrays are decoded once. Tree offsets share one index allocation. Use to_model()
for editing. This is the default storage representation exported by balsa.
"""

from std.utils import Variant
from .codec import read_file, read_header, read_tree, checkpoint_dtype
from .codec import decode as decode_editable
from .model import Model, Tree
from .wire import Reader, Limits
from .packed_views import (
    PackedTree,
    PackedArray,
    PackedExtensions,
    PackedExtension,
)
from .validation import (
    ValidationOptions,
    _validate_header,
    _check_tree_annotation,
    _validate_tree,
)


struct PackedModel[dtype: DType](Movable):
    """Own a checkpoint; field views cannot outlive or mutate its storage."""

    var _data: List[UInt8]
    var _header: Model[Self.dtype]
    var _trees: List[Int]
    var _limits: Limits

    def __init__(
        out self,
        var data: List[UInt8],
        limits: Limits = Limits(),
        options: ValidationOptions = ValidationOptions(),
    ) raises:
        var reader = Reader(Span(data), limits)
        var header = Model[Self.dtype]()
        read_header(header, reader)
        var trees = List[Int](
            capacity=min(Int(header.num_tree), len(data) // 256)
        )
        var total_nodes = 0
        for index in range(Int(header.num_tree)):
            reader.tree_id = index
            var start = reader.pos
            _ = PackedTree[Self.dtype](reader, total_nodes)
            trees.append(start)
        if reader.pos != len(data):
            reader.fail("trailing bytes")
        self._header = header^
        self._trees = trees^
        self._limits = limits.copy()
        self._data = data^
        if options.enabled:
            self.validate(options)

    def num_trees(self) -> Int:
        return len(self._trees)

    def num_features(self) -> Int:
        return Int(self._header.num_feature)

    def postprocessor_name(self) raises -> String:
        return self._header.postprocessor_name()

    def attributes_text(self) raises -> String:
        return self._header.attributes_text()

    def base_scores(self) -> Span[Float64, origin_of(self._header.base_scores)]:
        return Span(self._header.base_scores)

    def target_ids(self) -> Span[Int32, origin_of(self._header.target_id)]:
        return Span(self._header.target_id)

    def class_ids(self) -> Span[Int32, origin_of(self._header.class_id)]:
        return Span(self._header.class_id)

    def tree(
        self, index: Int
    ) raises -> PackedTree[Self.dtype, origin=origin_of(self._data)]:
        """Borrow typed fields; tree lookup scans its field headers, not payloads.
        """
        if index < 0 or index >= len(self._trees):
            raise Error("Packed tree index out of bounds")
        var reader = Reader(Span(self._data), self._limits)
        reader.pos = self._trees[index]
        reader.tree_id = index
        var total_nodes = 0
        return PackedTree[Self.dtype](reader, total_nodes)

    def to_model(
        self, options: ValidationOptions = ValidationOptions(enabled=True)
    ) raises -> Model[Self.dtype]:
        """Materialize independent editable fields, validating by default."""
        return decode_editable[Self.dtype](
            Span(self._data), self._limits, options
        )

    def validate(self, options: ValidationOptions = ValidationOptions()) raises:
        """Check semantics serially using one reusable tree and topology scratch.

        Always checks, even with enabled=False. max_workers is a cap; this
        representation currently uses one worker. No editable forest is built.
        """
        var max_class = _validate_header(
            self._header, len(self._trees), self._limits, options
        )
        var reader = Reader(Span(self._data), self._limits)
        var scratch = Tree[Self.dtype]()
        var seen = List[UInt8]()
        var stack = List[Int]()
        var parsed_nodes = 0
        var checked_nodes = 0
        for index in range(len(self._trees)):
            reader.pos = self._trees[index]
            reader.tree_id = index
            read_tree(scratch, reader, parsed_nodes)
            _check_tree_annotation(
                self._header,
                index,
                Int(scratch.num_nodes),
                self._limits,
                max_class,
                checked_nodes,
            )
            try:
                _validate_tree(
                    scratch, self._header, index, self._limits, seen, stack
                )
            except err:
                raise Error("tree[" + String(index) + "]: " + String(err))


def decode[
    dtype: DType = DType.float32
](
    var data: List[UInt8],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> PackedModel[dtype]:
    """Own checkpoint bytes with bounds checks; semantic validation is opt-in.
    """
    return PackedModel[dtype](data^, limits, options)


def decode[
    origin: Origin[mut=False], //, dtype: DType = DType.float32
](
    data: Span[UInt8, origin],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> PackedModel[dtype]:
    """Copy borrowed input once so the packed result owns its bytes."""
    limits.validate()
    if len(data) > limits.max_bytes:
        raise Error("Checkpoint exceeds byte limit")
    return decode[dtype](List(data), limits, options)


def load[
    dtype: DType = DType.float32
](
    path: String,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> PackedModel[dtype]:
    """Load directly into owned packed storage; no editable forest is allocated.
    """
    return decode[dtype](read_file(path, limits), limits, options)


def encode[dtype: DType](model: PackedModel[dtype]) -> List[UInt8]:
    """Copy the preserved wire bytes. No semantic validation is repeated.

    Models loaded with validation disabled are also emitted unchanged; call
    model.validate() explicitly when deferred semantic validation is wanted.
    """
    return model._data.copy()


def save[dtype: DType](model: PackedModel[dtype], path: String) raises:
    """Write the preserved bytes directly, without an intermediate output copy.

    Like encode(), this relies on the caller's load-time validation policy.
    """
    with open(path, "w") as file:
        file.write_all(Span(model._data))


comptime AnyPackedModel = Variant[
    PackedModel[DType.float32], PackedModel[DType.float64]
]


def decode_auto(
    var data: List[UInt8],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> AnyPackedModel:
    """Discover precision and own the original checkpoint buffer."""
    if checkpoint_dtype(data, limits) == DType.float32:
        return AnyPackedModel(decode[DType.float32](data^, limits, options))
    return AnyPackedModel(decode[DType.float64](data^, limits, options))


def decode_auto[
    origin: Origin[mut=False], //
](
    data: Span[UInt8, origin],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> AnyPackedModel:
    """Discover precision and copy borrowed bytes into an independent owner."""
    if checkpoint_dtype(data, limits) == DType.float32:
        return AnyPackedModel(decode[DType.float32](data, limits, options))
    return AnyPackedModel(decode[DType.float64](data, limits, options))


def load_auto(
    path: String,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> AnyPackedModel:
    return decode_auto(read_file(path, limits), limits, options)


def encode(model: AnyPackedModel) -> List[UInt8]:
    if model.isa[PackedModel[DType.float32]]():
        return encode(model[PackedModel[DType.float32]])
    return encode(model[PackedModel[DType.float64]])


def save(model: AnyPackedModel, path: String) raises:
    if model.isa[PackedModel[DType.float32]]():
        save(model[PackedModel[DType.float32]], path)
    else:
        save(model[PackedModel[DType.float64]], path)
