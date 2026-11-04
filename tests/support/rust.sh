#!/bin/sh
# platform: host-agnostic
pinned_cargo_or_skip() {
    rust=$(sh "$ROOT/build/tools.sh" tree --root "${MAVERGREEN_TOOL_ROOT:-/}" rust 2>&1) || {
        case "$rust" in *'but not installed'*) echo "$1 needs the pinned rust: $rust"; exit 77 ;; esac
        fail "$1 takes cargo only from the pinned rust: $rust"
    }
    cargo=$rust/bin/cargo
}
