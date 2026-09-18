"""Linux storage workload: fresh workers, warm file cache, operation time and RSS."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import tarfile
import time

import treelite
from treelite.core import _LIB

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent


def run(command, **kwargs):
    return subprocess.run(list(map(str, command)), cwd=ROOT, check=True, text=True, **kwargs)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--revision", default="HEAD")
    parser.add_argument("--cpu", type=int, default=min(os.sched_getaffinity(0)))
    parser.add_argument("--repeats", type=int, default=7)
    args = parser.parse_args()
    if args.repeats < 3 or args.cpu not in os.sched_getaffinity(0):
        parser.error("At least three repetitions and an available CPU required")
    directory, corpus = args.directory.resolve(), args.corpus.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    commit = run(["git", "rev-parse", "--verify", args.revision + "^{commit}"], capture_output=True).stdout.strip()
    snapshot = directory / "source"
    snapshot.mkdir()
    archive = subprocess.check_output(["git", "archive", commit, "src", "pixi.toml", "pixi.lock"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(snapshot, filter="data")
    shutil.copytree(TOOLS, directory / "harness", ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(corpus, directory / "corpus")
    corpus = directory / "corpus"
    manifest = json.loads((corpus / "manifest.json").read_text())
    build_times = {}
    library = Path(_LIB._name).resolve()
    for name, command in [
        ("balsa", ["pixi", "run", "--locked", "mojo", "build", "-O3", "-I", snapshot / "src",
                   directory / "harness/worker.mojo", "-o", directory / "balsa"]),
        ("measure", ["g++", "-O2", directory / "harness/measure.cpp", "-o", directory / "measure"]),
        ("native", ["g++", "-O3", "-std=c++17", directory / "harness/native.cpp", library,
                    f"-Wl,-rpath,{library.parent}", "-o", directory / "native"]),
    ]:
        start = time.monotonic()
        run(command)
        build_times[name] = time.monotonic()-start
    metadata = dict(created_utc=datetime.now(timezone.utc).isoformat(), revision=commit,
        host=platform.node(), platform=platform.platform(), cpu=args.cpu, repeats=args.repeats,
        mojo=run(["pixi", "run", "--locked", "mojo", "--version"], capture_output=True).stdout.strip(),
        cxx=run(["g++", "--version"], capture_output=True).stdout.splitlines()[0],
        cpu_info=run(["lscpu"], capture_output=True).stdout, treelite=treelite.__version__,
        treelite_library_sha256=sha(library), build_wall_seconds=build_times,
        harness_hashes={p.name: sha(p) for p in (directory / "harness").iterdir() if p.is_file()},
        binary_hashes={n: sha(directory / n) for n in ["balsa", "native", "measure"]},
        lock_sha256=sha(ROOT / "pixi.lock"),
        contracts=dict(cache="Input pre-read before every process; no cold-disk claim",
            operation="One first operation in a fresh process; result destruction excluded",
            wall="Worker launch through exit, including setup, destruction, taskset and wait4 launcher",
            rss="Linux wait4 maximum resident set of worker, KiB; includes runtime and setup, not orchestrator",
            save="File write/close without fsync; not durable-storage latency",
            conversion="Packed input retained alongside editable result; serial validation on/off",
            checks="Balsa semantic on/off; Treelite normal checks, not identical validation"))
    write(directory / "build.json", metadata)
    jobs = []
    for case in manifest["cases"]:
        if sha(corpus / case["file"]) != case["sha256"]:
            raise ValueError("Corpus hash mismatch")
        # Untimed upstream byte-roundtrip check.
        if treelite.Model.deserialize(corpus / case["file"]).serialize_bytes() != (corpus / case["file"]).read_bytes():
            raise ValueError("Upstream parity failed")
        for checked in [0, 1]:
            output = directory / "verify-convert.tl"
            run([directory / "balsa", corpus / case["file"], "verify-convert", checked,
                 output, case["dtype"]], capture_output=True)
            if output.read_bytes() != (corpus / case["file"]).read_bytes():
                raise ValueError("Conversion parity failed")
            output.unlink()
        for op in ["load-packed", "load-editable", "save-packed", "save-editable", "convert",
                   "roundtrip-packed", "roundtrip-editable"]:
            for checked in [0, 1]:
                jobs.append((case, "balsa", op, checked))
        for op in ["load", "save", "roundtrip"]:
            jobs.append((case, "native", op, None))
    samples = []
    for repeat in range(args.repeats):
        ordered = jobs.copy()
        random.Random(20260918 + repeat).shuffle(ordered)
        for case, engine, op, checked in ordered:
            path = corpus / case["file"]
            data = path.read_bytes()  # Warm input cache, outside worker and wall timer.
            output = directory / "output.tl"
            output.unlink(missing_ok=True)
            if engine == "balsa":
                command = [directory / engine, path, op, checked, output, case["dtype"]]
            else:
                command = [directory / engine, path, op, output]
            start = time.perf_counter_ns()
            result = run(["taskset", "-c", args.cpu, directory / "measure", *command], capture_output=True)
            wall_ns = time.perf_counter_ns() - start
            ns, rss = map(int, result.stdout.split())
            if ns <= 0 or rss <= 0:
                raise ValueError("Invalid timing/RSS")
            if op.startswith(("save", "roundtrip")) and output.read_bytes() != data:
                raise ValueError(f"Byte parity failed: {engine} {op} {case['name']}")
            samples.append(dict(repeat=repeat, case=case["name"], engine=engine, operation=op,
                                checked=checked, operation_ns=ns, wall_ns=wall_ns, peak_rss_kib=rss,
                                stderr=result.stderr))
        write(directory / "samples.json", samples)
        print(f"Completed shuffled repetition {repeat+1}/{args.repeats}", flush=True)
    output.unlink(missing_ok=True)
    groups = defaultdict(list)
    for sample in samples:
        groups[(sample["case"], sample["engine"], sample["operation"], sample["checked"])].append(sample)
    summary = []
    for (case, engine, op, checked), values in groups.items():
        row = dict(case=case, engine=engine, operation=op, checked=checked, samples=len(values))
        for key in ["operation_ns", "wall_ns", "peak_rss_kib"]:
            row[key] = dict(median=statistics.median(v[key] for v in values),
                            min=min(v[key] for v in values), max=max(v[key] for v in values))
        summary.append(row)
    write(directory / "summary.json", summary)
    lines = ["# Storage workload measurements", "", f"Library revision: `{commit}`. Host: `{metadata['host']}`.", "",
             "Seven fresh-process samples per cell by default; table reports medians. See build.json for contracts.", "",
             "| Case | Engine | Operation | Checked | Operation ms | Process wall ms | Peak RSS MiB |",
             "| --- | --- | --- | --- | ---: | ---: | ---: |"]
    for row in sorted(summary, key=lambda r: (r["case"], r["operation"], r["engine"], str(r["checked"]))):
        lines.append(f"| {row['case']} | {row['engine']} | {row['operation']} | {row['checked']} | "
                     f"{row['operation_ns']['median']/1e6:.3f} | {row['wall_ns']['median']/1e6:.3f} | "
                     f"{row['peak_rss_kib']['median']/1024:.2f} |")
    (directory / "tables.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
