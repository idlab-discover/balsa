"""Native Treelite v4 checkpoint storage, serialization and validation."""

from .codec import decode, encode, load, save
from .model import Model, Tree, Extension
from .validation import validate
from .wire import Limits


def version() -> String:
    """Return the Balsa project version."""
    return "0.1.0"
