#!/bin/sh
# platform: macOS-only -- reads the native release build's cargo messages and receipts
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$WORK_ROOT/build.json" ] || { echo 'not built; the update-check default is read from the release build'; exit 77; }
config_rs="$SOURCE_DIR/config/src/config.rs"
# spec: PORT.md "Upstream's update checker" -- the feature means what the build relies on only while
#       upstream's default reads it this way.
grep -A2 '^fn default_check_for_updates() -> bool {$' "$config_rs" | grep -F 'cfg!(not(feature = "distro-defaults"))' > /dev/null ||
    fail "upstream's default_check_for_updates no longer reads the distro-defaults feature ($config_rs)"
"$PYTHON" "$ROOT/build/artifacts.py" verify-build "$WORK_ROOT" "$ROOT" ||
    fail 'the cargo messages or the binaries are not the ones the build recorded'
"$PYTHON" - "$EVIDENCE_DIR/cargo-messages.jsonl" "$TARGET_DIR/x86_64-apple-darwin/release" <<'PY'
import json, os, sys
messages, release = sys.argv[1:]
units = {}
for line in open(messages):
    if not line.startswith('{'):
        continue
    message = json.loads(line)
    if message.get('reason') == 'compiler-artifact':
        units.setdefault(message['target']['name'], []).append(message)
def only(name, kind):
    found = [unit for unit in units.get(name, []) if kind in unit['target']['kind']]
    if len(found) != 1:
        sys.exit('FAIL: the build compiled %d %s %s units, not one' % (len(found), name, kind))
    return found[0]
config = only('config', 'lib')
if 'distro-defaults' not in config['features']:
    sys.exit('FAIL: config was built without distro-defaults, so check_for_updates defaults to true: %r' % config['features'])
for name in ('wezterm-gui', 'wezterm', 'wezterm-mux-server', 'strip-ansi-escapes'):
    unit = only(name, 'bin')
    if unit['executable'] != os.path.join(release, name):
        sys.exit('FAIL: %s was built at %s, not in %s' % (name, unit['executable'], release))
if 'distro-defaults' not in only('wezterm-gui', 'bin')['features']:
    sys.exit('FAIL: wezterm-gui was built without its distro-defaults feature')
PY
pass "the shipped binaries' config was built with upstream's distro-defaults, so upstream's update checker is off unless a user turns it on"
