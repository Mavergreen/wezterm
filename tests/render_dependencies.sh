#!/bin/sh
# platform: macOS-only -- verifies no-Metal rendering and native color behavior
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$WORK_ROOT/prepared.json" ] || { echo 'not prepared; renderer test needs verified source'; exit 77; }
sh "$ROOT/build/prepare.sh" --verify
cd "$SOURCE_DIR"
sh "$ROOT/build/environment.sh" cargo tree --locked \
    --target x86_64-apple-darwin -p wezterm-gui --prefix none > "$EVIDENCE_DIR/render-tree.txt"
status=0
for crate in metal objc2-metal; do
    if grep "^$crate v" "$EVIDENCE_DIR/render-tree.txt" >/dev/null; then
        echo "FAIL: selected GUI graph still contains $crate"
        status=1
    fi
done
[ "$status" -eq 0 ] || exit "$status"
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "the renderer's tests"
# spec: PORT.md "Staging and local acceptance" -- the release profile, with the product's
#       distro-defaults, reuses the product build's dependencies instead of compiling the graph again.
for package in window wezterm-gui; do
    case "$package" in
        window) selection=--lib; features=; filter=mavericks_compat ;;
        *) selection=--bin=wezterm-gui; features=--features=distro-defaults; filter=render_compat ;;
    esac
    sh "$ROOT/build/environment.sh" cargo test --release --locked \
        --target x86_64-apple-darwin -p "$package" "$selection" $features "$filter" -- --test-threads=1 \
        > "$EVIDENCE_DIR/render-$package-tests.log" 2>&1 || { tail -55 "$EVIDENCE_DIR/render-$package-tests.log"; exit 1; }
    grep -E 'test result: ok\. [1-9][0-9]* passed; 0 failed' "$EVIDENCE_DIR/render-$package-tests.log"
done
echo 'PASS: no Metal dependencies; real sRGB properties and unsupported-WebGpu/Lua paths tested'
