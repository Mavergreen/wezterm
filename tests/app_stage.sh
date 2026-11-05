#!/bin/sh
# platform: macOS-only -- checks bundle identity, resources and staged executables
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
release=$TARGET_DIR/x86_64-apple-darwin/release
[ -x "$release/wezterm-gui" ] || { echo 'GUI not built; app staging needs actual binaries'; exit 77; }
grep -F 'Finished `release` profile' "$EVIDENCE_DIR/build.log" > /dev/null ||
    { echo 'FAIL: the last native build did not use the release profile'; exit 1; }
assert_run 2 sh "$ROOT/build/stage-app.sh" --bogus
assert_output 'usage: stage-app.sh [--acceptance]'
app="$STAGE_DIR/Mavericks WezTerm.app"
tag=$(tr -d '\n' < "$SOURCE_DIR/.tag")
key=$(comparison_key "$tag")
upstream="$SOURCE_DIR/assets/macos/WezTerm.app/Contents/Info.plist"
info() {
    "$PYTHON" - "$app" "$tag" "$key" "$upstream" "$1" "$TEST_ROOT/product-info.plist" <<'PY'
import os, plistlib, shutil, sys
app, tag, key, upstream, flavour, saved = sys.argv[1:]
def load(path):
    with open(path, 'rb') as stream:
        return plistlib.load(stream) if hasattr(plistlib, 'load') else plistlib.readPlist(stream)
path = os.path.join(app, 'Contents', 'Info.plist')
info, original = load(path), load(upstream)
def expect(name, value):
    if info.get(name) != value:
        sys.exit('FAIL: %s Info.plist %s is %r, not %r' % (flavour, name, info.get(name), value))
expect('CFBundleIdentifier', 'dev.mavergreen.wezterm')
expect('CFBundleName', 'Mavericks WezTerm')
expect('CFBundleDisplayName', 'Mavericks WezTerm')
expect('CFBundleExecutable', 'wezterm-gui')
expect('LSMinimumSystemVersion', '10.9')
expect('CFBundleShortVersionString', tag)
expect('CFBundleVersion', key)
expect('MavergreenBuildIdentity', tag)
if flavour == 'product':
    if not original.get('CFBundleDocumentTypes'):
        sys.exit('FAIL: upstream Info.plist declares no CFBundleDocumentTypes to keep')
    expect('CFBundleDocumentTypes', original['CFBundleDocumentTypes'])
    shutil.copyfile(path, saved)
else:
    if 'CFBundleDocumentTypes' in info:
        sys.exit('FAIL: the acceptance bundle still declares CFBundleDocumentTypes')
    product = load(saved)
    del product['CFBundleDocumentTypes']
    if info != product:
        sys.exit('FAIL: the acceptance bundle differs from the product in more than its document types')
for name in ['wezterm-gui', 'wezterm', 'wezterm-mux-server', 'strip-ansi-escapes']:
    if not os.access(os.path.join(app, 'Contents', 'MacOS', name), os.X_OK):
        sys.exit('FAIL: %s is not executable' % name)
for name in ['Resources/terminal.icns', 'Resources/terminfo', 'Resources/wezterm.sh', 'Resources/LICENSE.md']:
    if not os.path.exists(os.path.join(app, 'Contents', name)):
        sys.exit('FAIL: missing ' + name)
PY
}
staged_executables() {
    for name in wezterm-gui wezterm wezterm-mux-server strip-ansi-escapes; do
        cmp -s "$release/$name" "$app/Contents/MacOS/$name" ||
            { echo "FAIL: staged $name is not the release build's"; exit 1; }
    done
}
sh "$ROOT/build/stage-app.sh"
staged_executables
info product
assert_run 1 "$PYTHON" "$ROOT/build/artifacts.py" verify-acceptance-stage "$WORK_ROOT" "$ROOT" "$app"
assert_output 'stage it with build/stage-app.sh --acceptance'
pass 'the product bundle keeps upstream document types, versions itself, and is refused for GUI acceptance'
sh "$ROOT/build/stage-app.sh" --acceptance
staged_executables
info acceptance
"$PYTHON" "$ROOT/build/artifacts.py" verify-acceptance-stage "$WORK_ROOT" "$ROOT" "$app"
pass 'the acceptance bundle differs from the product only by dropping its document types'
sh "$ROOT/build/stage-app.sh"
info product
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
stripped=$(printf 'A\033[1mB\033[0mC\n' | "$app/Contents/MacOS/strip-ansi-escapes")
[ "$stripped" = ABC ] || { echo "FAIL: staged strip-ansi-escapes printed $stripped"; exit 1; }
pass 'staged release executables, bundle identity/resources and all executable versions'
