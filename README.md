# Mavericks WezTerm

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut its first release.

An unofficial community port of current [WezTerm](https://github.com/wezterm/wezterm) for Mac OS X 10.9.5. Not affiliated with or endorsed by the upstream project.

## Local development

The real native GUI now builds and runs on Mavericks using OpenGL. Local acceptance has observed visible output/colors/Unicode, maintainer-typed keyboard input, resize/redraw, normal shutdown, native notification delivery/click/expiry, and an independent empty-target build followed by another GUI launch. This is a development milestone, **not an installable or publishable release**. No installer, updater or release CI exists yet.

On Mavericks with the existing Mavergreen Rust, clang22/Recaulk, LLVM archive tools, make, CMake and shipyard products available:

```sh
sh build/prepare.sh
sh build/build-native.sh
sh build/check-local.sh --non-gui
```

Preparation verifies immutable source and submodule archives, applies explained patches and preserves all 821 upstream locked package identities. Output is on local storage under `${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/private/tmp}/mm-build}/<checkout-name>-wezterm-local`, not in this checkout. The build prints its concrete path and stages `stage/Mavericks WezTerm.app` there. Source fetching/building does not require Apple's git. Python helpers support Python 2.7 and Python 3; `PYTHON` selects the interpreter.

A changed recipe requires `sh build/prepare.sh` again. Modified prepared sources/crates are rejected rather than discarded: save those edits outside the owned preparation directories first. Development builds disable debug symbols and incremental compilation to conserve disk. The native environment explicitly selects the pinned SDK/compiler and LLVM `ar`/`ranlib`, without changing installed toolchains.

## Isolated GUI acceptance

Keep the desktop unlocked while capturing a window. Stage the private acceptance bundle (the product's, without its document types), then start it through LaunchServices:

```sh
sh build/stage-app.sh --acceptance
sh build/check-local.sh --gui
```

This prints a private run directory and nonce, opens the test terminal and exits **2 (pending)**. It is not a pass or a skipped check. The private HOME/config and short Unix-socket alias avoid touching existing WezTerm configuration/runtime state. The helper captures only the identified test window, never the desktop or Notification Center.

Type the displayed nonce rather than pasting it, resize the window, and leave it open. Capture the resized window before exiting:

```sh
sh build/check-local.sh --gui --snapshot RUN_DIRECTORY
```

Inside the test terminal, `notify` requests a banner to click, `expire` requests a three-second notification, and `exit` closes the fixture after keyboard/resize/snapshot checks. Notifications open no URL in this GUI test. Inspect both owned-window PNGs before supplying visual confirmation.

Collection requires explicit measured results, including the fresh-build replay; missing/failed operations keep `evidence/local-acceptance.json` false. See `sh build/check-local.sh` for the command shape and [PORT.md](PORT.md) for evidence boundaries. Local human confirmations are intentionally supported here; this is **not** the future automated installed-product publication/automerge gate.

Run all repository tests through shipyard, sequentially because native artifact tests share the target/stage:

```sh
. build/msc.sh
MAVERICKS_TEST_JOBS=1 sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"
```

Artifact-dependent test files may return 77 before building. Explicit `check-local.sh` invocations fail on missing artifacts or unperformed checks. Do not enable the provenance-only upstream graphics features or use `--all-features`: WebGpu/Metal are intentionally unsupported in this product.

See [INGREDIENTS.md](INGREDIENTS.md) for input provenance and [PORT.md](PORT.md) for carried patches, observed limits and retirement conditions. Modern-host/Apple-Silicon cross builds, installed packages, complete functionality, Sparkle, weekly updates and publication remain subsequent work. Automated installed-product GUI acceptance must gate eventual updates and publication.
