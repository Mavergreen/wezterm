#!/bin/sh
# platform: host-agnostic
#   usage: . tests/support/pinned.sh; pinned_or_skip COMPONENT WHAT
#          Sets pinned to the installed tree of COMPONENT's pinned release (build/tools.sh tree, under
#          MAVERGREEN_TOOL_ROOT). Exits 77 naming WHAT when that release is not installed, as on the
#          10.9 guest, and fails when another release is.
pinned_or_skip() {
    pinned=$(sh "$ROOT/build/tools.sh" tree --root "${MAVERGREEN_TOOL_ROOT:-/}" "$1" 2>&1) || {
        case "$pinned" in *'but not installed'*) echo "$2 needs the pinned $1: $pinned"; exit 77 ;; esac
        fail "$2 needs the pinned $1: $pinned"
    }
}
