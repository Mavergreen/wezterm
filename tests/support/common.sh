#!/bin/sh
# platform: host-agnostic
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wezterm-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_run() {
    expected=$1; shift
    actual=0
    "$@" > "$TEST_ROOT/output" 2>&1 || actual=$?
    if [ "$actual" -ne "$expected" ]; then
        printf 'FAIL: expected exit %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
        tail -15 "$TEST_ROOT/output" >&2
        exit 1
    fi
}
assert_output() { grep -F "$1" "$TEST_ROOT/output" >/dev/null || fail "missing diagnostic: $1"; }
pass() { printf 'PASS: %s\n' "$*"; }
