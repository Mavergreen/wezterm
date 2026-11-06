#!/bin/sh
# platform: macOS-only -- builds the Mavericks terminal in the release profile
#   usage: build-native.sh [--mode native|cross]
#          Prepares (or verifies) the source, builds the four shipped executables for x86_64 10.9 with
#          the pinned products for the mode (default native; build-cross.sh passes cross) and stages
#          the product bundle.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
mode=native
case "$#:${1:-}:${2:-}" in
    0::) ;;
    2:--mode:native|2:--mode:cross) mode=$2 ;;
    *) printf 'usage: build-native.sh [--mode native|cross]\n' >&2; exit 2 ;;
esac
"$PYTHON" "$REPO_ROOT/build/artifacts.py" gui-idle "$WORK_ROOT" "$REPO_ROOT"
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
# spec: PORT.md "Upstream's update checker" -- upstream's packager feature turns its GitHub update
#       check off by default, since the Sparkle updater updates this product. Cargo's messages record each
#       unit's features beside the human log, so tests/update_check.sh can read what was built.
sh "$REPO_ROOT/build/environment.sh" --mode "$mode" cargo build --locked --release \
    --target x86_64-apple-darwin -p wezterm-gui -p wezterm -p wezterm-mux-server -p strip-ansi-escapes \
    --features wezterm-gui/distro-defaults --message-format=json-render-diagnostics \
    > "$EVIDENCE_DIR/cargo-messages.jsonl" 2> "$EVIDENCE_DIR/build.log" || rc=$?
printf '%s\n' "$rc" > "$EVIDENCE_DIR/build.exit"
tail -25 "$EVIDENCE_DIR/build.log"
[ "$rc" -eq 0 ] || exit "$rc"
"$PYTHON" "$REPO_ROOT/build/artifacts.py" record-build "$WORK_ROOT" "$REPO_ROOT"
printf '%s\n' "$$" > "$WORK_ROOT/.lock/stage-owner"
trap 'rm -f "$WORK_ROOT/.lock/stage-owner"; rmdir "$WORK_ROOT/.lock"' EXIT
sh "$REPO_ROOT/build/stage-app.sh" --from-builder
