"""Measure encoding before/after in shuffled CPU-pinned subprocess blocks."""

import argparse
import json
import random
import statistics

from benchmark_reuse import ROOT, build, run

OUT = ROOT / "benchmarking" / "encode-sizing"


def measure(case, engine, enabled, loops):
    command = ["taskset", "-c", "14", str(OUT / engine), case["path"],
               "1", "4096", "65536", str(loops), "1", "encode"]
    if not enabled:
        command.append("no-validation")
    return float(run(command).split()[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="6de1b0a")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    if not args.skip_build:
        build(args.baseline, OUT)
    cases = json.loads((ROOT / "benchmarking/validation-opt-out/corpus/manifest.json").read_text())
    for shape in ("leaves", "uneven", "few-large", "dominant"):
        path = ROOT / "build/threading" / f"{shape}.tl"
        if path.exists():
            cases.append(dict(name=shape, path=str(path)))
    jobs = []
    for case in cases:
        for enabled in (False, True):
            for engine in ("before", "after"):
                estimate = measure(case, engine, enabled, 2)
                loops = max(100, min(4000, int(100_000_000 / estimate)))
                jobs.extend((block, case, engine, enabled, loops) for block in range(5))
    random.Random(15095).shuffle(jobs)
    records = []
    for index, (block, case, engine, enabled, loops) in enumerate(jobs):
        records.append(dict(block=block, case=case["name"], engine=engine,
                            validation=enabled, loops=loops,
                            ns=measure(case, engine, enabled, loops)))
        if index % 40 == 0:
            print(f"{index}/{len(jobs)} batches", flush=True)
    (OUT / "timings.json").write_text(json.dumps(records, indent=2) + "\n")
    summary = []
    for case in cases:
        for enabled in (False, True):
            row = dict(case=case["name"], validation=enabled)
            for engine in ("before", "after"):
                row[engine] = statistics.median(r["ns"] for r in records
                    if r["case"] == case["name"] and r["validation"] == enabled
                    and r["engine"] == engine)
            row["change_percent"] = 100 * (row["after"] / row["before"] - 1)
            summary.append(row)
            print(json.dumps(row), flush=True)
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
