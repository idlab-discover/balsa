"""Shared contracts and worker adapter for the controlled codec comparison."""

import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ENGINES = {
    "treelite-native": "Treelite C ABI, normal checks, independent owned output",
    "treelite-python": "Treelite Python API, normal checks",
    "balsa-on": "Editable consuming API; serial semantic validation enabled",
    "balsa-off": "Editable consuming API; semantic validation disabled",
    "balsa-borrow-on": "Editable borrowed-input API; serial semantic validation enabled",
    "balsa-borrow-off": "Editable borrowed-input API; semantic validation disabled",
    "packed-on": "Packed consuming API; serial semantic validation enabled",
    "packed-off": "Packed consuming API; semantic validation disabled",
    "packed-copy": "Preserved-byte copy; setup validated, no timed revalidation",
    "balsa-default": "Editable consuming API; explicit checked four-worker policy (legacy ID, not public defaults)",
}


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, check=True, text=True, **kwargs)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=2) + "\n")


def measure(loops, directory, engine, case, operation):
    directory = Path(directory)
    if engine.startswith("treelite"):
        worker = ([str(directory / "treelite-native")] if engine == "treelite-native"
                  else [sys.executable, str(Path(__file__).with_name("treelite_worker.py"))])
        command = worker + [case["path"], operation, str(loops)]
    elif engine.startswith("packed"):
        op = "packed-decode" if operation == "decode" else "packed-encode"
        command = [str(directory / "packed"), case["path"], op,
                   str(int(engine == "packed-on")), str(loops)]
    else:
        op = "borrowed" if "borrow" in engine and operation == "decode" else operation
        workers = "4" if engine == "balsa-default" else "1"
        command = [str(directory / "balsa"), case["path"], workers, "4096", "65536",
                   str(loops), "1", op]
        if engine.endswith("off"):
            command.append("no-validation")
    result = run(command, capture_output=True, timeout=300,
                 env={**os.environ, "OPENBLAS_NUM_THREADS": "1", "OMP_NUM_THREADS": "1"})
    output = result.stdout.strip().split()
    if engine.startswith("treelite"):
        seconds, checksum = output
        expected = loops * (case["bytes"] if operation == "encode" else 1)
        if int(checksum) != expected:
            raise ValueError("Native/Python checksum mismatch")
        seconds = float(seconds)
    else:
        # These workers check their own checksum and report nanoseconds/call.
        seconds = float(output[-1]) * loops / 1e9
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError(f"Invalid worker duration: {result.stdout!r}")
    return seconds
