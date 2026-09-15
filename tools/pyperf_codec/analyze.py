"""Audit completed pyperf cells and retain block-aware descriptive comparisons."""

import argparse
from collections import defaultdict
from pathlib import Path
import random
from statistics import mean, median, stdev

import pyperf

from common import ENGINES, digest, read_json, write_json
from controlled import stem


def affinity(value):
    cpus = set()
    for part in value.split(","):
        bounds = [int(v) for v in part.split("-")]
        cpus.update(range(bounds[0], bounds[-1] + 1))
    return cpus


def load_cell(directory, job, expected):
    path = directory / "results" / (stem(job) + ".json")
    suite = pyperf.BenchmarkSuite.load(str(path))
    bench = suite.get_benchmark(f"{job['case']}/{job['operation']}")
    metadata = bench.get_metadata()
    for key, value in {**expected, "engine": job["engine"], "contract": ENGINES[job["engine"]]}.items():
        if metadata[key] != value:
            raise ValueError(f"{path}: inconsistent {key}")
    if affinity(metadata["cpu_affinity"]) != affinity(job["affinity"]):
        raise ValueError(f"{path}: wrong CPU affinity")
    runs = [list(run.values) for run in bench.get_runs() if run.values]
    if len(runs) != 3 or any(len(run) != 5 for run in runs):
        raise ValueError(f"{path}: expected three groups of five values")
    log = path.with_suffix(".log").read_text()
    warnings = [line for line in log.splitlines() if line.startswith("* ")]
    return runs, warnings


def process_means(blocks):
    return [mean(run) for block in blocks for run in block["runs"]]


def percentile(values, fraction):
    values = sorted(values)
    index = (len(values) - 1) * fraction
    lower = int(index)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (values[upper] - values[lower]) * (index - lower)


def describe(blocks):
    centers = process_means(blocks)
    values = [value for block in blocks for run in block["runs"] for value in run]
    return dict(mean_seconds=mean(centers), median_batch_seconds=median(values),
                p95_batch_seconds=percentile(values, .95),
                process_cv=stdev(centers) / mean(centers), values=len(values),
                block_means={str(b["block"]): mean(map(mean, b["runs"])) for b in blocks})


def bootstrap_ratio(first, second):
    rng = random.Random(1729)
    first_means = [list(map(mean, block["runs"])) for block in first]
    second_means = [list(map(mean, block["runs"])) for block in second]
    def sample(block_means):
        sampled = []
        for means in block_means:
            sampled.extend(rng.choices(means, k=len(means)))
        return mean(sampled)
    ratios = sorted(sample(first_means) / sample(second_means) for _ in range(5000))
    return [ratios[125], ratios[4874]]


def compare(first, second, partial):
    first_stats, second_stats = describe(first), describe(second)
    block_ratios = {block: value / second_stats["block_means"][block]
                    for block, value in first_stats["block_means"].items()
                    if block in second_stats["block_means"]}
    interval = None if partial else bootstrap_ratio(first, second)
    verdict = "incomplete"
    if interval:
        verdict = "overlap/inconsistent"
        if interval[1] < 1 and all(v < 1 for v in block_ratios.values()):
            verdict = "faster"
        elif interval[0] > 1 and all(v > 1 for v in block_ratios.values()):
            verdict = "slower"
    return dict(ratio=first_stats["mean_seconds"] / second_stats["mean_seconds"],
                bootstrap_95=interval, block_ratios=block_ratios, verdict=verdict)


def collect(directory, partial):
    settings = read_json(directory / "schedule.json")
    cases = {c["name"]: c for c in read_json(directory / "corpus/manifest.json")}
    build = read_json(directory / "build.json")
    for path, expected_hash in build["hashes"].items():
        if digest(path) != expected_hash:
            raise ValueError(f"Build/harness changed after measurement: {path}")
    if digest(build["treelite_library"]) != build["treelite_library_sha256"]:
        raise ValueError("Treelite library changed after measurement")
    for case in cases.values():
        if digest(case["path"]) != case["sha256"]:
            raise ValueError(f"Corpus changed: {case['name']}")
    expected = dict(build_sha256=digest(directory / "build.json"),
                    corpus_sha256=digest(directory / "corpus/manifest.json"),
                    main_commit=build["revisions"]["main"],
                    packed_commit=build["revisions"]["packed"])
    groups, warnings = defaultdict(lambda: defaultdict(list)), {}
    jobs = settings["schedule"]
    if not partial and (len(jobs) != 432 or not all(j.get("complete") for j in jobs)):
        raise ValueError("Full analysis requires all 432 completed cells")
    for job in jobs:
        if not job.get("complete"):
            continue
        case_metadata = {k: cases[job["case"]][k] for k in ("bytes", "nodes", "trees", "sha256", "dtype")}
        runs, notes = load_cell(directory, job, {**expected, **case_metadata})
        key = job["section"], job["case"], job["operation"]
        groups[key][job["engine"]].append(dict(block=job["block"], runs=runs))
        if notes:
            warnings[stem(job)] = notes
    return groups, warnings, settings, cases


def summarize(groups, partial):
    rows = []
    for (section, case, operation), engines in sorted(groups.items()):
        if not partial and any(len(blocks) != 2 or {b["block"] for b in blocks} != {0, 1}
                               for blocks in engines.values()):
            raise ValueError("Missing reversed-order block")
        expected_count = 2 if section == "default" else 8 if operation == "decode" else 5
        if not partial and len(engines) != expected_count:
            raise ValueError("Missing engine arm")
        comparisons = {}
        for reference in ("treelite-native", "treelite-python", "balsa-on", "balsa-off"):
            if reference in engines:
                comparisons[reference] = {
                    engine: compare(blocks, engines[reference], partial)
                    for engine, blocks in engines.items() if engine != reference}
        rows.append(dict(section=section, case=case, operation=operation,
                         engines={e: describe(b) for e, b in engines.items()},
                         comparisons=comparisons))
    return rows


def table(rows, operation, engines, section="serial"):
    lines = ["| Case | " + " | ".join(engines) + " |",
             "|---|" + "---:|" * len(engines)]
    for row in rows:
        if row["operation"] != operation or row["section"] != section:
            continue
        values = [f"{row['engines'][e]['mean_seconds'] * 1e6:.3f}" if e in row["engines"] else "—"
                  for e in engines]
        lines.append(f"| {row['case']} | " + " | ".join(values) + " |")
    return lines


def directional_table(rows):
    counts = defaultdict(lambda: defaultdict(int))
    synthetic = {"leaves", "uneven", "few-large", "dominant"}
    for row in rows:
        if row["section"] != "serial":
            continue
        corpus = "synthetic shapes (4)" if row["case"] in synthetic else "framework/scaled (12)"
        for engine, result in row["comparisons"].get("treelite-native", {}).items():
            counts[corpus, row["operation"], engine][result["verdict"]] += 1
    lines = ["## Directional summary versus native Treelite", "",
             "Counts require an interval excluding one and agreement in both run orders.",
             "Packed-copy remains a different operation contract; do not combine it with editable encode.", "",
             "| Corpus | Operation | Engine | Faster | Slower | Overlap/inconsistent | Incomplete |",
             "|---|---|---|---:|---:|---:|---:|"]
    for (corpus, operation, engine), values in sorted(counts.items()):
        numbers = " | ".join(str(values[v]) for v in ("faster", "slower", "overlap/inconsistent", "incomplete"))
        lines.append(f"| {corpus} | {operation} | {engine} | {numbers} |")
    return lines


def markdown(rows, quality, cases):
    lines = ["# Controlled codec results", "", "All times are microseconds per call (µs); lower is better.", "",
             "## Corpus", "", "| Case | Dtype | Trees | Nodes | Bytes |", "|---|---|---:|---:|---:|"]
    for case in cases.values():
        lines.append("| " + " | ".join(str(case[k]) for k in ("name", "dtype", "trees", "nodes", "bytes")) + " |")
    lines += [""] + directional_table(rows)
    for operation, engines in (
        ("decode", ["treelite-native", "treelite-python", "balsa-on", "balsa-off", "balsa-borrow-on", "balsa-borrow-off"]),
        ("encode", ["treelite-native", "treelite-python", "balsa-on", "balsa-off"]),
        ("decode", ["treelite-native", "balsa-on", "packed-on", "balsa-off", "packed-off"]),
        ("encode", ["treelite-native", "balsa-off", "packed-copy"]),
    ):
        lines += ["", f"## {operation.title()}: {', '.join(engines)}", ""]
        lines += table(rows, operation, engines)
    lines += ["", "Packed-copy copies an already serialized checkpoint; it is not serialization of an editable model.",
              "", "## Default four-worker policy (four available cores)", ""]
    for operation in ("decode", "encode"):
        lines += ["", f"### {operation.title()}", ""] + table(rows, operation, ["treelite-native", "balsa-default"], "default")
    lines += ["", "## Ratios against native Treelite", "",
              "Ratio = engine time / native time. Below 1 is faster. Intervals resample process-group means",
              "within each order block (5,000 bootstrap draws). Blocks and all samples are retained.",
              "These are descriptive intervals, not a multiple-comparison-corrected significance test.", "",
              "| Section | Case | Operation | Engine | Ratio | 95% interval | Block 0 / 1 | Assessment |",
              "|---|---|---|---|---:|---|---|---|"]
    for row in rows:
        for engine, result in row["comparisons"].get("treelite-native", {}).items():
            interval = result["bootstrap_95"]
            ci = f"{interval[0]:.3f}–{interval[1]:.3f}" if interval else "pending"
            blocks = " / ".join(f"{v:.3f}" for _, v in sorted(result["block_ratios"].items()))
            lines.append(f"| {row['section']} | {row['case']} | {row['operation']} | {engine} | "
                         f"{result['ratio']:.3f} | {ci} | {blocks} | {result['verdict']} |")
    lines += ["", "## Measurement quality", "",
              f"Completed cells: {quality['completed_cells']}; measured batches: {quality['measured_batches']}; "
              f"cells with pyperf warnings: {len(quality['warnings'])}.", "",
              "Per-engine CV, batch median/p95, and block means are in summary.json. The p95 is a percentile",
              "of batch-average times, not individual request latency. Warnings are retained in quality.json",
              "and original logs; no noisy samples were removed.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--partial", action="store_true")
    args = parser.parse_args()
    groups, warnings, settings, cases = collect(args.directory, args.partial)
    rows = summarize(groups, args.partial)
    quality = dict(completed_cells=sum(bool(j.get("complete")) for j in settings["schedule"]),
                   measured_batches=sum(v["values"] for row in rows for v in row["engines"].values()),
                   warnings=warnings, partial=args.partial)
    prefix = "partial-" if args.partial else ""
    write_json(args.directory / f"{prefix}summary.json", rows)
    write_json(args.directory / f"{prefix}quality.json", quality)
    (args.directory / f"{prefix}tables.md").write_text(markdown(rows, quality, cases))
    print(f"Audited {quality['completed_cells']} cells / {quality['measured_batches']} measured batches")


if __name__ == "__main__":
    main()
