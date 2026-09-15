"""Save packed checkpoints or serialize editable fields through one interface."""

import balsa.codec as editable
import balsa.packed as packed
from .model import Model
from .wire import Limits
from .validation import ValidationOptions


def encode[dtype: DType](model: packed.PackedModel[dtype]) -> List[UInt8]:
    """Copy retained serialization without semantic revalidation."""
    return packed.encode(model)


def save[dtype: DType](model: packed.PackedModel[dtype], path: String) raises:
    """Copy retained serialization without semantic revalidation."""
    packed.save(model, path)


def encode(model: packed.AnyPackedModel) -> List[UInt8]:
    """Copy retained serialization without semantic revalidation."""
    return packed.encode(model)


def save(model: packed.AnyPackedModel, path: String) raises:
    """Copy retained serialization without semantic revalidation."""
    packed.save(model, path)


def encode[
    dtype: DType
](
    model: Model[dtype],
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> List[UInt8]:
    """Serialize editable fields; pass enabled=True options for semantic checks.
    """
    return editable.encode(model, limits, options)


def save[
    dtype: DType
](
    model: Model[dtype],
    path: String,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises:
    """Serialize editable fields; pass enabled=True options for semantic checks.
    """
    editable.save(model, path, limits, options)


def encode(
    model: editable.AnyModel,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises -> List[UInt8]:
    """Serialize editable fields; pass enabled=True options for semantic checks.
    """
    return editable.encode(model, limits, options)


def save(
    model: editable.AnyModel,
    path: String,
    limits: Limits = Limits(),
    options: ValidationOptions = ValidationOptions(),
) raises:
    """Serialize editable fields; pass enabled=True options for semantic checks.
    """
    editable.save(model, path, limits, options)
