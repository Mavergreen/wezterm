# WezTerm for Mavericks

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut its first release.

An unofficial community port of current [WezTerm](https://github.com/wezterm/wezterm) for Mac OS X 10.9.5. Not affiliated with or endorsed by the upstream project.

## Local development

This is an unfinished native port, not an installable release. The CLI and mux server build; the GUI still has known compatibility blockers. No installer, updater, CI or publication exists yet.

On Mavericks with the existing Mavergreen Rust, clang22/Recaulk, make, CMake and shipyard products available:

```sh
sh build/prepare.sh
sh build/build-local.sh
```

Preparation verifies immutable source and submodule archives, applies explained patches and checks that Cargo dependency versions remain locked. Output is on local storage under `${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/private/tmp}/mm-build}/<checkout-name>-wezterm-local`, not in this checkout. The command prints its concrete path. Source fetching and build scripts do not require Apple's git. Python helpers support Python 2.7 and Python 3; `PYTHON` selects the interpreter if `python` is not on PATH.

A changed recipe requires `sh build/prepare.sh` again. Modified prepared sources/crates are rejected rather than discarded: save those edits outside the owned preparation directories before replacing them. Development builds default to no debug symbols or incremental cache to conserve this target machine's disk; override Cargo's profile environment variables if needed.

```sh
. build/msc.sh
sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"
```

Artifact-dependent tests return 77 before preparation/build. A skipped test is not GUI acceptance. The current recipe explicitly runs natively on 10.9; modern-host cross-build validation is pending, not silently claimed equivalent.

See [PORT.md](PORT.md) for carried changes and [INGREDIENTS.md](INGREDIENTS.md) for input provenance. The GUI must actually render, accept keyboard input, redraw on resize and exit cleanly before the local milestone is complete. Automated installed-product acceptance must gate eventual updates and publication.
