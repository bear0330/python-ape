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

## Use

```sh
./results/bin/python.com -V
./results/bin/python.com -c 'print("hello")'
./results/bin/python.com -m http.server --bind 127.0.0.1 8000
```

The standard library is packed inside the executable. Imports are resolved
from `/zip`.

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
