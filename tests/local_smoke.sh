#!/bin/sh
# platform: macOS-only -- exercises staged native executables and fail-closed local acceptance
set -eu
. "$(dirname "$0")/support/common.sh"
[ -f "$ROOT/build/check-local.sh" ] || fail 'local acceptance driver is missing'
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$WORK_ROOT/prepared.json" ] || { echo 'not prepared; local smoke needs native artifacts'; exit 77; }
sh "$ROOT/build/check-local.sh" --non-gui
assert_run 1 sh "$ROOT/build/check-local.sh" --gui --collect "$TEST_ROOT"
assert_output 'GUI evidence must be inside the owned evidence directory'
mkdir "$TEST_ROOT/idle"
printf '{"owner":"%s","pid":%s}\n' "$ROOT" "$$" > "$TEST_ROOT/idle/gui-active.json"
assert_run 1 "$PYTHON" "$ROOT/build/artifacts.py" gui-idle "$TEST_ROOT/idle" "$ROOT"
assert_output 'GUI acceptance session is active'
pass 'actual staged CLI PTY and binaries pass; incomplete/foreign GUI evidence and active-session overwrite fail closed'
