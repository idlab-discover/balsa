#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
for source in tests/compile_fail/*.mojo; do
    name=$(basename "$source" .mojo)
    if mojo build -I src "$source" -o "build/$name" > "build/$name.log" 2>&1; then
        echo "Expected ownership check to reject $source" >&2
        exit 1
    fi
    # Failures must come from the intended ownership/mutation rule.
    case "$name" in
        packed_escape) pattern='origin|outlive|lifetime' ;;
        packed_mutate) pattern='__setitem__|mutable|mutation|subscript' ;;
        *) exit 1 ;;
    esac
    if ! grep -Eiq "$pattern" "build/$name.log"; then
        cat "build/$name.log" >&2
        exit 1
    fi
    echo "PASS: rejected $source for the expected ownership rule"
done
