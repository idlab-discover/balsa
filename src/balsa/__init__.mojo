"""Native Treelite v4 checkpoint storage, serialization and validation."""

from .codec import (
    decode,
    encode,
    load,
    save,
    decode_auto,
    load_auto,
    checkpoint_dtype,
    AnyModel,
)
from .constants import Operator, NodeType, TaskType, TypeInfo
from .model import Model, Tree, Extension
from .builder import ModelBuilder, TreeBuilder
from .validation import validate, ValidationOptions
from .wire import Limits


def version() -> String:
    """Return the Balsa project version."""
    return "0.1.0"
