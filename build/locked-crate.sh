#!/bin/sh
# platform: host-agnostic
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'usage: locked-crate.sh NAME [LOCK]' >&2; exit 2; }
if [ "$#" -eq 2 ]; then
    lock=$2
else
    . "$REPO_ROOT/build/lib.sh"
    lock=$SOURCE_DIR/Cargo.lock.upstream
fi
exec "${PYTHON:-python}" "$REPO_ROOT/build/check-lock.py" --crate "$1" "$lock"
