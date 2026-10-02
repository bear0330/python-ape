#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
    echo "Usage: $0 [superconfigure-directory] [sdk-directory]" >&2
    echo "superconfigure-directory defaults to ./superconfigure." >&2
    echo "sdk-directory defaults to ./sdk." >&2
    exit 2
}

absolute_dir() {
    CDPATH= cd -- "$1" && pwd || exit 1
}

copy_arch() {
    arch=$1
    build=$superconfigure/o/lang/python/build/$arch
    lib=$dest/$arch/lib

    mkdir -p "$lib"
    cp -a "$build/libpython3.12.a" "$lib/libpython3.12.a"
    cp -a "$build/Modules/_decimal/libmpdec/libmpdec.a" "$lib/libmpdec.a"
    cp -a "$build/Modules/_hacl/libHacl_Hash_SHA2.a" "$lib/libHacl_Hash_SHA2.a"
    cp -a "$build/pyconfig.h" "$dest/$arch/pyconfig.h"

    for name in \
        ssl \
        crypto \
        expat \
        gdbm \
        readline \
        tinfo \
        panelw \
        ncursesw \
        tinfow \
        sqlite3 \
        uuid \
        bz2 \
        z
    do
        cp -a "$superconfigure/cosmos/$arch/lib/lib${name}.a" "$lib/lib${name}.a"
    done
}

prefix_of() {
    sed -n 's/^prefix=[[:space:]]*//p' \
        "$superconfigure/o/lang/python/build/$1/Makefile" | head -n 1
}

if [ "$#" -gt 2 ]; then
    usage
fi

if [ "$#" -ge 1 ]; then
    superconfigure=$(absolute_dir "$1")
elif [ -d "$root/superconfigure" ]; then
    superconfigure=$(absolute_dir "$root/superconfigure")
else
    echo "missing $root/superconfigure" >&2
    echo "Run install-overlay.sh, or pass the superconfigure directory." >&2
    exit 1
fi

if [ "$#" -ge 2 ]; then
    dest=$(absolute_dir "$2")
else
    dest=$root/sdk
fi

cosmocc=$superconfigure/cosmopolitan/cosmocc/bin

mkdir -p "$dest"
rm -rf "$dest/include" "$dest/x86_64" "$dest/aarch64"
cp -a "$superconfigure/o/lang/python/cpython-3.12.3/Include" "$dest/include"
cp -a "$superconfigure/results/bin/python.com" "$dest/python.com"
chmod +x "$dest/python.com"

copy_arch x86_64
copy_arch aarch64

DEST="$dest" COSMOCC="$cosmocc" python3 - <<'PY'
import os
import subprocess
from pathlib import Path

dest = Path(os.environ["DEST"])
cosmocc = Path(os.environ["COSMOCC"])
order = [
    "python3.12",
    "Hacl_Hash_SHA2",
    "mpdec",
    "ssl",
    "crypto",
    "expat",
    "gdbm",
    "readline",
    "tinfo",
    "panelw",
    "ncursesw",
    "tinfow",
    "sqlite3",
    "uuid",
    "bz2",
    "z",
]

for arch in ("x86_64", "aarch64"):
    ar = cosmocc / f"{arch}-linux-cosmo-ar"
    lib = dest / arch / "lib"
    work = dest / arch / ".members"
    work.mkdir()
    members = []

    for index, name in enumerate(order):
        sub = work / f"{index:02d}"
        sub.mkdir()
        subprocess.run(
            ["/bin/sh", str(ar), "x", str(lib / f"lib{name}.a")],
            cwd=sub,
            check=True,
        )

        for obj in sorted(sub.iterdir()):
            renamed = sub / f"l{index:02d}_{obj.name}"
            obj.rename(renamed)
            members.append(renamed)

    runtime = dest / arch / "libpython-runtime.a"

    # Member names collide across ssl, ncurses, and terminfo, so each object
    # is prefixed. One archive is enough for the linker to resolve cycles.
    subprocess.run(
        ["/bin/sh", str(ar), "rcs", str(runtime), *map(str, members)],
        check=True,
    )

    for path in sorted(work.rglob("*"), reverse=True):
        if path.is_file():
            path.unlink()
        elif path.is_dir():
            path.rmdir()

    work.rmdir()

    for archive in lib.glob("*.a"):
        archive.unlink()

    lib.rmdir()
    print(runtime)
PY

prefix_x86_64=$(prefix_of x86_64)
prefix_aarch64=$(prefix_of aarch64)

# prefixes are the cosmos paths compiled into the archives. A later relink
# rewrites those strings to /zip. cosmocc, apelink, and ape.elf are not
# recorded: the user passes the superconfigure checkout that contains them.
DEST="$dest" \
PREFIX_X86_64="$prefix_x86_64" \
PREFIX_AARCH64="$prefix_aarch64" \
python3 - <<'PY'
import json
import os
from pathlib import Path

dest = Path(os.environ["DEST"])
spec = {
    "prefixes": {
        "x86_64": os.environ["PREFIX_X86_64"],
        "aarch64": os.environ["PREFIX_AARCH64"],
    },
    "include": "include",
    "pyconfig_dir": {
        "x86_64": "x86_64",
        "aarch64": "aarch64",
    },
    "runtime": {
        "x86_64": "x86_64/libpython-runtime.a",
        "aarch64": "aarch64/libpython-runtime.a",
    },
    "python_com": "python.com",
}
(dest / "link.json").write_text(json.dumps(spec, indent=2) + "\n")
PY

echo "sdk: $dest"
