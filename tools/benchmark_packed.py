"""Compare packed and editable storage in shuffled CPU-pinned subprocess blocks."""

import hashlib
import json
import random
import statistics

from benchmark_reuse import ROOT, run

OUT = ROOT / "benchmarking" / "packed"


def measure(case, operation, enabled, loops):
    return float(run(["taskset", "-c", "14", str(OUT / "worker"),
                      case["path"], operation, str(int(enabled)), str(loops)]))


def main():
    OUT.mkdir(exist_ok=True)
    run(["pixi", "run", "mojo", "build", "-O3", "-I", "src",
         "tools/packed_worker.mojo", "-o", str(OUT / "worker")])
    provenance = dict(
        parent=run(["git", "rev-parse", "HEAD"]).strip(),
        compiler=run(["pixi", "run", "mojo", "--version"]).strip(),
        source_sha256={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in (ROOT / "src/balsa").glob("*.mojo")},
        cpu=14, blocks=5, warmups=8,
    )
    (OUT / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    cases = json.loads((ROOT / "benchmarking/validation-opt-out/corpus/manifest.json").read_text())
    for shape in ("leaves", "uneven", "few-large", "dominant"):
        path = ROOT / "build/threading" / f"{shape}.tl"
        if path.exists():
            cases.append(dict(name=shape, path=str(path)))
    configurations = [(op, enabled) for op in ("decode", "borrowed", "packed-decode")
                      for enabled in (False, True)]
    configurations += [("encode", False), ("packed-encode", False)]
    jobs = []
    for case in cases:
        for operation, enabled in configurations:
            estimate = measure(case, operation, enabled, 2)
            loops = max(100, min(4000, int(100_000_000 / estimate)))
            jobs.extend((block, case, operation, enabled, loops) for block in range(5))
    random.Random(15094).shuffle(jobs)
    records = []
    for index, (block, case, operation, enabled, loops) in enumerate(jobs):
        records.append(dict(block=block, case=case["name"], operation=operation,
                            validation=enabled, loops=loops,
                            ns=measure(case, operation, enabled, loops)))
        if index % 40 == 0:
            print(f"{index}/{len(jobs)} batches", flush=True)
    (OUT / "timings.json").write_text(json.dumps(records, indent=2) + "\n")
    summary = []
    for case in cases:
        for operation, enabled in configurations:
            ns = statistics.median(r["ns"] for r in records
                if r["case"] == case["name"] and r["validation"] == enabled
                and r["operation"] == operation)
            summary.append(dict(case=case["name"], operation=operation,
                                validation=enabled, ns=ns))
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    for row in summary:
        if row["case"].endswith("x1667") or row["case"] in ("dominant", "few-large"):
            print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main()
