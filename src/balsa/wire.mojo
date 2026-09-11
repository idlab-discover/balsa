"""Bounded little-endian checkpoint primitives; no pointer reinterpretation."""

from .model import Extension


struct Limits(Copyable, Movable):
    """Allocation/work limits for untrusted checkpoints (not an RSS guarantee).
    """

    var max_bytes: Int
    var max_elements: Int
    var max_trees: Int
    var max_nodes: Int
    var max_extensions: Int

    def __init__(
        out self,
        max_bytes: Int = 64 * 1024 * 1024,
        max_elements: Int = 8 * 1024 * 1024,
        max_trees: Int = 100_000,
        max_nodes: Int = 1_000_000,
        max_extensions: Int = 1024,
    ):
        self.max_bytes = max_bytes
        self.max_elements = max_elements
        self.max_trees = max_trees
        self.max_nodes = max_nodes
        self.max_extensions = max_extensions

    def validate(self) raises:
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


struct Reader(Movable):
    """Owns input bytes and reports the failing field and byte offset."""

    var data: List[UInt8]
    var pos: Int
    var field: String
    var limits: Limits

    def __init__(out self, var data: List[UInt8], limits: Limits) raises:
        limits.validate()
        if len(data) > limits.max_bytes:
            raise Error("Checkpoint exceeds byte limit")
        self.data = data^
        self.pos = 0
        self.field = "header"
        self.limits = limits.copy()

    def fail(self, message: String) raises:
        raise Error(
            "Malformed checkpoint at byte "
            + String(self.pos)
            + " ("
            + self.field
            + "): "
            + message
        )

    def require(self, count: Int) raises:
        if count < 0 or count > len(self.data) - self.pos:
            self.fail("truncated payload")

    def scalar[dtype: DType](mut self) raises -> SIMD[dtype, 1]:
        comptime n = width[dtype]()
        self.require(n)
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
        var count = self.scalar[DType.uint64]()
        comptime n = width[dtype]()
        if count > UInt64(self.limits.max_elements):
            self.fail("array element limit exceeded")
        if count > UInt64((len(self.data) - self.pos) // n):
            self.fail("truncated array")
        var result = List[SIMD[dtype, 1]](capacity=Int(count))
        for _ in range(Int(count)):
            result.append(self.scalar[dtype]())
        return result^

    def extensions(mut self) raises -> List[Extension]:
        var count = self.scalar[DType.int32]()
        if count < 0 or Int(count) > self.limits.max_extensions:
            self.fail("invalid extension count")
        var result = List[Extension]()
        for _ in range(Int(count)):
            var name = self.array[DType.uint8]()
            var size = self.scalar[DType.uint64]()
            var elements = self.scalar[DType.uint64]()
            if elements > UInt64(self.limits.max_elements):
                self.fail("extension element limit exceeded")
            if size > UInt64(self.limits.max_bytes):
                self.fail("extension element size limit exceeded")
            if (
                size != 0
                and elements > UInt64(len(self.data) - self.pos) // size
            ):
                self.fail("truncated extension or size overflow")
            var payload = List[UInt8]()
            for _ in range(Int(size * elements)):
                payload.append(self.scalar[DType.uint8]())
            result.append(Extension(name^, size, elements, payload^))
        return result^


struct Writer(Movable):
    """Builds a bounded checkpoint byte stream."""

    var data: List[UInt8]
    var limits: Limits

    def __init__(out self, limits: Limits) raises:
        limits.validate()
        self.data = List[UInt8]()
        self.limits = limits.copy()

    def scalar[dtype: DType](mut self, value: SIMD[dtype, 1]) raises:
        comptime n = width[dtype]()
        if len(self.data) > self.limits.max_bytes - n:
            raise Error("Encoded checkpoint exceeds byte limit")
        var bits: UInt64
        comptime if n == 1:
            bits = UInt64(value.to_bits[DType.uint8]())
        elif n == 4:
            bits = UInt64(value.to_bits[DType.uint32]())
        else:
            bits = value.to_bits[DType.uint64]()
        for i in range(n):
            self.data.append(UInt8((bits >> UInt64(i * 8)) & 255))

    def finish(deinit self) -> List[UInt8]:
        return self.data^

    def array[dtype: DType](mut self, values: List[SIMD[dtype, 1]]) raises:
        if len(values) > self.limits.max_elements:
            raise Error("Encoded array exceeds element limit")
        self.scalar[DType.uint64](UInt64(len(values)))
        for value in values:
            self.scalar[dtype](value)

    def extensions(mut self, values: List[Extension]) raises:
        if len(values) > self.limits.max_extensions:
            raise Error("Encoded extension count exceeds limit")
        self.scalar[DType.int32](Int32(len(values)))
        for value in values:
            self.array[DType.uint8](value.name)
            self.scalar[DType.uint64](value.element_size)
            self.scalar[DType.uint64](value.count)
            for byte in value.payload:
                self.scalar[DType.uint8](byte)
