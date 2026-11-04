#!/bin/sh
# platform: host-agnostic -- needs the pinned cargo and the verified upstream archive
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
. "$REPO_ROOT/tests/support/common.sh"
. "$ROOT/tests/support/rust.sh"
pinned_cargo_or_skip 'the upstream lock check'
. "$ROOT/components/wezterm/version"
assert_run 0 sh "$SHIPYARD/fetch_pinned_source.sh" "$REPO" "$DIGEST" "$SHA256" "$TEST_ROOT/source"
assert_run 0 sh "$SHIPYARD/apply_patches.sh" "$TEST_ROOT/source" "$ROOT/patches"
cp "$TEST_ROOT/source/Cargo.lock" "$TEST_ROOT/patched.lock"
cd "$TEST_ROOT/source"
assert_run 0 "$cargo" fetch --locked --target x86_64-apple-darwin
cmp -s "$TEST_ROOT/source/Cargo.lock" "$TEST_ROOT/patched.lock" || fail 'cargo rewrote the patched upstream lock'
pass 'patched upstream manifests agree with the patched upstream Cargo.lock before any crate override'
