#!/bin/sh
# Runs the Python APE socket checks against an installed superconfigure tree.
set -eu

[ "$#" -le 1 ] || { echo "Usage: $0 [superconfigure-directory]" >&2; exit 2; }
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SUPER=${1:-$ROOT/superconfigure}
SUPER=$(CDPATH= cd -- "$SUPER" && pwd)
"$ROOT/tests/python/validate.sh" "$SUPER/results/bin/python.com"
