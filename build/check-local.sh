#!/bin/sh
# platform: macOS-only -- fails closed on unperformed native local acceptance
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
. "$REPO_ROOT/build/msc.sh"
if [ "${1:-}" = --in-environment ]; then
    shift
else
    exec sh "$REPO_ROOT/build/environment.sh" sh "$0" --in-environment "$@"
fi
case "${1:-}" in
    --non-gui|--gui) mode=$1; shift ;;
    *) fail 'usage: check-local.sh --non-gui | --gui [--snapshot RUN | --replay | --collect RUN --confirm-visual NONCE --confirm-click NONCE --confirm-expiry NONCE ...]' ;;
esac
[ -f "$WORK_ROOT/prepared.json" ] || fail 'native artifacts are missing; prepare and build first'
sh "$REPO_ROOT/build/prepare.sh" --verify
lock_recipe
if [ "$mode" = --non-gui ]; then
    [ "$#" -eq 0 ] || fail 'unexpected non-GUI acceptance arguments'
    "$PYTHON" "$REPO_ROOT/build/acceptance.py" "$mode" "$REPO_ROOT" "$WORK_ROOT" "$SHIPYARD_SCRIPTS"
else
    case "${1:-}" in
        '') "$PYTHON" "$REPO_ROOT/build/gui_probe.py" start "$REPO_ROOT" "$WORK_ROOT" ;;
        --replay) "$PYTHON" "$REPO_ROOT/build/gui_probe.py" replay "$REPO_ROOT" "$WORK_ROOT" ;;
        --snapshot)
            [ "$#" -eq 2 ] || fail 'usage: --gui --snapshot RUN'
            "$PYTHON" "$REPO_ROOT/build/gui_probe.py" snapshot "$REPO_ROOT" "$WORK_ROOT" "$2"
            ;;
        --collect)
            "$PYTHON" "$REPO_ROOT/build/acceptance.py" "$mode" "$REPO_ROOT" "$WORK_ROOT" "$SHIPYARD_SCRIPTS" "$@"
            ;;
        *) fail 'unknown GUI acceptance operation' ;;
    esac
fi
