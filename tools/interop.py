"""Verify native checkpoint roundtrips and fields against pinned Treelite."""

import hashlib
import json
import subprocess
from pathlib import Path

import treelite

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures"
OUTPUT = ROOT / "build/interop"
BINARY = ROOT / "build/balsa"


def main():
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    assert treelite.__version__ == manifest["producer"] == "4.6.1"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for case in manifest["cases"]:
        checkpoint = FIXTURES / f"{case['name']}.tl"
        assert hashlib.sha256(checkpoint.read_bytes()).hexdigest() == case["sha256"]
        out = OUTPUT / checkpoint.name
        result = subprocess.run(
            [str(BINARY), "roundtrip", str(checkpoint), str(out)],
            capture_output=True, text=True, timeout=10,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert out.read_bytes() == checkpoint.read_bytes(), case["name"]
        restored = treelite.Model.deserialize(out)
        assert json.loads(restored.dump_as_json(pretty_print=False)) == case["metadata"]

    # These checkpoints are constructed in Mojo, not copied from the oracle.
    native_models = []
    for name in ("native-stump", "native-extensions"):
        model = treelite.Model.deserialize(ROOT / f"build/{name}.tl")
        fields = json.loads(model.dump_as_json(pretty_print=False))
        assert fields["num_feature"] == 1
        assert fields["base_scores"] == [0.5]
        assert len(fields["trees"]) == 1
        nodes = fields["trees"][0]["nodes"]
        assert nodes[0]["threshold"] == 0.5
        assert nodes[0]["comparison_op"] == "<"
        assert nodes[0]["default_left"] is True
        assert [node["leaf_value"] for node in nodes[1:]] == [-1.25, 2.75]
        native_models.append(fields)
    # Upstream skips the extensions; all recognized model fields must survive.
    assert native_models[0] == native_models[1]
    print(f"PASS: {len(manifest['cases'])} byte-exact roundtrips and field comparisons; "
          "native-created model and extension records")


if __name__ == "__main__":
    main()
