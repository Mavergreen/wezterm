# Mavericks WezTerm

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut its first release.

WezTerm for Mavericks: current [WezTerm](https://github.com/wezterm/wezterm), the GPU-accelerated terminal emulator and multiplexer, built for Mac OS X 10.9.5 and later. It is an unofficial community build, not affiliated with or endorsed by the WezTerm project.

Each release is a snapshot of upstream's `main`, taken once a week, with the changes 10.9 needs carried as explained patches (see [PORT.md](PORT.md)). The version says which snapshot: `20261026.072628-mavericks.1` is upstream's commit of 2026-10-26 07:26:28 UTC, packaged for the first time. The product is x86_64 only. It renders with upstream's OpenGL renderer: Metal and WebGpu do not exist on 10.9, and selecting WebGpu fails with a message saying so.

## Installing

Download `wezterm-<version>.pkg` from this repository's Releases, check it against the release's `SHA256SUMS`, and open it, or run `sudo installer -pkg wezterm-<version>.pkg -target /`. It needs Mac OS X 10.9.5 or later. No release has been published yet.

The pkg installs:

- `/Applications/Mavericks WezTerm.app`, the terminal;
- `/usr/local/mavergreen/wezterm`, with the commands below and the product's manifest;
- the Sparkle updater, `/Library/Application Support/Mavergreen/wezterm-updater.app`, which checks this repository's feed and offers new releases. Upstream's own update check is off by default (`check_for_updates`), so the updater is the only one.

`mavergreen check` checks what is installed. `sudo mavergreen uninstall wezterm` removes it.

## The commands on PATH

`wezterm`, `wezterm-gui`, `wezterm-mux-server` and `strip-ansi-escapes` are in `/usr/local/mavergreen/bin`, which login shells put on `PATH` through `/etc/paths.d/mavergreen`. Configuration is upstream's: `~/.wezterm.lua` or `~/.config/wezterm/`.

Each command is a two-line sh wrapper that `exec`s the app's own `Contents/MacOS/<command>`, not a symlink. Upstream looks for `wezterm-gui` (for `wezterm start`) and `wezterm-mux-server` (when `wezterm cli` starts a server) beside the path `wezterm` was started by, without resolving symlinks. Through a symlink it looks in the link's own directory, and finds nothing unless every sibling has a link there too (a `wezterm` linked into `~/bin` alone cannot start the GUI). Through the wrapper, `wezterm` runs from the app's `Contents/MacOS`, so it always finds the app's own copies.

## Limits

- **The GUI is not exercised in CI.** The 10.9 guest that CI installs every candidate into has no logged-in Aqua session, so CI checks the commands, the multiplexer, TLS and SSH, but never opens a window. The GUI has been checked by hand on a real 10.9 Mac, and the first release is checked that way too. INGREDIENTS.md declares the gap (`on-target:gui`) and what ends it.
- See [PORT.md](PORT.md) for what each carried change does and does not cover.

## Building natively on 10.9

The build uses Mavergreen's own toolchain products, each at the release `components/<name>/version` pins: `rust`, `clang22` and `make`, plus shipyard (which provides `shipyard-cmake`). INGREDIENTS.md "Build tools" says how to install them; `sh build/tools.sh check` names any that are missing or at another release. Then:

```sh
sh build/prepare.sh
sh build/build-native.sh
```

`prepare.sh` fetches upstream's source and its submodules as tarballs, checks them against the pin, applies the patches and verifies every locked crate; no git is needed. Its output and the build's go to `${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/private/tmp}/mm-build}/<checkout name>-wezterm-local`, not into this checkout, and `build-native.sh` stages `stage/Mavericks WezTerm.app` there. A change under `build/`, `components/` or `patches/` needs `prepare.sh` again. Python 2.7 and Python 3 both work; `PYTHON` selects one.

To make a pkg from the staged app:

```sh
sh build/check-compat.sh
sh build/build-updater.sh --out /tmp/wezterm-updater.app
sh build/package-pkg.sh --app "<build root>/stage/Mavericks WezTerm.app" \
    --updater-app /tmp/wezterm-updater.app --version <version> --out dist
```

where `<version>` is the staged app's `CFBundleShortVersionString`.

## Cross-building on a modern Mac

CI builds on an Apple Silicon Mac. With the pinned `rust-cross`, `clang22-cross` and `make` installed, and Longboat's 10.9 SDK (`sudo longboat sdk install 10.9`):

```sh
sh build/prepare.sh
sh build/build-cross.sh
```

The same prepared source becomes the same x86_64 10.9 executables, compiled by `clang22-cross` against the 10.9 SDK. Build scripts and proc macros, which run during the build, are built for the host with `/usr/bin/clang`. Nothing x86_64 runs there, not even under Rosetta: the tests that run the shipped code stop at that point (exit 77) and run on 10.9 instead.

## Tests

Run the repository's tests with shipyard's runner, one at a time, since they share the build root:

```sh
. build/msc.sh
MAVERICKS_TEST_JOBS=1 sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"
```

A test that needs something this machine does not have (a build, the pinned products, an x86_64 CPU) exits 77, which the runner reports as skipped. On a 10.9 Mac after a native build, every test runs. `tests/upstream_suite.sh` runs upstream's own tests, all of them, natively.

The release check installs a pkg on 10.9 and checks the installed product without a GUI:

```sh
sh build/check-release-on-10.9.sh --repo-tests <version>
```

It installs `dist/wezterm-<version>.pkg` with `sudo installer` after checking it against `dist/SHA256SUMS`, then checks the manifest, every command, a multiplexer round trip, TLS and SSH domains, and with `--repo-tests` runs the suite above. It leaves WezTerm installed. CI runs it in a 10.9 virtual machine on every candidate. `tests/release_check.sh` runs it against a scratch volume instead, so no sudo is needed.

`sh build/check-local.sh --non-gui` checks the staged app. For the GUI, a person checks it on a 10.9 desktop: `sh build/stage-app.sh --acceptance` stages a private copy of the app, and `sh build/check-local.sh --gui` opens it with a private configuration and prints a nonce to type into it. The check then needs the window resized and captured (`--snapshot`) and the notifications confirmed; until then it exits 2 (pending), never a pass. `sh build/check-local.sh` with no arguments prints every step's form.

See [INGREDIENTS.md](INGREDIENTS.md) for every input, its pin and how it is kept current, and what CI runs where.
