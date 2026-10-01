#!/bin/sh
set -eu
PYTHON=${1:-${RESULTS:+$RESULTS/bin/python.com}}
PYTHON=${PYTHON:-./results/bin/python.com}
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
test -x "$PYTHON" || { echo "missing python APE: $PYTHON" >&2; exit 1; }

echo "==> $PYTHON -V"
"$PYTHON" -V
echo "==> socket smoke"
"$PYTHON" "$ROOT/smoke.py"
