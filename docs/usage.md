# Constructing and inspecting models

## A numerical stump

```mojo
from balsa import ModelBuilder, TreeBuilder, Operator, save

def main() raises:
    var builder = ModelBuilder[DType.float64](num_feature=1, base_scores=[0.5])
    var tree = TreeBuilder[DType.float64](num_nodes=3)
    tree.numerical_split(0, feature=0, threshold=0.5, op=Operator.LT,
                         left=1, right=2, default_left=True)
    tree.leaf(1, -1.25)
    tree.leaf(2, 2.75)
    builder.add_tree(tree^.build())
    var model = builder^.build()
    save(model, "stump.tl")
```

Run the complete [construction example](../examples/construction.mojo) with
`pixi run example`. Builders default to float32 when precision is omitted.

`TreeBuilder(num_nodes)` reserves dense IDs `0..num_nodes-1`, with root 0.
Define each node exactly once, in any order. Child IDs may refer to nodes yet
to be defined. Numerical splits default to `<`; missing values default right.
`categorical_split(..., categories=[1, 7], categories_right=False)` sends
matching categories left by default. `leaf_vector(node, values)` appends a
vector payload and maintains its offsets. It rejects empty vectors.

`TreeBuilder.build()` consumes the builder and checks that every node is
assigned. Its resulting tree can still be structurally invalid (for example,
unreachable nodes); `ModelBuilder.build()` performs full validation by default
with model metadata. `add_tree` transfers an owned tree and maintains tree counts and
annotations. Both `build()` calls consume their builders, so use `^`.

`ModelBuilder` defaults to regression, one target/class, scalar leaves, identity
postprocessing, zero base score and no averaging. Keyword arguments support
`task_type`, `average_tree_output`, `num_class`, `leaf_vector_shape`,
`base_scores`, `postprocessor`, `sigmoid_alpha`, `ratio_c`, and `attributes`.
The target count comes from `len(num_class)`. An omitted or empty `base_scores`
list creates zeros of shape `num_target * max(num_class)`.

For multi-target or multi-class vector leaves, set `num_class` and
`leaf_vector_shape` explicitly. Set `target_id=-1` and/or `class_id=-1` on
`add_tree` when a tree produces outputs for all targets and/or classes. These
annotations default to zero for scalar trees. `Limits` applies to builders as
well as codec operations; final encoding also enforces serialized byte limits.

The returned model/tree fields remain editable. Add statistics or opaque
extensions through their raw fields, then validate or save. Raw constructors
remain available for bulk import and exact format editing.

Pass `options=ValidationOptions(enabled=False)` to codec calls or
`ModelBuilder.build` to defer automatic model validation. See
[validation policy](validation-policy.md) for the checks that remain.

## Discovering precision

```mojo
from balsa import Model, load_auto, save

# Inside a raising function:
var loaded = load_auto("stump.tl")
if loaded.isa[Model[DType.float32]]():
    print(loaded[Model[DType.float32]].postprocessor_name())
else:
    print(loaded[Model[DType.float64]].postprocessor_name())
save(loaded, "copy.tl")
```

The variant's typed subscript borrows its model. Pass that expression to a
function taking `Model[dtype]` to dispatch once for a whole operation. No
precision conversion occurs. `decode_auto(bytes^)` provides the same behavior
for owned byte lists. `load[dtype]` / `decode[dtype]` remain useful when the
expected precision is known and should be checked.

## Named format constants and text

| Namespace | Constants |
| --- | --- |
| `Operator` | `NONE`, `EQ`, `LT`, `LE`, `GT`, `GE` |
| `NodeType` | `LEAF`, `NUMERICAL`, `CATEGORICAL` |
| `TaskType` | `BINARY_CLF`, `REGRESSOR`, `MULTI_CLF`, `LEARNING_TO_RANK`, `ISOLATION_FOREST` |
| `TypeInfo` | `INVALID`, `UINT32`, `FLOAT32`, `FLOAT64` |

Constants have the format's exact integer types; for example,
`tree.cmp[node] == Operator.LT` works directly with the raw field.
`NONE` is not valid for numerical split nodes. `UINT32` names a wire enum value,
not a supported v4 model precision.

`model.postprocessor_name()` and `model.attributes_text()` return owned UTF-8
strings and raise on invalid UTF-8. Their setters, `set_postprocessor_name`
and `set_attributes_text`, store UTF-8 bytes. Unknown postprocessor names are
allowed; Balsa does not execute them. Attribute JSON remains the caller's
responsibility. The raw byte lists are preserved even if text decoding fails,
so malformed text can still roundtrip without replacement characters.

## Borrowing fields without copies

```mojo
from balsa import Model

def inspect[dtype: DType](model: Model[dtype]) raises:
    var targets = Span(model.target_id)
    var classes = Span(model.class_id)
    for tree in model.trees:
        var thresholds = Span(tree.threshold)
        var categories = tree.categories(0)
        var vector = tree.leaf_values(0)
        print(tree.num_nodes, len(thresholds), len(categories), len(vector))
```

Function arguments borrow by default. `for tree in model.trees` borrows each
tree, and `Span(field)` borrows a contiguous array. This also works for
`num_class`, `leaf_vector_shape`, `base_scores`, children and node types.
Use `.copy()` only when you need independent owned storage; `^` transfers
ownership. Direct field mutation or `for ref tree in model.trees` provides
mutable access when the owner is mutable.

`tree.categories(node)` and `tree.leaf_values(node)` return immutable spans
into the corresponding payload. They check the node index, offset-array
access and payload range even after raw field edits. An empty leaf span denotes
no vector payload, not a scalar leaf value; read `leaf_value[node]` for that.
These accessors check storage bounds, while `validate` checks node kinds and
all field relationships.

Mojo tracks views' origins: views cannot outlive their backing storage or be
used across conflicting mutation of it. Ordinary borrowed access needs no
unsafe pointer and makes no tree copies. Node IDs remain checkpoint indices;
Balsa does not reorder nodes into an execution layout.
