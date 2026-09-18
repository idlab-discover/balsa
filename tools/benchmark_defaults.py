"""Matched local release check; warmed codec timing, not disk I/O or peak RSS.

Run with pixi run -e benchmark python tools/benchmark_defaults.py OUTPUT FILE...
Defaults to HEAD; --revision selects historical source and its worker.
The current compiler environment is used; uncommitted source is excluded.
"""
import argparse
import hashlib
import json
import io
import tarfile
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--revision", default="HEAD", help="Library and worker commit/tag/branch (default: HEAD)")
    parser.add_argument("--cpu", type=int, default=min(os.sched_getaffinity(0)))
    parser.add_argument("--batches", type=int, default=5)
    args = parser.parse_args()
    if args.batches < 1 or args.cpu not in os.sched_getaffinity(0):
        parser.error("positive batches and an available CPU are required")
    args.output.mkdir(parents=True, exist_ok=False)
    binary = (args.output / "worker").resolve()
    revision = subprocess.check_output(["git", "rev-parse", "--verify", args.revision + "^{commit}"], cwd=ROOT, text=True).strip()
    snapshot = (args.output / "source").resolve()
    snapshot.mkdir()
    archive = subprocess.check_output(["git", "archive", revision, "src", "tools"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        files.extractall(snapshot, filter="data")
    subprocess.run(["mojo", "build", "-O3", "-I", str(snapshot / "src"), str(snapshot / "tools/packed_worker.mojo"), "-o", str(binary)], cwd=ROOT, check=True)
    arms = {
        "default-decode": ("default-decode", 0),
        "packed-off": ("packed-decode", 0),
        "packed-on": ("checked-decode", 1),
        "editable-off": ("decode", 0),
        "editable-on": ("decode", 1),
        "default-output": ("default-encode", 0),
        "editable-output": ("encode", 0),
    }
    results = {str(p): {a: [] for a in arms} for p in args.files}
    rng = random.Random(20260915)
    for _ in range(args.batches):
        schedule = [(p, a) for p in args.files for a in arms]
        rng.shuffle(schedule)
        for path, arm in schedule:
            operation, checked = arms[arm]
            loops = 100 if path.stat().st_size > 1_000_000 else 10000
            run = subprocess.run(["taskset", "-c", str(args.cpu), str(binary), str(path.resolve()), operation, str(checked), str(loops)], text=True, capture_output=True, check=True)
            results[str(path)][arm].append(float(run.stdout.strip()))
    report = {
        "utc": datetime.now(timezone.utc).isoformat(),
        "cpu": args.cpu, "platform": platform.platform(), "revision": revision,
        "compiler": subprocess.check_output(["mojo", "--version"], text=True).strip(),
        "source_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((snapshot / "src/balsa").glob("*.mojo"))},
        "worker_sha256": hashlib.sha256((snapshot / "tools/packed_worker.mojo").read_bytes()).hexdigest(),
        "input_sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in args.files},
        "nanoseconds_per_call": results,
    }
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    rows = ["# Public API benchmark", "", "Median microseconds per call; five shuffled batches by default. Consuming decode", "includes the input copy and result destruction. Checked runs use one worker.", "Output compares copying packed bytes with serializing editable fields. File I/O,", "first-use latency, conversion and peak memory are excluded. Local regression", "evidence only; large forests repeat trained trees.", "", "| Input | Default decode | Packed off | Packed on | Editable off | Editable on | Default output | Editable output |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for path, values in results.items():
        rows.append("| " + Path(path).name + " | " + " | ".join(f"{statistics.median(values[a])/1000:.3f}" for a in arms) + " |")
    rows += ["", f"Compiler: {report['compiler']}. CPU affinity: {args.cpu}.", "", "Reproduce with `pixi run -e benchmark python tools/benchmark_defaults.py OUTPUT FILE...`.", "Raw samples and source/input hashes are in OUTPUT/results.json."]
    (args.output / "report.md").write_text("\n".join(rows) + "\n")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
