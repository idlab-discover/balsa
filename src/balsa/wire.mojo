"""Bounded little-endian primitives with byte-aligned bulk transfers."""

from std.memory import unsafe_memcpy
from std.sys.info import is_little_endian

from .model import Extension


struct Limits(Copyable, Movable):
    """Allocation/work limits for untrusted checkpoints (not an RSS guarantee).
    """

    var max_bytes: Int
    """Maximum checkpoint size in bytes; default 64 MiB."""
    var max_elements: Int
    """Maximum elements in an individual array; default 8,388,608."""
    var max_trees: Int
    """Maximum trees per model; default 100,000."""
    var max_nodes: Int
    """Maximum total nodes per model; default 1,000,000."""
    var max_extensions: Int
    """Maximum records in each extension slot; default 1,024."""

    def __init__(
        out self,
        max_bytes: Int = 64 * 1024 * 1024,
        max_elements: Int = 8 * 1024 * 1024,
        max_trees: Int = 100_000,
        max_nodes: Int = 1_000_000,
        max_extensions: Int = 1024,
    ):
        """Set byte, per-array, tree, total-node and per-slot extension caps."""
        self.max_bytes = max_bytes
        self.max_elements = max_elements
        self.max_trees = max_trees
        self.max_nodes = max_nodes
        self.max_extensions = max_extensions

    def validate(self) raises:
        """Reject limits outside the inclusive range 1 through 2^30."""
        if (
            self.max_bytes <= 0
            or self.max_bytes > 1_073_741_824
            or self.max_elements <= 0
            or self.max_trees <= 0
            or self.max_nodes <= 0
            or self.max_extensions <= 0
            or self.max_elements > 1_073_741_824
            or self.max_trees > 1_073_741_824
            or self.max_nodes > 1_073_741_824
            or self.max_extensions > 1_073_741_824
        ):
            raise Error("Invalid limits: each limit must be between 1 and 2^30")


def width[dtype: DType]() -> Int:
    comptime if dtype == DType.uint8 or dtype == DType.int8:
        return 1
    elif dtype == DType.uint32 or dtype == DType.int32 or dtype == DType.float32:
        return 4
    else:
        comptime assert (
            dtype == DType.uint64 or dtype == DType.float64
        ), "Unsupported wire type"
        return 8


struct Reader[origin: Origin[mut=False]](Movable):
    """Borrows input bytes and reports the failing field and byte offset."""

    var data: Span[UInt8, Self.origin]
    var pos: Int
    var field: StaticString
    var tree_id: Int
    var limits: Limits

    def __init__(
        out self, data: Span[UInt8, Self.origin], limits: Limits
    ) raises:
        limits.validate()
        if len(data) > limits.max_bytes:
            raise Error("Checkpoint exceeds byte limit")
        self.data = data
        self.pos = 0
        self.field = "header"
        self.tree_id = -1
        self.limits = limits.copy()

    @always_inline
    def read[
        dtype: DType, //, field: StaticString
    ](mut self, mut value: SIMD[dtype, 1]) raises:
        """Read a named scalar, inferring its wire dtype from the destination.
        """
        self.field = field
        value = self.scalar[dtype]()

    @always_inline
    def read[
        dtype: DType, //, field: StaticString
    ](mut self, mut value: List[SIMD[dtype, 1]]) raises:
        """Read a named array, inferring its wire dtype from the destination."""
        self.field = field
        self.array_into(value)

    @always_inline
    def read[field: StaticString](mut self, mut value: List[Extension]) raises:
        """Read a named extension slot with its dedicated wire representation.
        """
        self.field = field
        self.extensions_into(value)

    def fail(self, message: String) raises:
        var context = String(self.field)
        if self.tree_id >= 0:
            context = "tree[" + String(self.tree_id) + "]." + context
        raise Error(
            "Malformed checkpoint at byte "
            + String(self.pos)
            + " ("
            + context
            + "): "
            + message
        )

    def require(self, count: Int) raises:
        if (
            self.pos < 0
            or self.pos > len(self.data)
            or count < 0
            or count > len(self.data) - self.pos
        ):
            self.fail("truncated payload")

    def scalar[dtype: DType](mut self) raises -> SIMD[dtype, 1]:
        comptime n = width[dtype]()
        self.require(n)
        comptime if is_little_endian() or n == 1:
            var value = (
                self.data.unsafe_ptr()
                .unsafe_offset(self.pos)
                .unsafe_bitcast[SIMD[dtype, 1]]()
                .unsafe_load[alignment=1]()
            )
            self.pos += n
            return value
        var bits = UInt64(0)
        for i in range(n):
            bits |= UInt64(self.data[self.pos + i]) << UInt64(i * 8)
        self.pos += n
        comptime if n == 1:
            return SIMD[dtype, 1](from_bits=UInt8(bits))
        elif n == 4:
            return SIMD[dtype, 1](from_bits=UInt32(bits))
        else:
            return SIMD[dtype, 1](from_bits=bits)

    def array[dtype: DType](mut self) raises -> List[SIMD[dtype, 1]]:
        var result = List[SIMD[dtype, 1]]()
        self.array_into(result)
        return result^

    def array_bytes[dtype: DType](mut self) raises -> Span[UInt8, Self.origin]:
        """Borrow a checked wire array payload without allocating typed storage.
        """
        var count = self.scalar[DType.uint64]()
        comptime n = width[dtype]()
        if count > UInt64(self.limits.max_elements):
            self.fail("array element limit exceeded")
        if count > UInt64((len(self.data) - self.pos) // n):
            self.fail("truncated array")
        var start = self.pos
        self.pos += Int(count) * n
        return self.data[start : self.pos]

    def array_into[
        dtype: DType
    ](mut self, mut result: List[SIMD[dtype, 1]]) raises:
        var count = self.scalar[DType.uint64]()
        comptime n = width[dtype]()
        if count > UInt64(self.limits.max_elements):
            self.fail("array element limit exceeded")
        if count > UInt64((len(self.data) - self.pos) // n):
            self.fail("truncated array")
        comptime if is_little_endian() or n == 1:
            # Extent was proved by division before multiplication/allocation.
            # Copy bytes: the wire payload need not have typed alignment.
            result.resize(unsafe_uninit_length=Int(count))
            var byte_count = Int(count) * n
            if byte_count > 0:
                unsafe_memcpy(
                    dest=result.unsafe_ptr().unsafe_bitcast[UInt8](),
                    src=self.data.unsafe_ptr().unsafe_offset(self.pos),
                    count=byte_count,
                )
            self.pos += byte_count
        else:
            # Portable explicit little-endian conversion on big-endian hosts.
            result.clear()
            result.reserve(Int(count))
            for _ in range(Int(count)):
                result.append(self.scalar[dtype]())

    def extensions(mut self) raises -> List[Extension]:
        var result = List[Extension]()
        self.extensions_into(result)
        return result^

    def extensions_into(mut self, mut result: List[Extension]) raises:
        var count = self.scalar[DType.int32]()
        if count < 0 or Int(count) > self.limits.max_extensions:
            self.fail("invalid extension count")
        for i in range(Int(count)):
            if i == len(result):
                result.append(Extension([], 0, 0, []))
            self.extension_into(result[i])
        while len(result) > Int(count):
            _ = result.pop()

    def extension_into(mut self, mut extension: Extension) raises:
        self.array_into(extension.name)
        var size = self.scalar[DType.uint64]()
        var elements = self.scalar[DType.uint64]()
        if elements > UInt64(self.limits.max_elements):
            self.fail("extension element limit exceeded")
        if size > UInt64(self.limits.max_bytes):
            self.fail("extension element size limit exceeded")
        if size != 0 and elements > UInt64(len(self.data) - self.pos) // size:
            self.fail("truncated extension or size overflow")
        var byte_count = Int(size * elements)
        extension.payload.resize(unsafe_uninit_length=byte_count)
        if byte_count > 0:
            unsafe_memcpy(
                dest=extension.payload.unsafe_ptr(),
                src=self.data.unsafe_ptr().unsafe_offset(self.pos),
                count=byte_count,
            )
        self.pos += byte_count
        extension.element_size = size
        extension.count = elements


struct Writer[count_only: Bool = False, fixed_size: Bool = False](Movable):
    """Builds a bounded checkpoint byte stream."""

    var data: List[UInt8]
    var limits: Limits
    var counted: Int

    def __init__(out self, limits: Limits, size: Int = 0) raises:
        comptime assert not (Self.count_only and Self.fixed_size)
        limits.validate()
        self.data = List[UInt8]()
        self.counted = 0
        self.limits = limits.copy()
        comptime if Self.fixed_size:
            if size < 0 or size > limits.max_bytes:
                raise Error("Encoded checkpoint exceeds byte limit")
            self.data.resize(unsafe_uninit_length=size)

    def size(self) -> Int:
        comptime if Self.count_only or Self.fixed_size:
            return self.counted
        else:
            return len(self.data)

    def grow(mut self, count: Int) raises:
        # Subtract before adding, so an untrusted size cannot overflow.
        comptime if Self.fixed_size:
            if count < 0 or count > len(self.data) - self.counted:
                raise Error("Encoded checkpoint exceeds sized output")
        else:
            if count < 0 or count > self.limits.max_bytes - self.size():
                raise Error("Encoded checkpoint exceeds byte limit")
        comptime if Self.count_only or Self.fixed_size:
            self.counted += count
        else:
            self.data.resize(unsafe_uninit_length=len(self.data) + count)

    def scalar[dtype: DType](mut self, value: SIMD[dtype, 1]) raises:
        comptime n = width[dtype]()
        var start = self.size()
        self.grow(n)
        comptime if not Self.count_only:
            self.store_scalar(start, value)

    def store_scalar[dtype: DType](mut self, start: Int, value: SIMD[dtype, 1]):
        """Emit into an extent already checked by grow or array sizing."""
        comptime n = width[dtype]()
        comptime if is_little_endian() or n == 1:
            self.data.unsafe_ptr().unsafe_offset(start).unsafe_bitcast[
                SIMD[dtype, 1]
            ]().unsafe_store[alignment=1](value)
        else:
            var bits: UInt64
            comptime if n == 4:
                bits = UInt64(value.to_bits[DType.uint32]())
            else:
                bits = value.to_bits[DType.uint64]()
            comptime for i in range(n):
                self.data.unsafe_ptr().unsafe_offset(start + i).unsafe_write(
                    UInt8((bits >> UInt64(i * 8)) & 255)
                )

    def finish(deinit self) raises -> List[UInt8]:
        comptime if Self.fixed_size:
            if self.counted != len(self.data):
                raise Error("Encoded checkpoint does not fill sized output")
        return self.data^

    def array[dtype: DType](mut self, values: List[SIMD[dtype, 1]]) raises:
        if len(values) > self.limits.max_elements:
            raise Error("Encoded array exceeds element limit")
        comptime if Self.count_only:
            self.counted += self.array_extent[dtype](len(values))
            return
        elif Self.fixed_size and is_little_endian():
            var extent = self.array_extent[dtype](len(values))
            var start = self.size()
            self.grow(extent)
            self.store_scalar(start, UInt64(len(values)))
            if extent > 8:
                unsafe_memcpy(
                    dest=self.data.unsafe_ptr().unsafe_offset(start + 8),
                    src=values.unsafe_ptr().unsafe_bitcast[UInt8](),
                    count=extent - 8,
                )
            return
        self.scalar[DType.uint64](UInt64(len(values)))
        comptime n = width[dtype]()
        if len(values) > (self.limits.max_bytes - self.size()) // n:
            raise Error("Encoded checkpoint exceeds byte limit")
        comptime if Self.count_only:
            self.grow(len(values) * n)
        elif is_little_endian() or n == 1:
            var start = self.size()
            var byte_count = len(values) * n
            self.grow(byte_count)
            if byte_count > 0:
                unsafe_memcpy(
                    dest=self.data.unsafe_ptr().unsafe_offset(start),
                    src=values.unsafe_ptr().unsafe_bitcast[UInt8](),
                    count=byte_count,
                )
        else:
            for value in values:
                self.scalar[dtype](value)

    def array_extent[dtype: DType](self, count: Int) raises -> Int:
        """Check header plus payload size before multiplying the element count.
        """
        var remaining = self.limits.max_bytes - self.size()
        comptime n = width[dtype]()
        if remaining < 8 or count > (remaining - 8) // n:
            raise Error("Encoded checkpoint exceeds byte limit")
        return 8 + count * n

    def extensions(mut self, values: List[Extension]) raises:
        if len(values) > self.limits.max_extensions:
            raise Error("Encoded extension count exceeds limit")
        self.scalar[DType.int32](Int32(len(values)))
        for value in values:
            self.array[DType.uint8](value.name)
            self.scalar[DType.uint64](value.element_size)
            self.scalar[DType.uint64](value.count)
            var start = self.size()
            self.grow(len(value.payload))
            comptime if not Self.count_only:
                if len(value.payload) > 0:
                    unsafe_memcpy(
                        dest=self.data.unsafe_ptr().unsafe_offset(start),
                        src=value.payload.unsafe_ptr(),
                        count=len(value.payload),
                    )
