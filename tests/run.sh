#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0
for t in tests/test_*.lua; do
  echo "RUN $t"
  if ! nvim --headless -u tests/minimal_init.lua -c "luafile $t" -c qa 2>&1; then
    fail=1
  fi
done
exit "$fail"
