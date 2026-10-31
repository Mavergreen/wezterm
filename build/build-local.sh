#!/bin/sh
# platform: macOS-only -- builds the native Mavericks terminal
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
if [ -f "$WORK_ROOT/prepared.json" ]; then
    sh "$REPO_ROOT/build/prepare.sh" --verify
else
    sh "$REPO_ROOT/build/prepare.sh"
fi
lock_recipe
"$PYTHON" "$REPO_ROOT/build/provenance.py" verify "$WORK_ROOT" "$REPO_ROOT"
mkdir -p "$EVIDENCE_DIR"
printf 'WORK_ROOT=%s\nBuild log: %s/build.log\n' "$WORK_ROOT" "$EVIDENCE_DIR"
cd "$SOURCE_DIR"
rc=0
sh "$REPO_ROOT/build/environment.sh" /usr/local/mavergreen/bin/cargo build --locked \
    --target x86_64-apple-darwin -p wezterm-gui -p wezterm -p wezterm-mux-server \
    > "$EVIDENCE_DIR/build.log" 2>&1 || rc=$?
printf '%s\n' "$rc" > "$EVIDENCE_DIR/build.exit"
tail -25 "$EVIDENCE_DIR/build.log"
[ "$rc" -eq 0 ] || exit "$rc"
if [ -f "$REPO_ROOT/build/stage-app.sh" ]; then
    sh "$REPO_ROOT/build/stage-app.sh"
else
    printf 'Binaries built; local app staging is not implemented yet.\n'
fi
