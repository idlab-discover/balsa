"""Run two reversed-order blocks, retaining all pyperf JSON, logs and warnings."""

import argparse
from datetime import datetime, timezone
from pathlib import Path
import random
import subprocess
import sys
import time

from common import ENGINES, ROOT, digest, read_json, write_json, measure


def schedule(cases, cpu, multicore):
    groups = {"decode": ["treelite-native", "treelite-python", "balsa-on", "balsa-off",
                         "balsa-borrow-on", "balsa-borrow-off", "packed-on", "packed-off"],
              "encode": ["treelite-native", "treelite-python", "balsa-on", "balsa-off", "packed-copy"]}
    pairs = [(case["name"], operation) for case in cases for operation in groups]
    random.Random(150915).shuffle(pairs)
    jobs = []
    for block in range(2):
        for case, operation in pairs:
            engines = groups[operation] if block == 0 else groups[operation][::-1]
            for engine in engines:
                jobs.append(dict(section="serial", block=block, case=case,
                                 operation=operation, engine=engine, affinity=cpu))
    for block in range(2):
        for case in cases:
            if not case["name"].endswith("x1667"):
                continue
            for operation in ("decode", "encode"):
                engines = ["treelite-native", "balsa-default"]
                for engine in (engines if block == 0 else engines[::-1]):
                    jobs.append(dict(section="default", block=block, case=case["name"],
                                     operation=operation, engine=engine, affinity=multicore))
    return jobs


def stem(job):
    return "-".join(str(job[k]) for k in ("section", "block", "case", "operation", "engine"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--cpu", default="14")
    parser.add_argument("--multicore", default="14-17")
    args = parser.parse_args()
    directory = args.directory.resolve()
    build = read_json(directory / "build.json")
    for path, expected in build["hashes"].items():
        if digest(path) != expected:
            raise ValueError(f"Build/harness hash changed: {path}")
    cases = read_json(directory / "corpus/manifest.json")
    settings_path = directory / "schedule.json"
    if settings_path.exists():
        settings = read_json(settings_path)
    else:
        settings = dict(created_utc=datetime.now(timezone.utc).isoformat(),
                        processes_per_block=3, values_per_process=5, warmups=2, min_time=0.1,
                        schedule=schedule(cases, args.cpu, args.multicore), engines=ENGINES)
        write_json(settings_path, settings)
    results = directory / "results"
    results.mkdir(exist_ok=True)
    if not (directory / "preflight.json").exists():
        verified = []
        for case in cases:
            if digest(case["path"]) != case["sha256"]:
                raise ValueError("Corpus hash changed")
            for engine in ENGINES:
                operations = ["encode"] if engine == "packed-copy" else ["decode"]
                if engine in ("treelite-native", "treelite-python", "balsa-on", "balsa-off", "balsa-default"):
                    operations.append("encode")
                for operation in operations:
                    measure(1, directory, engine, case, operation)
                    verified.append([case["name"], engine, operation])
        write_json(directory / "preflight.json", verified)
        print(f"Preflight passed: {len(verified)} byte-parity/checksum configurations", flush=True)
    for index, job in enumerate(settings["schedule"]):
        output = results / (stem(job) + ".json")
        if job.get("complete") and output.exists():
            continue
        if output.exists():
            raise RuntimeError(f"Unfinished output exists; inspect before retrying: {output}")
        command = [sys.executable, str(Path(__file__).with_name("runner.py")),
                   "--directory", str(directory), "--engine", job["engine"],
                   "--case", job["case"], "--operation", job["operation"],
                   "--affinity", job["affinity"], "--processes", "3", "--values", "5",
                   "--warmups", "2", "--min-time", "0.1", "--timeout", "300", "-o", str(output)]
        print(f"[{index+1}/{len(settings['schedule'])}] {stem(job)}", flush=True)
        started = time.monotonic()
        with (results / (stem(job) + ".log")).open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError((results / (stem(job) + ".log")).read_text())
        job.update(complete=True, wall_seconds=time.monotonic()-started)
        write_json(settings_path, settings)
    settings["finished_utc"] = datetime.now(timezone.utc).isoformat()
    write_json(settings_path, settings)
    print("Completed all controlled pyperf cells", flush=True)


if __name__ == "__main__":
    main()
