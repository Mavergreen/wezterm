#!/bin/sh
# platform: macOS-only -- measures missing Mavericks selectors and real guarded behavior
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$WORK_ROOT/prepared.json" ] || { echo 'not prepared; Cocoa tests need native source'; exit 77; }
sh "$ROOT/build/prepare.sh" --verify
if [ "${1:-}" != --in-environment ]; then
    exec sh "$ROOT/build/environment.sh" sh "$0" --in-environment
fi
"$CC" "$ROOT/tests/fixtures/cocoa-availability.m" -framework AppKit -framework Foundation \
    -o "$EVIDENCE_DIR/cocoa-availability"
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "the Cocoa availability probe and tests"
"$EVIDENCE_DIR/cocoa-availability" > "$EVIDENCE_DIR/cocoa-availability.txt"
cat "$EVIDENCE_DIR/cocoa-availability.txt"
cd "$SOURCE_DIR"
# spec: PORT.md "Staging and local acceptance" -- the release profile reuses the product build's
#       dependencies, where the dev profile compiled the whole graph a second time on a fresh root.
"$CARGO" test --release --locked --target x86_64-apple-darwin -p window --lib mavericks_compat -- --test-threads=1 \
    > "$EVIDENCE_DIR/cocoa-tests.log" 2>&1 || { tail -50 "$EVIDENCE_DIR/cocoa-tests.log"; exit 1; }
grep 'absent_selectors_skip_actions_and_fall_back_to_light .* ok' "$EVIDENCE_DIR/cocoa-tests.log" || { echo 'FAIL: actual guarded fallback regression is missing'; exit 1; }
grep 'supported_native_selector_still_performs_the_real_operation .* ok' "$EVIDENCE_DIR/cocoa-tests.log"
grep 'legacy_informal_layer_delegate_allows_window_view_registration .* ok' "$EVIDENCE_DIR/cocoa-tests.log"
grep 'opengl_backing_layer_uses_real_calayer_without_metal .* ok' "$EVIDENCE_DIR/cocoa-tests.log"
grep '^test .*::native_cgl_detaches_layer_backing_before_attaching_its_drawable \.\.\.' "$EVIDENCE_DIR/cocoa-tests.log"
grep '^test .*::unavailable_accelerated_renderer_returns_the_native_format_error \.\.\.' "$EVIDENCE_DIR/cocoa-tests.log"
grep 'new_windows_opt_into_native_full_screen .* ok' "$EVIDENCE_DIR/cocoa-tests.log" || { echo 'FAIL: new windows do not opt into native full screen'; exit 1; }
grep 'test result: ok. 9 passed; 0 failed;' "$EVIDENCE_DIR/cocoa-tests.log"
echo 'PASS: missing Cocoa methods take guarded fallbacks; supported native operations remain active'
