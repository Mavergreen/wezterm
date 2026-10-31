# Carried changes

The product tracks an immutable upstream-main snapshot. Compatibility changes remain patches to their actual upstream owners, not private replacements for system APIs.

## Build-time OpenSSL

`0001-vendored-build-openssl.patch` enables git2's existing vendored OpenSSL support for wezterm-version's build dependency. Cargo resolver 2 separates it from the application's dependency features; without this, native builds depend on an unavailable system OpenSSL development installation. This changes build tooling, not application trust policy. Destination: upstream wezterm-version archive-build support. Retire when upstream's build helper no longer needs this explicit selection or an equivalent shared solution covers host build dependencies.

## Archive source completeness

`0002-archive-submodules.patch` checks real required C/C++ source files instead of `.git` markers and fails with a preparation diagnostic if a source component is missing. Verified GitHub archives have no Git metadata. The regression builds the actual font dependencies with an external-git trap; unpatched build scripts invoked it four times. Destination: upstream freetype/harfbuzz build scripts. Retire when upstream supports metadata-free, complete source archives directly.

## libssh 64-bit network byte order

`patches/crates/libssh-rs-sys-byteorder.patch` removes unconditional Darwin HAVE_HTONLL/HAVE_NTOHLL claims. The 10.9 SDK has no such declarations; vendored libssh already provides the correct fallback macros. No substitute implementation is added. The native test characterizes those actual macros against literal network-order byte vectors in both directions, not merely a round trip. Destination: upstream libssh-rs-sys SDK-aware capability selection. Retire when the locked upstream build script detects these APIs correctly. A private crate copy is extracted from checksum-verified Cargo.lock bytes; shared registry sources are never edited.

## Local recipe boundaries

The currently implemented driver is native-Mavericks-only. Modern-host compilation, package identity/version resolution, updater integration and release CI are subsequent work; the absence of that work is not a release exemption. Initial source hashes are observed GitHub API-archive hashes, not upstream signatures. Parent submodule gitlinks were checked against the nontruncated GitHub tree response for the full parent SHA; `components/wezterm/gitlinks.json` records that reviewed mapping. A future pin updater must verify that mapping and archive contents independently for every proposed snapshot.

All download/checksum/retry/extraction primitives come from shipyard. API archive URLs preserve the verified bytes acquired for this snapshot; the simpler codeload-only fetch_pinned_source.sh produces a different archive layout/hash. The recipe therefore uses shipyard_fetch_extract and a product-specific, single-root assembly transaction. Ownership and content manifests prevent accidental overwrites of foreign or locally modified preparation trees.

The initial baseline GUI link fails on Metal, UserNotifications, SSLSetSessionTicketsEnabled and CGColorCreateSRGB. CLI/PTY success is not GUI success. The renderer/notification/TLS/Cocoa changes must remove these blockers and prove actual app behavior, without fake-success stubs or weakened certificate verification.

## Mavericks notifications

`0003-legacy-notifications.patch` adds an explicit legacy-macos feature using real NSUserNotification/NSUserNotificationCenter APIs. The package retains its modern backend as its default; this product selects the legacy feature. Both the optional binding dependency and the separate build.rs framework directive must be gated. No system API is replaced or faked. Destination: upstream wezterm-toast-notification. Retire when upstream provides an equivalent supported backend/feature boundary.

Requests run on the main operation queue, retain one delegate for process lifetime because the native center does not retain it, and use per-notification identifiers for URL activation/expiration. The pending book is pruned of dismissed delivered notifications when another request arrives; waiting requests remain tracked until delivery/error checking. A native unavailable center is an error; an accepted asynchronous request is not proof of delivery. A delayed check logs requests that never reach the center, like the modern backend's asynchronous error reporting. User notification preferences are not overridden.

Mavericks documents a userInfo property-list size below 1 KiB. The backend measures its actual binary serialization and rejects oversized URL metadata explicitly instead of provoking a native exception or dropping the URL. Title/body properties and click/expiration lifecycle are covered by native object/unit tests. Actual banner delivery, URL interaction, expiration and queued-main-thread execution from the staged product remain mandatory local integration checks; those tests do not claim those operations already worked. Modern-host behavior of the selected legacy backend remains to be validated before release.
