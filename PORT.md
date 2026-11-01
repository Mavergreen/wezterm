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

## Optional SecureTransport session tickets

`security-framework-3.7.0-runtime-tickets.patch` changes only the optional session-ticket setter and adds a private resolver module. It opens the genuine system Security framework by absolute path with RTLD_FIRST, caches the exact C-ABI function pointer or absence with OnceLock, and retains the framework reference for process lifetime. An explicit request on Mavericks returns errSecUnimplemented (-4), including an explicit false request; a real provider receives the unchanged context/Boolean and its OSStatus passes through the original error conversion. Destination: upstream security-framework. Retire when upstream provides equivalent runtime availability handling; no Recaulk API implementation has been added.

ClientBuilder defaults tickets off. The ordinary handshake, SNI, server-auth break, protocol settings and trust/hostname evaluation code are unchanged. Native tests exercise both the compiled public API and the same resolver module, with a compile-time ABI check against security-framework-sys. The packaged upstream crate omits its own unit-test certificate assets, so the external native harness avoids fetching unrelated development dependencies or adding a public test API.

The local TLS fixture uses ephemeral per-test CA/leaf files, per-connection anchors, and a loopback server linked to the already-built pinned vendored OpenSSL. It does not import identities or alter any keychain/global trust. System OpenSSL 0.9.8 only generates certificates; the actual server/client exchange is TLS 1.2. The fixture checks a trusted exchange, real wire SNI, min/max/negotiated protocol, server-auth break, untrusted-CA rejection and hostname rejection. Returning fake success for an absent setter makes two tests fail; disabling certificate verification makes both rejection tests fail. On the installed stack, the two trust failures currently surface as generic Error code 1; rejection is proved, not detailed trust-error fidelity. This measurement is recorded in the shared Recaulk queue.

## No-Metal renderer and named sRGB

`0004-no-metal-srgb.patch` selects wgpu's retained WGSL/type API without any runtime backend and reduces objc2-core-graphics to std/CGColor/CGColorSpace. Upstream OpenGL rendering is unchanged; this is not wgpu's GLES renderer. WebGpu requests fail explicitly before window/render initialization and again at the low-level WebGpu constructor. The Lua GPU enumerator uses the same unavailable diagnostic instead of entering a backendless wgpu instance (which otherwise panics). OpenGL and Software selections remain allowed. Destination: upstream product build-feature/availability handling. Retire when upstream supports an equivalent no-Metal/OpenGL-only configuration.

Cargo removed 28 optional upstream dependency identities when those defaults were disabled. Off-by-default `upstream-render-dependencies`/`upstream-graphics-dependencies` features retain the full upstream lock graph, without compiling it in the product. They are provenance-only escape hatches, not support for WebGpu; never enable them or use --all-features for this Mavericks product. The selected real GUI graph is tested to contain neither metal nor objc2-metal; all 821 original locked identities remain pinned.

The titlebar helper creates the named kCGColorSpaceSRGB via CGColorSpaceCreateWithName, then CGColorCreate with four CGFloat components, checking allocation failures and preserving CFRetained/layer ownership. No device/generic RGB fallback or exported compatibility API is introduced. Its direct objc2-core-foundation dependency uses the already-locked 0.3.2. Native tests compare independently created named spaces with CFEqual and check transparent black, opaque white, fractional RGBA and alpha; substituting device RGB fails the identity assertion. A separate native CALayer retention characterization explicitly loads genuine QuartzCore and proves the native property retains the color after the Rust owner drops. This does not claim an actual GUI titlebar was displayed yet.

The native GUI now links, and shipyard's compatibility guard accepts GUI, CLI and mux as x86_64 with SDK/minos 10.9 and no post-10.9 imports. Actual app startup, rendering/input/resize/exit and unavailable Cocoa selector fallbacks remain the next milestone; a successful link is not that acceptance.
