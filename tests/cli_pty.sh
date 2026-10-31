#!/bin/sh
# platform: macOS-only -- executes the newly built CLI and a real shell PTY
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
bin=$TARGET_DIR/x86_64-apple-darwin/debug
[ -x "$bin/wezterm" ] && [ -x "$bin/wezterm-mux-server" ] || { echo 'not built; CLI PTY test needs both executables'; exit 77; }
. "$ROOT/components/wezterm/version"
mkdir -p "$EVIDENCE_DIR"
"$bin/wezterm" --version > "$EVIDENCE_DIR/cli-version.txt"
"$bin/wezterm-mux-server" --version > "$EVIDENCE_DIR/mux-version.txt"
grep -F "local-$DIGEST" "$EVIDENCE_DIR/cli-version.txt"
grep -F "local-$DIGEST" "$EVIDENCE_DIR/mux-version.txt"
"$bin/wezterm" --help > "$EVIDENCE_DIR/cli-help.txt"
"$bin/wezterm-mux-server" --help > "$EVIDENCE_DIR/mux-help.txt"
run=$(mktemp -d "$EVIDENCE_DIR/pty.XXXXXX")
/usr/bin/script -q "$run/transcript.txt" "$bin/wezterm" --skip-config record \
    -o "$run/recording.cast" -- /bin/sh -c 'printf "MAVERGREEN_LOCAL_RECIPE_PTY_OK\n"' > "$run/driver.log" 2>&1
"$PYTHON" - "$run/recording.cast" <<'PY'
import json, sys
lines = open(sys.argv[1]).readlines()
header = json.loads(lines[0])
assert header['version'] == 2, header
output = ''.join(item[2] for item in (json.loads(line) for line in lines[1:]) if item[1] == 'o')
assert 'MAVERGREEN_LOCAL_RECIPE_PTY_OK' in output, output
PY
echo 'PASS: versioned local CLI and mux execute; real PTY shell output recorded'
