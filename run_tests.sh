#!/usr/bin/env bash
# Run every test suite. Requires the venv (uv venv && uv pip install mojo tinydb).
set -euo pipefail
cd "$(dirname "$0")"
source .venv/bin/activate
for t in tests/test_*.mojo; do
  echo "== $t"
  mojo run -I src "$t" 2>&1 | grep -v -e HSA -e doorbell -e '^$'
done
