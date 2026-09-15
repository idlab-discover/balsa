"""Read-only, origin-tracked views over checked little-endian checkpoint bytes."""

from std.sys.info import is_little_endian
from .wire import Reader, Limits, width


struct PackedArray[dtype: DType, origin: Origin[mut=False]](
    Copyable, Movable, Sized
):
    """Typed access to unaligned wire bytes; no mutable or typed-pointer escape.
    """

    var _bytes: Span[UInt8, Self.origin]

    def __init__(out self, data: Span[UInt8, Self.origin]):
        self._bytes = data

    def __len__(self) -> Int:
        return len(self._bytes) // width[Self.dtype]()

    def __getitem__(self, index: Int) raises -> SIMD[Self.dtype, 1]:
        if index < 0 or index >= len(self):
            raise Error("Packed array index out of bounds")
        comptime n = width[Self.dtype]()
        comptime if is_little_endian() or n == 1:
            return (
                self._bytes.unsafe_ptr()
                .unsafe_offset(index * n)
                .unsafe_bitcast[SIMD[Self.dtype, 1]]()
                .unsafe_load[alignment=1]()
            )
        else:
            var bits = UInt64(0)
            for i in range(n):
                bits |= UInt64(self._bytes[index * n + i]) << UInt64(i * 8)
            comptime if n == 4:
                return SIMD[Self.dtype, 1](from_bits=UInt32(bits))
            else:
                return SIMD[Self.dtype, 1](from_bits=bits)

    def to_list(self) raises -> List[SIMD[Self.dtype, 1]]:
        """Materialize this field for independent ownership or editing."""
        var result = List[SIMD[Self.dtype, 1]](capacity=len(self))
        for i in range(len(self)):
            result.append(self[i])
        return result^


def _array[
    origin: Origin[mut=False], //, field: StaticString, dtype: DType
](mut reader: Reader[origin],) raises -> PackedArray[dtype, origin=origin]:
    reader.field = field
    return PackedArray[dtype](reader.array_bytes[dtype]())


@fieldwise_init
struct PackedExtension[origin: Origin[mut=False]](Copyable, Movable):
    var name: PackedArray[DType.uint8, origin=Self.origin]
    var element_size: UInt64
    var count: UInt64
    var payload: PackedArray[DType.uint8, origin=Self.origin]


def _extension[
    origin: Origin[mut=False]
](mut reader: Reader[origin],) raises -> PackedExtension[origin]:
    var name = PackedArray[DType.uint8](reader.array_bytes[DType.uint8]())
    var size = reader.scalar[DType.uint64]()
    var count = reader.scalar[DType.uint64]()
    if count > UInt64(reader.limits.max_elements):
        reader.fail("extension element limit exceeded")
    if size > UInt64(reader.limits.max_bytes):
        reader.fail("extension element size limit exceeded")
    if size != 0 and count > UInt64(len(reader.data) - reader.pos) // size:
        reader.fail("truncated extension or size overflow")
    var start = reader.pos
    reader.pos += Int(size * count)
    var payload = PackedArray[DType.uint8](reader.data[start : reader.pos])
    return PackedExtension(name^, size, count, payload^)


struct PackedExtensions[origin: Origin[mut=False]](Copyable, Movable, Sized):
    """Opaque extension records; indexed access scans preceding records."""

    var _bytes: Span[UInt8, Self.origin]
    var _count: Int
    var _limits: Limits

    def __init__(out self, mut reader: Reader[Self.origin]) raises:
        var start = reader.pos
        var count = reader.scalar[DType.int32]()
        if count < 0 or Int(count) > reader.limits.max_extensions:
            reader.fail("invalid extension count")
        for _ in range(Int(count)):
            _ = _extension(reader)
        self._bytes = reader.data[start : reader.pos]
        self._count = Int(count)
        self._limits = reader.limits.copy()

    def __len__(self) -> Int:
        return self._count

    def __getitem__(self, index: Int) raises -> PackedExtension[Self.origin]:
        if index < 0 or index >= self._count:
            raise Error("Packed extension index out of bounds")
        var reader = Reader(self._bytes, self._limits)
        _ = reader.scalar[DType.int32]()
        for _ in range(index):
            _ = _extension(reader)
        return _extension(reader)


def _extensions[
    origin: Origin[mut=False], //, field: StaticString
](mut reader: Reader[origin],) raises -> PackedExtensions[origin]:
    reader.field = field
    return PackedExtensions(reader)


struct PackedTree[dtype: DType, origin: Origin[mut=False]](Copyable, Movable):
    """Read-only tree fields borrowing the checkpoint owner's storage."""

    var num_nodes: Int32
    var has_categorical_split: UInt8
    var node_type: PackedArray[DType.int8, origin=Self.origin]
    var cleft: PackedArray[DType.int32, origin=Self.origin]
    var cright: PackedArray[DType.int32, origin=Self.origin]
    var split_index: PackedArray[DType.int32, origin=Self.origin]
    var default_left: PackedArray[DType.uint8, origin=Self.origin]
    var leaf_value: PackedArray[Self.dtype, origin=Self.origin]
    var threshold: PackedArray[Self.dtype, origin=Self.origin]
    var cmp: PackedArray[DType.int8, origin=Self.origin]
    var category_list_right_child: PackedArray[DType.uint8, origin=Self.origin]
    var leaf_vector: PackedArray[Self.dtype, origin=Self.origin]
    var leaf_vector_begin: PackedArray[DType.uint64, origin=Self.origin]
    var leaf_vector_end: PackedArray[DType.uint64, origin=Self.origin]
    var category_list: PackedArray[DType.uint32, origin=Self.origin]
    var category_list_begin: PackedArray[DType.uint64, origin=Self.origin]
    var category_list_end: PackedArray[DType.uint64, origin=Self.origin]
    var data_count: PackedArray[DType.uint64, origin=Self.origin]
    var data_count_present: PackedArray[DType.uint8, origin=Self.origin]
    var sum_hess: PackedArray[DType.float64, origin=Self.origin]
    var sum_hess_present: PackedArray[DType.uint8, origin=Self.origin]
    var gain: PackedArray[DType.float64, origin=Self.origin]
    var gain_present: PackedArray[DType.uint8, origin=Self.origin]
    var tree_extensions: PackedExtensions[Self.origin]
    var node_extensions: PackedExtensions[Self.origin]

    def __init__(
        out self, mut reader: Reader[Self.origin], mut total_nodes: Int
    ) raises:
        self.num_nodes = 0
        self.has_categorical_split = 0
        reader.read["num_nodes"](self.num_nodes)
        if (
            self.num_nodes <= 0
            or Int(self.num_nodes) > reader.limits.max_nodes - total_nodes
        ):
            reader.fail("invalid node count or total node limit exceeded")
        total_nodes += Int(self.num_nodes)
        reader.read["has_categorical_split"](self.has_categorical_split)
        self.node_type = _array["node_type", DType.int8](reader)
        self.cleft = _array["cleft", DType.int32](reader)
        self.cright = _array["cright", DType.int32](reader)
        self.split_index = _array["split_index", DType.int32](reader)
        self.default_left = _array["default_left", DType.uint8](reader)
        self.leaf_value = _array["leaf_value", Self.dtype](reader)
        self.threshold = _array["threshold", Self.dtype](reader)
        self.cmp = _array["cmp", DType.int8](reader)
        self.category_list_right_child = _array[
            "category_list_right_child", DType.uint8
        ](reader)
        self.leaf_vector = _array["leaf_vector", Self.dtype](reader)
        self.leaf_vector_begin = _array["leaf_vector_begin", DType.uint64](
            reader
        )
        self.leaf_vector_end = _array["leaf_vector_end", DType.uint64](reader)
        self.category_list = _array["category_list", DType.uint32](reader)
        self.category_list_begin = _array["category_list_begin", DType.uint64](
            reader
        )
        self.category_list_end = _array["category_list_end", DType.uint64](
            reader
        )
        self.data_count = _array["data_count", DType.uint64](reader)
        self.data_count_present = _array["data_count_present", DType.uint8](
            reader
        )
        self.sum_hess = _array["sum_hess", DType.float64](reader)
        self.sum_hess_present = _array["sum_hess_present", DType.uint8](reader)
        self.gain = _array["gain", DType.float64](reader)
        self.gain_present = _array["gain_present", DType.uint8](reader)
        self.tree_extensions = _extensions["tree_extensions"](reader)
        self.node_extensions = _extensions["node_extensions"](reader)
