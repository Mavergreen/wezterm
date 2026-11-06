#!/bin/sh
# platform: macOS-only -- checks the actual GUI startup identity before parsing
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
bin=$TARGET_DIR/x86_64-apple-darwin/release/wezterm-gui
[ -x "$bin" ] || { echo 'GUI not built; startup version test requires the real executable'; exit 77; }
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "the GUI startup version test"
mkdir -p "$WORK_ROOT/gui-version-home"
HOME=$WORK_ROOT/gui-version-home
XDG_CACHE_HOME=$HOME/cache
XDG_CONFIG_HOME=$HOME/config
XDG_DATA_HOME=$HOME/data
export HOME XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME
"$bin" --version > "$EVIDENCE_DIR/gui-version.txt"
grep -F "$(upstream_version)-mavericks." "$EVIDENCE_DIR/gui-version.txt" || { echo 'FAIL: GUI startup did not initialize its pinned build identity'; exit 1; }
echo 'PASS: GUI --version reports the pinned snapshot version'
