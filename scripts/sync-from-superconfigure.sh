#!/bin/sh
# Copies the two Python overlay files and the runtime tests out of a
# superconfigure checkout.  The rest of lang/python stays upstream.
set -eu

usage() {
  echo "Usage: $0 [--force] /path/to/superconfigure" >&2
  exit 2
}

FORCE=false
case "${1:-}" in
  --force) FORCE=true; shift ;;
esac
[ "$#" -eq 1 ] || usage

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE=$(CDPATH= cd -- "$1" && pwd)
for path in lang/python/minimal.diff lang/python/sitecustomize.py tests/python/validate.sh; do
  [ -e "$SOURCE/$path" ] || {
    echo "missing required source path: $SOURCE/$path" >&2
    exit 1
  }
done

if [ "$FORCE" != true ] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for path in lang/python/minimal.diff lang/python/sitecustomize.py tests/python; do
    if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all -- "$path")" ]; then
      echo "refusing to overwrite modified $path; commit/stash it or rerun with --force" >&2
      exit 1
    fi
  done
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/python-ape-sync-stage.XXXXXX")
BACKUP=$(mktemp -d "${TMPDIR:-/tmp}/python-ape-sync-backup.XXXXXX")
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT HUP INT TERM

mkdir -p "$STAGE/lang/python" "$STAGE/tests"
cp -p "$SOURCE/lang/python/minimal.diff" "$STAGE/lang/python/minimal.diff"
cp -p "$SOURCE/lang/python/sitecustomize.py" "$STAGE/lang/python/sitecustomize.py"
cp -pR "$SOURCE/tests/python" "$STAGE/tests/python"
find "$STAGE" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
find "$STAGE" -type d -name __pycache__ -empty -delete

sync_path() {
  relative=$1
  destination=$ROOT/$relative
  staged=$STAGE/$relative
  backup=$BACKUP/$relative
  mkdir -p "$(dirname "$destination")" "$(dirname "$backup")"
  if [ -e "$destination" ]; then mv "$destination" "$backup"; fi
  mv "$staged" "$destination"
}

sync_path lang/python/minimal.diff
sync_path lang/python/sitecustomize.py
sync_path tests/python

echo "Synchronized from $SOURCE"
echo "Replaced files are backed up at $BACKUP"
