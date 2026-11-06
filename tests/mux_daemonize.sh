#!/bin/sh
# platform: macOS-only -- daemonizes the newly built mux server and reads its forked child's wait status
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
bin=$TARGET_DIR/x86_64-apple-darwin/release
[ -x "$bin/wezterm-mux-server" ] || { echo 'not built; wezterm-mux-server is missing'; exit 77; }
sh "$ROOT/build/environment.sh" sh -c '
    "$CC" -dynamiclib -Wall -Werror "$1/tests/fixtures/wait-status.c" -o "$2"
' sh "$ROOT" "$TEST_ROOT/wait-status.dylib"
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "the mux daemonize test"
# platform: the server's socket is $HOME/.local/share/wezterm/sock, and a Unix socket's path must
#           shorter than 104 bytes, so each home is a two-letter directory in TEST_ROOT
status_name() {
    if [ $(($1 & 127)) -eq 0 ]; then echo "exit $(($1 >> 8))"; else echo "signal $(($1 & 127))"; fi
}
# spec: PORT.md "Daemonizing mux server" -- each run counts: the crash needs the main thread to have
#       parked before the fork, which notify's FSEvents watcher makes it do while the config loads
for run in 1 2 3; do
    home=$TEST_ROOT/h$run
    mkdir "$home"
    : > "$TEST_ROOT/waits$run"
    assert_run 0 env -i HOME="$home" PATH=/usr/bin:/bin \
        DYLD_INSERT_LIBRARIES="$TEST_ROOT/wait-status.dylib" WEZTERM_TEST_WAIT_LOG="$TEST_ROOT/waits$run" \
        "$bin/wezterm-mux-server" --config-file "$ROOT/tests/fixtures/mux.lua" --daemonize
    pidfile=$home/.local/share/wezterm/pid
    i=0
    until [ -s "$pidfile" ] && pid=$(tr -dc 0-9 < "$pidfile") && [ -n "$pid" ]; do
        [ "$i" -lt 30 ] || fail "run $run: the daemon wrote no pid file"
        sleep 1; i=$((i + 1))
    done
    kill -0 "$pid" 2> /dev/null || fail "run $run: the daemon (pid $pid) is not running"
    kill "$pid"
    i=0
    while kill -0 "$pid" 2> /dev/null; do
        [ "$i" -lt 30 ] || { kill -KILL "$pid"; fail "run $run: the daemon (pid $pid) ignored SIGTERM"; }
        sleep 1; i=$((i + 1))
    done
    [ "$(wc -l < "$TEST_ROOT/waits$run" | tr -d ' ')" = 1 ] ||
        fail "run $run: expected one reaped child, recorded: $(cat "$TEST_ROOT/waits$run")"
    read -r child status < "$TEST_ROOT/waits$run"
    [ "$status" -eq 0 ] ||
        fail "run $run: the daemonizing child (pid $child) ended with $(status_name "$status"), not exit 0"
done
pass 'wezterm-mux-server --daemonize: the forked child exits 0 and the daemon runs, three times'
