"""Verify saved framework checkpoints through Balsa and back through Treelite.

Only Treelite is needed to run this check; training is a separate task.
"""

import hashlib
import json
import subprocess
from pathlib import Path

import treelite

ROOT = Path(__file__).resolve().parents[1]


def main():
    fixtures = ROOT / "tests/fixtures/frameworks"
    manifest = json.loads((fixtures / "manifest.json").read_text())
    assert treelite.__version__ == manifest["versions"]["treelite"]
    output = ROOT / "build/framework-interop"
    output.mkdir(parents=True, exist_ok=True)
    for name, sha256 in manifest["source_artifacts"].items():
        assert hashlib.sha256((fixtures / name).read_bytes()).hexdigest() == sha256
    for case in manifest["cases"]:
        source = fixtures / f"{case['name']}.tl"
        data = source.read_bytes()
        assert hashlib.sha256(data).hexdigest() == case["sha256"], case["name"]
        assert len(data) == case["bytes"]
        path = output / source.name
        result = subprocess.run(
            [str(ROOT / "build/balsa"), "roundtrip", str(source), str(path)],
            capture_output=True, text=True, timeout=30,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert path.read_bytes() == data, case["name"]
        restored = treelite.Model.deserialize(path)
        assert json.loads(restored.dump_as_json(pretty_print=False)) == case["metadata"], case["name"]
        assert restored.serialize_bytes() == data, case["name"]
        print(f"PASS: {case['name']} — byte-exact roundtrip and upstream fields")
    print(f"PASS: {len(manifest['cases'])} trained-framework checkpoints")


if __name__ == "__main__":
    main()
