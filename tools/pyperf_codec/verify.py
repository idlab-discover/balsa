"""Record final acceptance checks after (never during) codec measurement."""

import argparse
from pathlib import Path
import subprocess
import time

from common import ROOT, digest, read_json, write_json


def check(directory, name, command, expect_failure=False):
    started = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    output = result.stdout + result.stderr
    (directory / f"{name}.log").write_text(output)
    passed = result.returncode != 0 if expect_failure else result.returncode == 0
    record = dict(name=name, command=command, returncode=result.returncode,
                  expected_failure=expect_failure, passed=passed,
                  wall_seconds=time.monotonic() - started)
    print(f"{'PASS' if passed else 'FAIL'}: {name}", flush=True)
    if not passed:
        print(output, flush=True)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    settings = read_json(args.directory / "schedule.json")
    if not settings.get("finished_utc"):
        raise ValueError("Finish timing before running acceptance checks")
    output = args.directory / "acceptance"
    output.mkdir(exist_ok=False)
    commands = [
        ("check", ["pixi", "run", "check"]),
        ("fixtures", ["pixi", "run", "-e", "oracle", "fixtures-check"]),
        ("interop", ["pixi", "run", "-e", "oracle", "python", "tools/interop.py"]),
        ("framework-interop", ["pixi", "run", "-e", "oracle", "python", "tools/framework_interop.py"]),
        ("docs", ["pixi", "run", "-e", "docs", "docs-check"]),
    ]
    records = [check(output, name, command) for name, command in commands]
    for name in ("packed_escape", "packed_mutate"):
        command = ["pixi", "run", "mojo", "build", "-I", "src",
                   f"tests/compile_fail/{name}.mojo", "-o", str(output / name)]
        records.append(check(output, name, command, expect_failure=True))
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    sources = list((ROOT / "src").rglob("*.mojo")) + list((ROOT / "tests").rglob("*.mojo"))
    write_json(output / "results.json", dict(revision=revision, checks=records,
               sources={str(p.relative_to(ROOT)): digest(p) for p in sources},
               note="Compile-fail diagnostics require manual confirmation of the expected cause."))
    if not all(record["passed"] for record in records):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
