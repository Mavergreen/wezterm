#!/bin/sh
# platform: macOS-only -- tests the selected native notification backend
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$WORK_ROOT/prepared.json" ] || { echo 'not prepared; notification test needs verified source'; exit 77; }
sh "$ROOT/build/prepare.sh" --verify
mkdir -p "$EVIDENCE_DIR"
cd "$SOURCE_DIR"
sh "$ROOT/build/environment.sh" cargo tree --locked \
    --target x86_64-apple-darwin -p wezterm-gui --prefix none > "$EVIDENCE_DIR/notification-tree.txt"
if grep '^objc2-user-notifications v' "$EVIDENCE_DIR/notification-tree.txt" >/dev/null; then
    echo 'FAIL: Mavericks product still requires UserNotifications framework'
    exit 1
fi
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "the notification backend's tests"
# spec: PORT.md "Staging and local acceptance" -- the release profile reuses the product build's dependencies.
sh "$ROOT/build/environment.sh" cargo test --release --locked \
    --target x86_64-apple-darwin -p wezterm-toast-notification --lib \
    --no-default-features --features legacy-macos legacy_tests -- --test-threads=1 \
    > "$EVIDENCE_DIR/notification-tests.log" 2>&1 || { tail -45 "$EVIDENCE_DIR/notification-tests.log"; exit 1; }
grep -E 'test result: ok\. [1-9][0-9]* passed; 0 failed' "$EVIDENCE_DIR/notification-tests.log"
echo 'PASS: legacy backend tests run without a UserNotifications dependency; actual app delivery remains pending'
