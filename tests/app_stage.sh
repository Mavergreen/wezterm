#!/bin/sh
# platform: macOS-only -- checks bundle identity, resources and staged executables
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -x "$TARGET_DIR/x86_64-apple-darwin/debug/wezterm-gui" ] || { echo 'GUI not built; app staging needs actual binaries'; exit 77; }
sh "$ROOT/build/stage-app.sh"
app="$STAGE_DIR/Mavericks WezTerm.app"
"$PYTHON" - "$app" "$SOURCE_DIR/.tag" <<'PY'
import os, plistlib, sys
app, tag = sys.argv[1:]
with open(os.path.join(app, 'Contents', 'Info.plist'), 'rb') as stream:
    info = plistlib.load(stream) if hasattr(plistlib, 'load') else plistlib.readPlist(stream)
assert info['CFBundleIdentifier'] == 'dev.mavergreen.wezterm'
assert info['CFBundleName'] == 'Mavericks WezTerm'
assert info['CFBundleDisplayName'] == 'Mavericks WezTerm'
assert info['CFBundleExecutable'] == 'wezterm-gui'
assert info['LSMinimumSystemVersion'] == '10.9'
assert info['MavergreenBuildIdentity'] == open(tag).read().strip()
for name in ['wezterm-gui', 'wezterm', 'wezterm-mux-server']:
    assert os.access(os.path.join(app, 'Contents', 'MacOS', name), os.X_OK)
for path in ['Resources/terminal.icns', 'Resources/terminfo', 'Resources/wezterm.sh', 'Resources/LICENSE.md']:
    assert os.path.exists(os.path.join(app, 'Contents', path)), path
PY
mkdir -p "$WORK_ROOT/app-test-home"
HOME=$WORK_ROOT/app-test-home
XDG_CACHE_HOME=$HOME/cache
XDG_CONFIG_HOME=$HOME/config
XDG_DATA_HOME=$HOME/data
export HOME XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME
(cd / && "$app/Contents/MacOS/wezterm" --skip-config ls-fonts) > "$EVIDENCE_DIR/staged-sibling-gui.txt"
grep -F 'Primary font:' "$EVIDENCE_DIR/staged-sibling-gui.txt"
/usr/bin/infocmp -A "$app/Contents/Resources/terminfo" wezterm > "$EVIDENCE_DIR/staged-terminfo.txt"
for name in wezterm-gui wezterm wezterm-mux-server; do
    "$app/Contents/MacOS/$name" --version > "$EVIDENCE_DIR/staged-$name-version.txt"
    grep -F "$(tr -d '\n' < "$SOURCE_DIR/.tag")" "$EVIDENCE_DIR/staged-$name-version.txt"
done
echo 'PASS: staged product bundle identity/resources and all executable versions'
