#!/bin/sh
# platform: macOS-only -- records children that exit as soon as they have written, with the newly built CLI
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
bin=$TARGET_DIR/x86_64-apple-darwin/release
[ -x "$bin/wezterm" ] || { echo 'not built; wezterm is missing'; exit 77; }
sh "$ROOT/build/environment.sh" sh -c '
    "$CC" -dynamiclib -Wall -Werror "$1/tests/fixtures/slow-pty-read.c" -o "$2"
' sh "$ROOT" "$TEST_ROOT/slow-pty-read.dylib"
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "the record drain test"
# platform: wezterm record needs a terminal, so script(1) gives it one; record NAME DELAY_MS SCRIPT
#           delays each read of the child's pty DELAY_MS and prints what the cast recorded
record() {
    printf '%s\n' "$3" > "$TEST_ROOT/$1.sh"
    env -i HOME="$TEST_ROOT" PATH=/usr/bin:/bin LANG=en_US.UTF-8 \
        DYLD_INSERT_LIBRARIES="$TEST_ROOT/slow-pty-read.dylib" WEZTERM_TEST_PTY_READ_DELAY_MS="$2" \
        /usr/bin/script -q "$TEST_ROOT/$1.transcript" "$bin/wezterm" --skip-config record \
        -o "$TEST_ROOT/$1.cast" -- /bin/sh "$TEST_ROOT/$1.sh" > "$TEST_ROOT/$1.log" 2>&1 ||
        { cat "$TEST_ROOT/$1.log" >&2; fail "$1: wezterm record failed"; }
    grep -q 'Child status: Some(ExitStatus { code: 0' "$TEST_ROOT/$1.log" ||
        { cat "$TEST_ROOT/$1.log" >&2; fail "$1: wezterm record did not report the child's exit 0"; }
    "$PYTHON" - "$TEST_ROOT/$1.cast" <<'PY'
import json, sys
lines = open(sys.argv[1]).readlines()
sys.stdout.write(''.join(item[2] for item in (json.loads(line) for line in lines[1:]) if item[1] == 'o'))
PY
}
# spec: PORT.md "Recording a child's last output" -- the child's exit is reported first, every time
out=$(record late 200 'printf "recorded-late-output\n"')
case $out in
    *recorded-late-output*) ;;
    *) fail "the output read after the child's exit is missing from the cast: [$out]" ;;
esac
pass 'wezterm record keeps output that it reads after the child has exited'
# spec: PORT.md "Recording a child's last output" -- a burst of output, unslowed, then an immediate exit
for run in 1 2 3; do
    lines=$(record burst$run 0 'i=0; while [ $i -lt 2000 ]; do echo "burst line $i"; i=$((i + 1)); done' |
        grep -c '^burst line [0-9]*')
    [ "$lines" -eq 2000 ] || fail "burst run $run: the cast has $lines of the child's 2000 lines"
done
pass 'wezterm record keeps all 2000 lines of a child that exits right after writing them, three times'
