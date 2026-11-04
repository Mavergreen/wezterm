# Build ingredients

This repository is in its local native-port stage. It does not package or publish. Release automation and automatically maintained ingredient pins must be established before a first release; none is claimed to exist here.

| Input | Identity / provenance | Update policy |
|---|---|---|
| WezTerm | Full upstream commit, its UTC committer time (`COMMITTED`) and the SHA256 of GitHub's tarball of it in `components/wezterm/version` | Renovate (`git-refs` on `wezterm/wezterm` `main`) moves `DIGEST` once a week, Mondays 04:00–05:00 UTC; the pins bot writes the rest of the pin on Renovate's branch (below); builds never resolve main |
| freetype2, libpng, zlib, harfbuzz | Exact parent gitlinks plus each tarball's SHA256 in the same pin; reviewed mapping in `components/wezterm/gitlinks.json` | Follow the parent's gitlinks, never independent latest branches: the pins bot reads them from the pinned commit |
| Cargo crates and Git dependencies | Original upstream Cargo.lock; preparation verifies all package versions/sources/checksums after declared path substitutions | Follow upstream's lockfile; no opportunistic dependency upgrades |
| Private libssh-rs-sys source | Exact locked `.crate` checksum; carried source patch in `patches/crates/` | Retire the path substitution when the upstream SDK-capability fix lands |
| Private libssh2-sys source | Exact locked `.crate` checksum; build-script patch in `patches/crates/libssh2-sys/` so a complete source never runs git | Retire when upstream checks for the vendored source rather than `.git` |
| Private security-framework 3.7.0 source | Exact locked `.crate` checksum; runtime optional-session-ticket patch in `patches/crates/` | Retire when upstream guards the optional API without altering trust verification |
| Patches, notification adapter and Cocoa/CGL startup | `patches/*.patch` and `patches/crates/<crate>/*.patch`, applied in name order by shipyard's `apply_patches.sh`, including the upstream-owned legacy Cocoa notification backend; content covered by preparation provenance | Maintained here with reasons, upstream destinations and retirement conditions in PORT.md |
| Rust/cargo, clang22 (with its Recaulk), make | One release each, pinned under `components/`; see Build tools below | Renovate `github-releases` managers with `-mavericks.N` versioning |
| Shipyard and pinned 10.9 SDK | Installed shared facilities resolved by canonical build/msc.sh; fetch_sdk.sh verifies the SDK pin | Shared family maintenance; SDK bytes are not modified |
| Tests | POSIX shell, Python 2.7/3-compatible standard library, installed family tools | No downloaded test framework or Homebrew dependency |

No ingredient-bump workflow exists in this local-only stage.

The shared preset groups every Mavergreen release (Rust, clang22, make, Longboat) into one Renovate PR, and a green build merges it.

### The pins bot

Renovate moves `DIGEST` in `components/wezterm/version`, but the build also verifies what follows from that commit: `SHA256` of the tarball `build/prepare.sh` fetches (GitHub's tarball of the commit, through shipyard's `fetch_pinned_source.sh`), `COMMITTED`, each submodule's `_DIGEST` (its gitlink at that commit) and `_SHA256`, and `components/wezterm/gitlinks.json`. Renovate cannot compute those. `.github/workflows/pins-bot.yml` runs on every push to a `renovate/**` branch whose `DIGEST` moved. Its `pins` job, which can only read, runs `scripts/pin-source-tarballs.sh --fill`. That script downloads each tarball and checks with git that it holds exactly its commit's tree, running nothing it fetched. Its `push` job never sees upstream's bytes. It writes the checked values with `scripts/pins-bot.sh apply` and pushes them as the `mavergreen-pins-bot` GitHub App, so the build runs on the new head. `gitIgnoredAuthors` in `.github/renovate.json` keeps that commit from counting as an edit to Renovate's branch. If the bot fails, run `sh scripts/pin-source-tarballs.sh --fill` on the branch (it needs git and python3) and push what it writes. `--check` writes nothing and exits 3 when the pin is stale.

Upstream licensing/attribution remains in the verified source tree. The local bundle stages upstream's existing terminal.icns, LICENSE.md, shell integration/completion and compiled terminfo; no application icon is generated or replaced. Complete dependency-license redistribution and packaging review remain required before a release.

The local acceptance record binds prepared input provenance, executable/staged Contents hashes and actual GUI evidence. A separate empty-target source-snapshot build and GUI replay have also passed. These local results do not replace modern-host parity or automated installed-product publication checks.

## Build tools

The build runs these family products, each pinned to one release. `build/environment.sh` first runs `build/tools.sh check`, which refuses unless each product's installed manifest (`/usr/local/mavergreen/<short>/mavergreen.plist`, key `version`) equals its pin, naming the product, the pin and what is installed. It then takes every tool from that product's own tree (`/usr/local/mavergreen/<short>/bin`), never the link farm, so the pinned product is the one used whichever member of its group is selected. Preparation (`build/prepare.sh`) needs only cargo, for `cargo fetch --locked` and `cargo update --offline`, whose output is the prepared lock; it checks the rust pin alone with `build/tools.sh tree rust` and runs that tree's cargo. `MAVERGREEN_TOOL_ROOT` moves the root both look under. A release's native and cross products share one pin, as fetch_clang22.sh expects of `components/clang22`: a native build checks `rust`, `clang22` and `make`, a cross build `rust-cross`, `clang22-cross` and `make`.

| Ingredient | Pinned in | Renovate | On a bump | Why this release |
|---|---|---|---|---|
| Rust (`rust` on 10.9, `rust-cross` on a modern Mac): `cargo`, `rustc`, `rustdoc` | `components/rust/version` = `1.99.1-mavericks.10` | `github-releases` on `Mavergreen/rust`, `-mavericks.N` versioning | the next build compiles with the new toolchain | The newest release; both of its packages come from this one tag. |
| clang22 (`clang22` on 10.9, `clang22-cross` on a modern Mac): `clang`, `clang++` (the C/C++ compilers, and the linker driver for clang22's `portable-ld`), `llvm-ar`, `llvm-ranlib`; `llvm-otool`, `llvm-lipo`, `llvm-nm` and `llvm-strings` for tests and checks | `components/clang22/version` = `22.1.8-mavericks.12`, with its Linux archive's line of that release's `SHA256SUMS` in `components/clang22/linux-sha256` | `github-releases` on `Mavergreen/clang-22`, `-mavericks.N` versioning; the digest beside it is copied by hand from the new release's `SHA256SUMS`, as the bump's PR says | the next build compiles and links with the new LLVM and its Recaulk | The release Rust `1.99.1-mavericks.10` was built with (its `build-info-native.txt` and `build-info-cross.txt` say `clang=22.1.8-mavericks.12`), so Rust's own objects and this build's C, C++ and link share one LLVM and one Recaulk. `22.1.8-mavericks.13` is a packaging-only repackage. `linux-sha256` is there because `fetch_clang22.sh` refuses a Linux fetch without it, and the Sparkle updater and conformance's `LIPO`/`OTOOL`/`NM` run with clang22 on Linux. |
| Recaulk (the 10.9 back-fills) | through clang22: `20261025.5` in `22.1.8-mavericks.12` | moves with clang22 | moves with clang22 | Linked, statically, into every binary: clang22's `clang.cfg` and `clang++.cfg` name clang22's own `lib/librecaulk.a`, and the binaries define `___recaulk_impl_*` symbols. The standalone `recaulk` product is never used, so it has no pin of its own. |
| GNU make: `make`, `gmake` | `components/make/version` = `4.4.1-mavericks.8` | `github-releases` on `Mavergreen/make`, `-mavericks.N` versioning | the next build's vendored OpenSSL builds with the new make | openssl-src runs `make`, whose recipes run `$(MAKE)`, the exported `gmake`. This is the release built with clang22 `22.1.8-mavericks.12`; `4.4.1-mavericks.9` only follows clang22 `.13`. |

Natively, install each pinned release's pkg from its GitHub release after checking it against that release's `SHA256SUMS`: `sudo installer -pkg <pkg> -target /`. The clang22 pkgs since `22.1.8-mavericks.12` require Longboat's 10.9 SDK, so run `sudo longboat sdk install 10.9` first. Their assets are named `mavericks-clang-22-native-<tag>.pkg` and `mavericks-clang-22-cross-<tag>.pkg`, not `<short>-<tag>.pkg`.

Not pinned: `shipyard-cmake` and the shipyard scripts are the shared facility that moves with `@v1`; the build exports `CMAKE` but nothing in it runs CMake. `perl` (OpenSSL's `Configure`) is the system's `/usr/bin/perl`. libssh2-sys's build script runs `git submodule update --init` once and ignores its result; the vendored sources are already present.

### CI-only pins

Pinned so CI installs a known release, but nothing shipped is built with it, so a bump neither repackages nor appears in the declared state.

| Tool | Pinned in | Renovate | Used by | Why this release |
|---|---|---|---|---|
| Longboat (installs `sdk109`, which the clang22 pkgs require) | `components/longboat/version` = `20261027.1` | `github-releases` on `Mavergreen/longboat`, `YYYYMMDD.N` versioning | CI, before installing clang22 | The release clang-22 `22.1.8-mavericks.12` and Rust `1.99.1-mavericks.10` were built with. |

## Version form

The version is `YYYYMMDD.HHMMSS-mavericks.N`, for example `20261026.072628-mavericks.1`, and its comparison key is `20261026.072628.1`. The upstream part is the pinned commit's UTC committer time, which `build/derive-upstream-version.sh` copies from `COMMITTED` in `components/wezterm/version` into the gitignored `UPSTREAM_VERSION`. This deviates from ed25519's date-only form on purpose: weekly snapshots of upstream `main` can share a day, and a date alone would give two different commits one version. A native 10.9 build has no git to read the time from the commit, so `COMMITTED` is recorded in the pin beside `SHA256`, taken from the commit itself. `build/check-snapshot-order.sh` (CI only) refuses a `COMMITTED` older than the previous release's, or equal to it with a different `DIGEST`.

## Declared state

- upstream: components/wezterm/version

The upstream entry names the pin rather than `UPSTREAM_VERSION`, because the version is derived from that pin by `build/derive-upstream-version.sh`, which names both files.
