#!/bin/sh
# platform: host-agnostic
: "${REPO_ROOT:?caller must set REPO_ROOT}"
PYTHON=${PYTHON:-python}
export PYTHON
fail() { printf 'wezterm-local: %s\n' "$*" >&2; exit 1; }
MAVERICKS_ROOT=$REPO_ROOT
export MAVERICKS_ROOT
. "$REPO_ROOT/build/msc.sh"
. "$SHIPYARD/lib.sh"
WORK_ROOT=$("$PYTHON" - "$REPO_ROOT" "${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/private/tmp}/mm-build}" <<'PY'
import os, sys
repo = os.path.realpath(sys.argv[1])
work = os.path.realpath(os.path.join(sys.argv[2], os.path.basename(repo) + '-wezterm-local'))
if work == repo or work.startswith(repo + os.sep) or repo.startswith(work + os.sep):
    sys.stderr.write('wezterm-local: build output must be outside the checkout\n')
    sys.exit(1)
print(work)
PY
) || exit 1
SOURCE_DIR=$WORK_ROOT/source
CRATES_DIR=$WORK_ROOT/crates
TARGET_DIR=$WORK_ROOT/target
STAGE_DIR=$WORK_ROOT/stage
EVIDENCE_DIR=$WORK_ROOT/evidence
export REPO_ROOT WORK_ROOT SOURCE_DIR CRATES_DIR TARGET_DIR STAGE_DIR EVIDENCE_DIR
TOOL_ROOT=${MAVERGREEN_TOOL_ROOT:-/}
TREES=${TOOL_ROOT%/}/usr/local/mavergreen
pinned_rust() {
    RUST_BIN=$(sh "$REPO_ROOT/build/tools.sh" tree --root "$TOOL_ROOT" ${1:+--mode "$1"} rust) ||
        fail "install the pinned rust release above (INGREDIENTS.md), then retry; build/tools.sh tree --root $TOOL_ROOT rust"
    RUST_BIN=$RUST_BIN/bin
}
own_work_root() {
    if [ -L "$WORK_ROOT" ]; then fail "foreign symlink: $WORK_ROOT"; fi
    if [ -f "$WORK_ROOT/.owner" ]; then
        [ "$(cat "$WORK_ROOT/.owner")" = "$REPO_ROOT" ] || fail "foreign owner: $WORK_ROOT"
    else
        if [ -d "$WORK_ROOT" ]; then
            entries=$(ls -A "$WORK_ROOT")
            case "$entries" in ''|downloads) ;; *) fail "foreign directory: $WORK_ROOT" ;; esac
        fi
        mkdir -p "$WORK_ROOT"
        printf '%s\n' "$REPO_ROOT" > "$WORK_ROOT/.owner"
    fi
}
lock_recipe() {
    own_work_root
    mkdir "$WORK_ROOT/.lock" 2>/dev/null || fail "recipe busy: $WORK_ROOT/.lock"
    trap 'rmdir "$WORK_ROOT/.lock"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}
