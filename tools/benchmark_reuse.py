"""Compare consuming, borrowed, cold-into and reused decode in shuffled blocks.

Run with: pixi run -e benchmark python tools/benchmark_reuse.py
Fresh operations include destruction; reuse retains the destination between calls.
"""

import hashlib
import argparse
import io
import json
from pathlib import Path
import random
import statistics
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "benchmarking" / "reuse"


def run(command):
    return subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True).stdout


def build(revision, out=OUT):
    out.mkdir(exist_ok=True)
    baseline = out / "baseline"
    baseline.mkdir(exist_ok=True)
    commit = run(["git", "rev-parse", "--verify", revision + "^{commit}"]).strip()
    archive = subprocess.check_output(["git", "archive", commit, "src", "tools"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        files.extractall(baseline, filter="data")
    for label, source in [("before", baseline), ("after", ROOT)]:
        run(["pixi", "run", "mojo", "build", "-O3", "-I", str(source / "src"),
             str(source / "tools/validation_policy_worker.mojo"), "-o", str(out / label)])
    provenance = {
        "baseline": commit,
        "compiler": run(["pixi", "run", "mojo", "--version"]).strip(),
        "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in (ROOT / "src/balsa").glob("*.mojo")},
        "cpu": 14, "blocks": 5, "warmups": 8,
    }
    (out / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")


def measure(case, operation, enabled, loops):
    binary = "before" if operation == "before" else "after"
    op = "decode" if operation in ("before", "consuming") else operation
    command = ["taskset", "-c", "14", str(OUT / binary), case["path"],
               "1", "4096", "65536", str(loops), "1", op]
    if not enabled:
        command.append("no-validation")
    return float(run(command).split()[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--baseline", default="46d5012", help="Pre-change baseline revision")
    args = parser.parse_args()
    if not args.skip_build:
        build(args.baseline)
    cases = json.loads((ROOT / "benchmarking/validation-opt-out/corpus/manifest.json").read_text())
    for shape in ("leaves", "uneven", "few-large", "dominant"):
        path = ROOT / "build/threading" / f"{shape}.tl"
        if path.exists():
            cases.append(dict(name=shape, path=str(path)))
    operations = ["before", "consuming", "borrowed", "cold-into", "reuse"]
    jobs = []
    for case in cases:
        for enabled in (False, True):
            for operation in operations:
                estimate = measure(case, operation, enabled, 2)
                loops = max(100, min(2000, int(100_000_000 / estimate)))
                jobs.extend((block, case, operation, enabled, loops) for block in range(5))
    random.Random(1509).shuffle(jobs)
    records = []
    for index, (block, case, operation, enabled, loops) in enumerate(jobs):
        records.append(dict(block=block, case=case["name"], operation=operation,
                            validation=enabled, loops=loops,
                            ns=measure(case, operation, enabled, loops)))
        if index % 50 == 0:
            print(f"{index}/{len(jobs)} batches", flush=True)
    (OUT / "timings.json").write_text(json.dumps(records, indent=2) + "\n")
    summary = []
    for case in cases:
        for enabled in (False, True):
            row = dict(case=case["name"], validation=enabled)
            for operation in operations:
                row[operation] = statistics.median(r["ns"] for r in records
                    if r["case"] == case["name"] and r["validation"] == enabled
                    and r["operation"] == operation)
            summary.append(row)
            print(json.dumps(row), flush=True)
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
