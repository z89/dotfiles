#!/usr/bin/env bash
# Run all carry regressions without contacting the compositor.
set -euo pipefail
carry_test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for suite in "$carry_test_dir"/test_*.lua; do
    lua5.5 "$suite"
done
