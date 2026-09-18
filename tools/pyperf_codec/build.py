"""Build revision-selected editable/packed/native workers and a reproducible 16-shape corpus."""

import argparse
from datetime import datetime, timezone
import io
from pathlib import Path
import platform
import subprocess
import sys
import tarfile

import treelite
from treelite.core import _LIB
from common import ROOT, digest, run, read_json, write_json


def checkout(revision, target):
    commit = run(["git", "rev-parse", "--verify", revision + "^{commit}"], capture_output=True).stdout.strip()
    archive = subprocess.check_output(["git", "archive", commit, "src", "tools"], cwd=ROOT)
    target.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        files.extractall(target, filter="data")
    return commit


def synthetic(path, sizes):
    from treelite.model_builder import ModelBuilder, Metadata, TreeAnnotation, PostProcessorFunc
    builder = ModelBuilder(
        threshold_type="float32", leaf_output_type="float32",
        metadata=Metadata(num_feature=1, task_type="kRegressor", average_tree_output=False,
                          num_target=1, num_class=[1], leaf_vector_shape=(1, 1)),
        tree_annotation=TreeAnnotation(num_tree=len(sizes), target_id=[0]*len(sizes), class_id=[0]*len(sizes)),
        postprocessor=PostProcessorFunc(name="identity"), base_scores=[0.0])
    for n in sizes:
        builder.start_tree()
        for i in range(n):
            builder.start_node(i)
            if 2*i+2 < n:
                builder.numerical_test(feature_id=0, threshold=0.5, default_left=True,
                    opname="<", left_child_key=2*i+1, right_child_key=2*i+2)
            else:
                builder.leaf(1.0)
            builder.end_node()
        builder.end_tree()
    builder.commit().serialize(path)


def corpus(directory):
    sys.path.insert(0, str(ROOT / "tools"))
    from benchmark_decode import prepare
    directory.mkdir()
    prepare(directory)
    cases = read_json(directory / "cases.json")
    for name, sizes in [("leaves", [1]*4096),
                        ("uneven", [255 if i % 16 == 0 else 1 for i in range(4096)]),
                        ("few-large", [1023]*128), ("dominant", [65535]+[1]*4095)]:
        path = directory / f"{name}.tl"
        synthetic(path, sizes)
        cases.append(dict(name=name, path=str(path), trees=len(sizes), nodes=sum(sizes)))
    for case in cases:
        data = Path(case["path"]).read_bytes()
        case.update(bytes=len(data), sha256=digest(case["path"]),
                    dtype={2: "float32", 3: "float64"}[data[12]])
    write_json(directory / "manifest.json", cases)
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--revision", default="HEAD", help="Commit/tag/branch for both workers (default: HEAD)")
    parser.add_argument("--main", help="Override editable worker revision")
    parser.add_argument("--packed", help="Override packed worker revision")
    args = parser.parse_args()
    directory = args.directory.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    assert treelite.__version__ == "4.6.1"
    revisions = {label: checkout(revision, directory / (label + "-src"))
                 for label, revision in [("main", args.main or args.revision), ("packed", args.packed or args.revision)]}
    for binary, label, source in [("balsa", "main", "validation_policy_worker.mojo"),
                                  ("packed", "packed", "packed_worker.mojo")]:
        snapshot = directory / (label + "-src")
        run(["pixi", "run", "mojo", "build", "-O3", "-I", str(snapshot / "src"),
             str(snapshot / "tools" / source), "-o", str(directory / binary)])
    library = Path(_LIB._name).resolve()
    run(["g++", "-O3", "-std=c++17", str(ROOT / "tools/treelite_codec_worker.cpp"),
         str(library), f"-Wl,-rpath,{library.parent}", "-o", str(directory / "treelite-native")])
    corpus(directory / "corpus")
    files = [directory / name for name in ("balsa", "packed", "treelite-native")]
    files += list(Path(__file__).parent.glob("*.py"))
    files += [ROOT / "tools/treelite_codec_worker.cpp", ROOT / "pixi.lock"]
    metadata = dict(
        created_utc=datetime.now(timezone.utc).isoformat(), revisions=revisions,
        platform=platform.platform(), treelite_version=treelite.__version__,
        treelite_library=str(library), treelite_library_sha256=digest(library),
        compiler=run(["pixi", "run", "mojo", "--version"], capture_output=True).stdout.strip(),
        cpp_compiler=run(["g++", "--version"], capture_output=True).stdout.splitlines()[0],
        cpu=run(["lscpu"], capture_output=True).stdout,
        hashes={str(p.resolve()): digest(p) for p in files},
        system_tuning="unchanged; no affinity isolation or governor changes",
    )
    for key, path in {
        "governor": "/sys/devices/system/cpu/cpu14/cpufreq/scaling_governor",
        "driver": "/sys/devices/system/cpu/cpu14/cpufreq/scaling_driver",
        "smt_siblings": "/sys/devices/system/cpu/cpu14/topology/thread_siblings_list",
    }.items():
        metadata[key] = Path(path).read_text().strip() if Path(path).exists() else "unavailable"
    write_json(directory / "build.json", metadata)
    print(f"Built workers and corpus in {directory}", flush=True)


if __name__ == "__main__":
    main()
