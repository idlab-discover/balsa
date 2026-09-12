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


comptime __version__ = "0.1.0"
"""Balsa library version, independent of the Treelite checkpoint version."""


def version() -> String:
    """Return the library version; prefer the compile-time __version__ constant.

    Retained for compatibility with existing callers.
    """
    return String(__version__)
