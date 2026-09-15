"""One pyperf engine/case/operation cell, measuring internal codec batch time."""

from pathlib import Path
import pyperf
from common import ENGINES, digest, read_json, measure


def forward(command, args):
    command.extend(["--directory", args.directory, "--engine", args.engine,
                    "--case", args.case, "--operation", args.operation])


runner = pyperf.Runner(add_cmdline_args=forward)
runner.argparser.add_argument("--directory", required=True)
runner.argparser.add_argument("--engine", choices=ENGINES, required=True)
runner.argparser.add_argument("--case", required=True)
runner.argparser.add_argument("--operation", choices=("decode", "encode"), required=True)
args = runner.parse_args()
directory = Path(args.directory)
build = read_json(directory / "build.json")
case = next(c for c in read_json(directory / "corpus/manifest.json") if c["name"] == args.case)
if digest(case["path"]) != case["sha256"]:
    raise ValueError("Corpus hash mismatch")
if args.track_memory or args.tracemalloc:
    raise ValueError("Memory tracking would measure the orchestrator, not the codec worker")
runner.metadata.update(
    engine=args.engine, contract=ENGINES[args.engine],
    measurement="internal codec batch; resident input; output destruction included; eight warmup calls",
    build_sha256=digest(directory / "build.json"),
    corpus_sha256=digest(directory / "corpus/manifest.json"),
    harness_revision="final-codec-pyperf-v1", treelite_version=build["treelite_version"],
    main_commit=build["revisions"]["main"], packed_commit=build["revisions"]["packed"],
    compiler=build["compiler"], limits="Balsa max_bytes=536870912, max_nodes=4000000, other defaults",
    validation=("load-time only" if args.engine == "packed-copy" else
                "disabled" if args.engine.endswith("off") else
                "normal Treelite API checks" if args.engine.startswith("treelite") else "enabled"),
)
runner.bench_time_func(f"{args.case}/{args.operation}", measure, args.directory,
                      args.engine, case, args.operation,
                      metadata={k: case[k] for k in ("bytes", "nodes", "trees", "sha256", "dtype")})
