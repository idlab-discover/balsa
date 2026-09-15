"""Native Treelite v4 storage with performance-first, read-only packed loading.

Automatic semantic validation is off. Pass ValidationOptions(enabled=True) for
uncertain input; bounds and format checks remain active. Use load_editable or
packed.to_model() for editing. Packed output never repeats semantic validation.
"""

from .packed import (
    decode,
    load,
    decode_auto,
    load_auto,
    PackedModel,
    AnyPackedModel,
)
from .storage import encode, save
from .codec import (
    decode as decode_editable,
    decode_into,
    load as load_editable,
    decode_auto as decode_auto_editable,
    load_auto as load_auto_editable,
    checkpoint_dtype,
    AnyModel,
)
from .constants import Operator, NodeType, TaskType, TypeInfo
from .model import Model, Tree, Extension
from .builder import ModelBuilder, TreeBuilder
from .validation import validate, ValidationOptions
from .wire import Limits


comptime __version__ = "0.2.0"
"""Balsa library version, independent of the Treelite checkpoint version."""


def version() -> String:
    """Return the library version; prefer the compile-time __version__ constant.

    Retained for compatibility with existing callers.
    """
    return String(__version__)
