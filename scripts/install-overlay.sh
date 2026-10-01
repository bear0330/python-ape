#!/bin/sh
set -eu

[ "$#" -le 1 ] || { echo "Usage: $0 [superconfigure-directory]" >&2; exit 2; }
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
value() { sed -n "s/^$1=//p" "$ROOT/superconfigure.lock"; }
REPOSITORY=$(value superconfigure_repository)
REF=$(value superconfigure_ref)
EXPECTED=$(value superconfigure_commit)
if [ "$#" -eq 0 ]; then
  SUPER=$ROOT/superconfigure
  if [ ! -e "$SUPER" ]; then git clone --depth 1 --branch "$REF" "$REPOSITORY" "$SUPER"; fi
else
  SUPER=$1
fi
SUPER=$(CDPATH= cd -- "$SUPER" && pwd)
ACTUAL=$(git -C "$SUPER" rev-parse HEAD 2>/dev/null || true)
[ "$ACTUAL" = "$EXPECTED" ] || { echo "expected superconfigure $EXPECTED, got ${ACTUAL:-not-a-matching-git-checkout}" >&2; exit 1; }
# Do not provision Cosmopolitan here.  The base project's setup and cosmo
# scripts clone its current source and generate the matching cosmocc tree.
# z0.0.66 already contains lang/python.  Only the two files below differ.
DESTINATION=$SUPER/lang/python
[ -d "$DESTINATION" ] || { echo "missing stock recipe: $DESTINATION" >&2; exit 1; }
mkdir -p "$SUPER/.ape-overlay-backups"
BACKUPS=$(mktemp -d "$SUPER/.ape-overlay-backups/python-ape.XXXXXX")
mkdir -p "$BACKUPS/lang/python"
for file in minimal.diff sitecustomize.py; do
  [ -f "$ROOT/lang/python/$file" ] || { echo "missing overlay file: $file" >&2; exit 1; }
  [ -f "$DESTINATION/$file" ] || { echo "missing stock file: $DESTINATION/$file" >&2; exit 1; }
  cp -p "$DESTINATION/$file" "$BACKUPS/lang/python/$file"
  cp -p "$ROOT/lang/python/$file" "$DESTINATION/$file"
done
printf 'Installed Python overlay into %s. Backup: %s\n' "$SUPER" "$BACKUPS"
