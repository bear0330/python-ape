# Python for Cosmopolitan APE

This project builds CPython 3.12.3 as a fat, portable `python.com`. The
executable contains x86_64 and aarch64 launchers and runs on the platforms
supported by [Cosmopolitan](https://github.com/jart/cosmopolitan) APE, without
a separate Python installation.

The repository is the `lang/python` overlay for
[superconfigure](https://github.com/ahgamut/superconfigure) `z0.0.66`.
Superconfigure supplies the build framework and the Cosmopolitan toolchain.
This project supplies `lang/python/minimal.diff`, `lang/python/sitecustomize.py`,
and the runtime tests.

## Install

[`superconfigure.lock`](superconfigure.lock) pins superconfigure `z0.0.66`
(`29009f53a141be8113e7f5729a0a007f1081df58`). With no argument, the installer
clones that revision to `./superconfigure/` and installs
`lang/python/minimal.diff` and `lang/python/sitecustomize.py`:

```sh
./scripts/install-overlay.sh
```

To use an existing checkout of that exact commit:

```sh
./scripts/install-overlay.sh /path/to/superconfigure
```

The installer checks the revision. Replaced files are kept under
`.ape-overlay-backups/`.

## Build

On WSL, clone into the Linux filesystem (for example `~/src`), not a
`/mnt/c` or `/mnt/d` Windows mount: Cosmocc launches nested APE programs that
DrvFs cannot run reliably. Then run `ulimit -s unlimited`; Cosmopolitan's
build needs an unlimited shell stack.

```sh
cd /path/to/superconfigure
bash ./.github/scripts/setup
bash ./.github/scripts/cosmo
MAXPROC=4 bash ./.github/scripts/collectbuild lang/python
```

`setup` clones Cosmopolitan at the revision recorded by superconfigure, and
`cosmo` builds the matching `cosmocc` toolchain. The Python recipe downloads
and checksum-verifies CPython 3.12.3.

The build writes:

```text
results/bin/python.com
```

A finished build can also be packed as a link SDK. `python.com` stays the
runtime for pure-Python programs. `package-sdk.sh` joins `libpython` with
ssl, crypto, sqlite, ncurses, and the other libraries it was linked against
into one `libpython-runtime.a` per architecture. Linking an application then
adds only that archive and the extension `.a` files.

`sdk/link.json` records the cosmos prefix compiled into those archives, plus
paths inside the SDK. It does not record `cosmocc`. Extension builds and
relinks take the superconfigure checkout, the same way `install-overlay.sh`
does: pass the directory, or rely on `superconfigure/` beside the SDK after
`./scripts/install-overlay.sh`. That checkout has to contain `cosmopolitan/`
(`setup` and `cosmo` produce it).

```sh
./scripts/package-sdk.sh
./scripts/build-extension.sh markupsafe
./scripts/build-extension.sh crc32c
```

[`scripts/build-extension.sh`](scripts/build-extension.sh) builds every C
extension. An extension name resolves under `extensions/`. The SDK defaults
to `./sdk` and the checkout defaults to `./superconfigure`. Pass either
path when it lives somewhere else.

`extensions/markupsafe` is the usual third-party package. Its
[`BUILD.mk`](extensions/markupsafe/BUILD.mk) calls superconfigure's
`DOWNLOAD_SOURCE`. The shared script links the extension into that checkout
for the duration of `make`, and the stock rules download the MarkupSafe
3.0.3 tarball, check
[`check.signature`](extensions/markupsafe/check.signature), extract it, and
apply [`minimal.diff`](extensions/markupsafe/minimal.diff) with `patch -p0`.
The diff renames the C module to the builtin `_markupsafe__speedups` and
points the Python import at that name. The build then splits the tree into
two parts. `native/` is the C file compiled for x86_64 and aarch64.
`python/markupsafe` is the package packed into `Lib/site-packages`.
`tests/try.py` is a unittest for that builtin. MarkupSafe itself is
BSD-3-Clause and is downloaded at build time.

`extensions/crc32c` is the same kind of package. The recipe downloads
crc32c 2.7.1, checks it, and applies `minimal.diff` so the package imports
the builtin `_crc32c`. `native/` holds the six C files compiled into
`lib_crc32c.a`. `python/crc32c` is the package packed into
`Lib/site-packages`. `tests/try.py` is a unittest for that builtin.
crc32c is LGPL-2.1-or-later and is downloaded at build time.

An extension without `BUILD.mk` is compiled from the `sources` and
`defines` listed in `extension.json`.

`package-sdk.sh` only copies archives and headers out of a build that has
already completed. With no arguments it reads `./superconfigure` and writes
`./sdk`. Pass the checkout when the build tree lives elsewhere, and a
second path when the SDK should be copied somewhere else.

## Use

```sh
./results/bin/python.com -V
./results/bin/python.com -c 'print("hello")'
./results/bin/python.com -m http.server --bind 127.0.0.1 8000
```

The standard library is packed inside the executable. Imports are resolved
from `/zip`.

## Example

[`examples/bore/Bore.py`](examples/bore/Bore.py) is a bore tunnel client
extracted from [FastFileLink (ffl)](https://github.com/nuwainfo/ffl). It
connects to a bore server, accepts incoming tunnel connections, and forwards
them to a local TCP service. That exercises `getsockname`, `localhost`
resolution, and ordinary TCP sockets. 

Start something on port 8000, then open the tunnel:

```sh
./results/bin/python.com -m http.server --bind 127.0.0.1 8000
./results/bin/python.com examples/bore/Bore.py 8000 -t bore.pub
```

The client prints a public endpoint such as `bore.pub:36168`. Pass `-s` or
set `BORE_SECRET` when the server requires authentication. `--use-https`
connects on port 443.

## Improvements

`python.com` from this overlay has the following socket behavior.

- `socket.getsockname()` is present. Cosmopolitan does not define
  `HAVE_GETSOCKNAME`, so the stock superconfigure build omits the method.
  On Windows, `EBADF` from `getsockname` still rejects a bad descriptor.
  On other hosts that error is ignored and socket construction continues.
- `localhost` resolves to `127.0.0.1`, or to `::1` for IPv6. When the system
  resolver fails for another name, lookup continues over DNS-over-UDP
  (`1.1.1.1`, `8.8.8.8`) and DNS-over-HTTPS.
- `socket.socketpair()` uses a `127.0.0.1` TCP pair when the host
  `socketpair` fails. `asyncio` uses that pair.

## Test

After `collectbuild lang/python`:

```sh
./scripts/test-overlay.sh /path/to/superconfigure
```

[`tests/python/smoke.py`](tests/python/smoke.py) checks `getsockname`,
`localhost`, `socketpair`, and a loopback TCP exchange.

## License

This project is licensed under the [MIT License](LICENSE).
CPython remains under the PSF License. superconfigure and Cosmopolitan
remain under their own licenses.
