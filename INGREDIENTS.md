# Build ingredients

This repository is in its local native-port stage. It does not package or publish. Release automation and automatically maintained ingredient pins must be established before a first release; none is claimed to exist here.

| Input | Identity / provenance | Update policy |
|---|---|---|
| WezTerm | Full upstream commit and API-archive SHA256 in `components/wezterm/version` | Planned weekly upstream-main discovery; builds never resolve main |
| freetype2, libpng, zlib, harfbuzz | Exact parent gitlinks plus API-archive SHA256 in the same pin; reviewed mapping in `components/wezterm/gitlinks.json` | Follow the parent's gitlinks, never independent latest branches |
| Cargo crates and Git dependencies | Original upstream Cargo.lock; preparation verifies all package versions/sources/checksums after declared path substitutions | Follow upstream's lockfile; no opportunistic dependency upgrades |
| Private libssh-rs-sys source | Exact locked `.crate` checksum; carried source patch in `patches/crates/` | Retire the path substitution when the upstream SDK-capability fix lands |
| Private security-framework 3.7.0 source | Exact locked `.crate` checksum; runtime optional-session-ticket patch in `patches/crates/` | Retire when upstream guards the optional API without altering trust verification |
| Patches and notification adapter | Ordered `patches/series` and `patches/crates/series`, including the upstream-owned legacy Cocoa notification backend; content covered by preparation provenance | Maintained here with reasons, upstream destinations and retirement conditions in PORT.md |
| Rust/cargo, clang22/Recaulk, make, CMake | Existing installed Mavergreen products; not downloaded/replaced by this local recipe | Exact build-tool release pins remain required for later native/cross release equivalence |
| Shipyard and pinned 10.9 SDK | Installed shared facilities resolved by canonical build/msc.sh; fetch_sdk.sh verifies the SDK pin | Shared family maintenance; SDK bytes are not modified |
| Tests | POSIX shell, Python 2.7/3-compatible standard library, installed family tools | No downloaded test framework or Homebrew dependency |

No ingredient-bump workflow or declared release state exists in this local-only stage. Public numeric snapshot/repackage versioning remains unimplemented; generated `local-<full SHA>` is a private diagnostic identity only.

Upstream licensing/attribution remains in the verified source tree. Resource/icon redistribution and complete bundled-license staging must be checked before packaging. No application icon is generated or replaced here.
