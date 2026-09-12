"""Named Treelite v4 wire values; constants retain their wire integer types."""


struct Operator:
    """Numerical comparison codes; NONE is reserved for non-split nodes."""

    comptime NONE = Int8(0)
    comptime EQ = Int8(1)
    comptime LT = Int8(2)
    comptime LE = Int8(3)
    comptime GT = Int8(4)
    comptime GE = Int8(5)


struct NodeType:
    """Node kind codes for scalar/vector leaves and numerical/categorical splits.
    """

    comptime LEAF = Int8(0)
    comptime NUMERICAL = Int8(1)
    comptime CATEGORICAL = Int8(2)


struct TaskType:
    """Treelite task codes preserved as metadata; Balsa does not run inference.
    """

    comptime BINARY_CLF = UInt8(0)
    comptime REGRESSOR = UInt8(1)
    comptime MULTI_CLF = UInt8(2)
    comptime LEARNING_TO_RANK = UInt8(3)
    comptime ISOLATION_FOREST = UInt8(4)


struct TypeInfo:
    """Wire tags. UINT32 exists in the enum but is unsupported in v4 models."""

    comptime INVALID = UInt8(0)
    comptime UINT32 = UInt8(1)
    comptime FLOAT32 = UInt8(2)
    comptime FLOAT64 = UInt8(3)


def type_tag[dtype: DType]() -> UInt8:
    comptime assert (
        dtype == DType.float32 or dtype == DType.float64
    ), "Unsupported model precision"
    return TypeInfo.FLOAT32 if dtype == DType.float32 else TypeInfo.FLOAT64
