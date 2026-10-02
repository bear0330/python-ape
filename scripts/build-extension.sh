#!/bin/sh
# Build one python-ape C extension.
#
# An extension with BUILD.mk is a superconfigure DOWNLOAD_SOURCE package.
# This script links that directory into the checkout only while make runs,
# then removes the link. An extension without BUILD.mk is compiled from
# the sources and defines listed in extension.json.
set -eu

project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
    echo "$1" >&2
    exit 1
}

usage() {
    echo "Usage: $0 extension [sdk-directory] [superconfigure-directory]" >&2
    echo "extension is a name under extensions/, or a directory." >&2
    echo "sdk-directory defaults to ./sdk." >&2
    echo "superconfigure-directory defaults to ./superconfigure." >&2
    exit 2
}

absolute_dir() {
    CDPATH= cd -- "$1" && pwd || exit 1
}

resolve_extension() {
    name=$1

    if [ "$(basename -- "$name")" = "$name" ] && [ -d "$project/extensions/$name" ]; then
        absolute_dir "$project/extensions/$name"
        return
    fi

    if [ -d "$name" ]; then
        absolute_dir "$name"
        return
    fi

    fail "no extension '$name' under $project/extensions"
}

resolve_sdk() {
    requested=$1

    if [ -n "$requested" ]; then
        absolute_dir "$requested"
        return
    fi

    if [ -d "$project/sdk" ]; then
        absolute_dir "$project/sdk"
        return
    fi

    echo "missing $project/sdk" >&2
    echo "Package the SDK into ./sdk, or pass the SDK directory." >&2
    exit 1
}

resolve_superconfigure() {
    sdk=$1
    requested=$2
    parent=$(absolute_dir "$sdk/..")

    if [ -n "$requested" ]; then
        absolute_dir "$requested"
        return
    fi

    if [ -d "$parent/superconfigure" ]; then
        absolute_dir "$parent/superconfigure"
        return
    fi

    if [ -d "$parent/cosmopolitan" ]; then
        printf '%s\n' "$parent"
        return
    fi

    echo "missing superconfigure checkout beside the SDK." >&2
    echo "Run install-overlay.sh so superconfigure/ exists next to the SDK, or pass the superconfigure directory." >&2
    exit 1
}

require_cosmocc() {
    superconfigure=$1

    if [ -d "$superconfigure/cosmopolitan/cosmocc/bin" ]; then
        return
    fi

    echo "$superconfigure has no cosmopolitan/cosmocc/bin." >&2
    echo "Run .github/scripts/setup and .github/scripts/cosmo in that checkout." >&2
    exit 1
}

build_with_make() {
    extension=$1
    sdk=$2
    superconfigure=$3
    name=$(basename -- "$extension")
    link=$superconfigure/extensions/$name

    if [ -e "$link" ] && [ ! -L "$link" ]; then
        fail "refusing to replace $link"
    fi

    tmp=$(mktemp)
    cleanup() {
        rm -f "$link" "$tmp"
        rmdir "$superconfigure/extensions" 2>/dev/null || true
    }
    trap cleanup EXIT

    mkdir -p "$superconfigure/extensions"
    ln -sfn "$extension" "$link"

    # o/%/downloaded depends on the package directory. The recipe writes
    # native/ and python/ there, so that directory is newer than the stamp
    # and the next make would download the tarball again.
    stamp=$superconfigure/o/extensions/$name/downloaded

    if [ -f "$stamp" ]; then
        touch -r "$stamp" "$extension"
    fi

    printf '.NOTPARALLEL:\ninclude extensions/%s/BUILD.mk\n' "$name" >"$tmp"

    make -C "$superconfigure" \
        -f Makefile \
        -f "$tmp" \
        LOG=stdout \
        SDK="$sdk" \
        EXT="$extension" \
        "o/extensions/$name/built.x86_64" \
        "o/extensions/$name/built.aarch64"
}

compile_from_json() {
    extension=$1
    sdk=$2
    superconfigure=$3

    python3 - "$extension" "$sdk" "$superconfigure" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

extension = Path(sys.argv[1])
sdk = Path(sys.argv[2])
superconfigure = Path(sys.argv[3])
spec_path = extension / "extension.json"

if not spec_path.is_file():
    raise SystemExit(f"missing {spec_path}")

spec = json.loads(spec_path.read_text())
sources = spec.get("sources") or []

if not sources:
    raise SystemExit(
        f"{spec_path} needs a sources list, or the extension needs a BUILD.mk"
    )

defines = spec.get("defines") or []
archives = spec.get("archives") or {}
link = json.loads((sdk / "link.json").read_text())
bindir = superconfigure / "cosmopolitan" / "cosmocc" / "bin"
include = sdk / link["include"]

for arch in ("x86_64", "aarch64"):
    cc = bindir / f"{arch}-unknown-cosmo-cc"
    ar = bindir / f"{arch}-linux-cosmo-ar"

    if not cc.is_file() or not ar.is_file():
        raise SystemExit(
            f"cosmocc in {superconfigure} is incomplete.\n"
            "Run .github/scripts/setup and .github/scripts/cosmo in that checkout.\n"
            f"{cc}\n{ar}"
        )

    relative = archives.get(arch)

    if not relative:
        raise SystemExit(f"{spec_path} has no archives.{arch}")

    archive = extension / relative
    archive.parent.mkdir(parents=True, exist_ok=True)
    objects = []

    for name in sources:
        source = extension / name

        if not source.is_file():
            raise SystemExit(f"missing source {source}")

        obj = archive.parent / (source.stem + ".o")
        subprocess.run(
            [
                str(cc),
                "-c",
                "-Os",
                *[f"-D{item}" for item in defines],
                "-I",
                str(sdk / link["pyconfig_dir"][arch]),
                "-I",
                str(include),
                "-o",
                str(obj),
                str(source),
            ],
            check=True,
        )
        objects.append(str(obj))

    archive.unlink(missing_ok=True)
    subprocess.run(
        ["/bin/sh", str(ar), "rcs", str(archive), *objects],
        check=True,
    )
    print(archive)
PY
}

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
    usage
fi

extension=$(resolve_extension "$1")

sdk_arg=
if [ "$#" -ge 2 ]; then
    sdk_arg=$2
fi
sdk=$(resolve_sdk "$sdk_arg")

super_arg=
if [ "$#" -ge 3 ]; then
    super_arg=$3
fi
superconfigure=$(resolve_superconfigure "$sdk" "$super_arg")

require_cosmocc "$superconfigure"

if [ -f "$extension/BUILD.mk" ]; then
    build_with_make "$extension" "$sdk" "$superconfigure"
    exit 0
fi

compile_from_json "$extension" "$sdk" "$superconfigure"
