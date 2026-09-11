"""Generate small deterministic checkpoints with pinned Treelite (offline only)."""

import argparse
import hashlib
import json
import struct
import tempfile
from pathlib import Path

import treelite
from treelite.model_builder import Metadata, ModelBuilder, PostProcessorFunc, TreeAnnotation

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "a2cd458e2140052a2234402835bd02815d11458e"


def build(dtype, *, op="<", default_left=False, kind="stump", average=False,
          sigmoid=False, stats=False, base=0.25):
    vector = kind == "vector"
    multi = kind == "multi_target"
    shape = (2, 1) if multi else (1, 3) if vector else (1, 1)
    count = 3 if average or kind == "deep" else 1
    builder = ModelBuilder(
        threshold_type=dtype, leaf_output_type=dtype,
        metadata=Metadata(num_feature=1, task_type="kMultiClf" if vector else
                          "kBinaryClf" if sigmoid else "kRegressor",
                          average_tree_output=average, num_target=2 if multi else 1,
                          num_class=[1, 1] if multi else [3] if vector else [1],
                          leaf_vector_shape=shape),
        tree_annotation=TreeAnnotation(num_tree=count,
                                       target_id=[-1 if multi else 0] * count,
                                       class_id=[-1 if vector else 0] * count),
        postprocessor=PostProcessorFunc(name="identity_multiclass" if vector else
                                        "sigmoid" if sigmoid else "identity",
                                        sigmoid_alpha=1.7),
        base_scores=[base] * (shape[0] * shape[1]),
        attributes={"balsa_fixture": True, "unicode": "é🌲"} if stats else None,
    )
    for tree_id in range(count):
        builder.start_tree()
        builder.start_node(0)
        if kind == "leaf":
            builder.leaf(1.25)
        elif kind == "category":
            builder.categorical_test(feature_id=0, default_left=default_left,
                                     category_list=[0, 2, 7], category_list_right_child=True,
                                     left_child_key=1, right_child_key=2)
        else:
            builder.numerical_test(feature_id=0, threshold=0.5, default_left=default_left,
                                   opname=op, left_child_key=1, right_child_key=2)
        if stats:
            builder.data_count(10)
            builder.sum_hess(7.25)
            if kind != "leaf":
                builder.gain(0.125)
        builder.end_node()
        if kind != "leaf":
            for node, value in [(1, -1.25 + tree_id), (2, 2.75 - tree_id)]:
                builder.start_node(node)
                if kind == "deep" and node == 1:
                    builder.numerical_test(feature_id=0, threshold=0.0, default_left=True,
                                           opname=">=", left_child_key=3, right_child_key=4)
                else:
                    builder.leaf([value, value + 0.25] if multi else
                                 [value, value + 0.25, value + 0.5] if vector else value)
                if stats:
                    builder.data_count(4 if node == 1 else 6)
                builder.end_node()
            if kind == "deep":
                for node, value in [(3, 0.125), (4, -3.25)]:
                    builder.start_node(node)
                    builder.leaf(value)
                    builder.end_node()
        builder.end_tree()
    return builder.commit()


def cases():
    for dtype in ("float32", "float64"):
        yield f"{dtype}_op2_missing0", dtype, {}
        for kind in ("leaf", "deep", "category", "vector", "multi_target"):
            yield f"{dtype}_{kind}", dtype, dict(
                kind=kind, stats=kind == "deep", average=kind == "deep"
            )
        yield f"{dtype}_sigmoid", dtype, dict(sigmoid=True)


def annotate_stump(checkpoint):
    """Independent offsets for the float32 stump, directly from the v4 spec."""
    cursor = 0
    fields = []

    def scalar(name, fmt):
        nonlocal cursor
        size = struct.calcsize("<" + fmt)
        value, = struct.unpack_from("<" + fmt, checkpoint, cursor)
        fields.append(dict(field=name, offset=cursor, bytes=size, value=value))
        cursor += size
        return value

    def array(name, fmt):
        nonlocal cursor
        count = scalar(name + ".count", "Q")
        size = struct.calcsize("<" + fmt) * count
        fields.append(dict(field=name, offset=cursor, bytes=size, elements=count))
        cursor += size

    for name in ("major", "minor", "patch"):
        scalar(name, "i")
    scalar("threshold_type", "B")
    scalar("leaf_output_type", "B")
    assert scalar("num_tree", "Q") == 1
    scalar("num_feature", "i")
    scalar("task_type", "B")
    scalar("average_tree_output", "B")
    scalar("num_target", "i")
    for name in ("num_class", "leaf_vector_shape", "target_id", "class_id"):
        array(name, "i")
    array("postprocessor", "B")
    scalar("sigmoid_alpha", "f")
    scalar("ratio_c", "f")
    array("base_scores", "d")
    array("attributes", "B")
    assert scalar("model_extensions", "i") == 0
    scalar("tree.num_nodes", "i")
    scalar("tree.has_categorical_split", "B")
    for name, fmt in [("node_type", "b"), ("cleft", "i"), ("cright", "i"),
                      ("split_index", "i"), ("default_left", "B"), ("leaf_value", "f"),
                      ("threshold", "f"), ("cmp", "b"), ("category_list_right_child", "B"),
                      ("leaf_vector", "f"), ("leaf_vector_begin", "Q"), ("leaf_vector_end", "Q"),
                      ("category_list", "I"), ("category_list_begin", "Q"), ("category_list_end", "Q"),
                      ("data_count", "Q"), ("data_count_present", "B"), ("sum_hess", "d"),
                      ("sum_hess_present", "B"), ("gain", "d"), ("gain_present", "B")]:
        array("tree." + name, fmt)
    assert scalar("tree.extensions", "i") == 0
    assert scalar("tree.node_extensions", "i") == 0
    assert cursor == len(checkpoint)
    return dict(checkpoint="float32_op2_missing0.tl", size=cursor, fields=fields)


def generate(directory):
    if treelite.__version__ != "4.6.1":
        raise RuntimeError("Fixture producer must be Treelite 4.6.1")
    directory.mkdir(parents=True, exist_ok=True)
    # The resolved wheel URL and SHA256 are recorded in the Pixi lockfile.
    # Extract that entry rather than downloading a second copy of the wheel.
    lock = (ROOT / "pixi.lock").read_text()
    start = lock.index("- pypi: https://", lock.index("packages:"))
    entries = lock[start:].split("\n- pypi: ")
    wheel_entry = next(e for e in entries if "treelite-4.6.1-" in e.splitlines()[0])
    wheel_url = wheel_entry.splitlines()[0].removeprefix("- pypi: ")
    wheel_hash = next(line.split("sha256:", 1)[1].strip() for line in wheel_entry.splitlines()
                      if "sha256:" in line)
    records = []
    for name, dtype, config in cases():
        model = build(dtype, **config)
        checkpoint = model.serialize_bytes()
        restored = treelite.Model.deserialize_bytes(checkpoint)
        assert restored.serialize_bytes() == checkpoint
        (directory / f"{name}.tl").write_bytes(checkpoint)
        record = dict(name=name, dtype=dtype, config=config,
                      sha256=hashlib.sha256(checkpoint).hexdigest(),
                      metadata=json.loads(restored.dump_as_json(pretty_print=False)))
        records.append(record)
    manifest = dict(producer=treelite.__version__, source_reference=SOURCE,
                    wheel_url=wheel_url, wheel_sha256=wheel_hash,
                    platform="linux-64", byteorder="little",
                    command="pixi run -e oracle fixtures", cases=records)
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    layout = annotate_stump((directory / "float32_op2_missing0.tl").read_bytes())
    (directory / "stump-layout.json").write_text(json.dumps(layout, indent=2) + "\n")
    print(f"Generated {len(records)} Treelite {treelite.__version__} fixtures in {directory}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "tests/fixtures")
    parser.add_argument("--check", action="store_true", help="Regenerate in a temporary directory and compare every artifact")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="balsa-fixtures-") as temporary:
            generated = Path(temporary)
            generate(generated)
            expected_names = {p.name for p in args.output.iterdir() if p.is_file()}
            actual_names = {p.name for p in generated.iterdir()}
            assert actual_names == expected_names, (actual_names ^ expected_names)
            for name in actual_names:
                assert (generated / name).read_bytes() == (args.output / name).read_bytes(), name
        print("PASS: fixture regeneration is byte-for-byte reproducible")
    else:
        generate(args.output)
