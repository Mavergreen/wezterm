#!/bin/sh
# platform: macOS-only -- stages the actual native product without installing it
#   usage: stage-app.sh [--acceptance]
#          Stages "Mavericks WezTerm.app" from the release build: the product bundle, or with
#          --acceptance the private bundle for GUI acceptance, which differs only by declaring no
#          document types. build/build-native.sh stages the product with --from-builder.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
. "$REPO_ROOT/build/msc.sh"
own_lock=false
candidate=
flavour=product
case "$*" in
    '') ;;
    --acceptance) flavour=acceptance ;;
    --from-builder) ;;
    *) printf 'usage: stage-app.sh [--acceptance]\n' >&2; exit 2 ;;
esac
if [ "${1:-}" = --from-builder ]; then
    own_work_root
    [ -d "$WORK_ROOT/.lock" ] && [ -f "$WORK_ROOT/.lock/stage-owner" ] || fail 'builder lock missing'
    IFS= read -r owner_pid < "$WORK_ROOT/.lock/stage-owner"
    [ "$owner_pid" = "$PPID" ] || fail 'staging is not a child of the lock owner'
else
    lock_recipe
    own_lock=true
fi
cleanup() {
    if [ -n "$candidate" ] && [ -f "$candidate/.owner" ]; then
        [ "$(cat "$candidate/.owner")" = "$REPO_ROOT" ] || return 1
        rm -rf "$candidate"
    fi
    if [ "$own_lock" = true ]; then rmdir "$WORK_ROOT/.lock"; fi
}
trap cleanup EXIT
"$PYTHON" "$REPO_ROOT/build/artifacts.py" gui-idle "$WORK_ROOT" "$REPO_ROOT"
sh "$REPO_ROOT/build/prepare.sh" --verify
"$PYTHON" "$REPO_ROOT/build/artifacts.py" verify-build "$WORK_ROOT" "$REPO_ROOT"
[ ! -L "$STAGE_DIR" ] || fail 'foreign stage symlink'
mkdir -p "$STAGE_DIR"
app="$STAGE_DIR/Mavericks WezTerm.app"
backup="$STAGE_DIR/.mavergreen-app-backup"
[ ! -e "$backup" ] && [ ! -L "$backup" ] || fail 'preserved staging backup needs recovery before replacement'
if [ -e "$app" ] || [ -L "$app" ]; then
    [ ! -L "$app" ] && [ -f "$app/.mavergreen-owner" ] || fail 'refusing to replace a foreign bundle'
    [ "$(cat "$app/.mavergreen-owner")" = "$REPO_ROOT" ] || fail 'foreign bundle owner'
fi
candidate=$(mktemp -d "$WORK_ROOT/stage-build.XXXXXX")
printf '%s\n' "$REPO_ROOT" > "$candidate/.owner"
new="$candidate/Mavericks WezTerm.app"
mkdir "$new"
cp -R "$SOURCE_DIR/assets/macos/WezTerm.app/Contents" "$new/Contents"
mkdir -p "$new/Contents/MacOS" "$new/Contents/Resources/terminfo"
for name in wezterm-gui wezterm wezterm-mux-server strip-ansi-escapes; do
    cp -p "$TARGET_DIR/x86_64-apple-darwin/release/$name" "$new/Contents/MacOS/$name"
done
cp -p "$SOURCE_DIR/assets/shell-integration/"* "$new/Contents/Resources/"
cp -p "$SOURCE_DIR/LICENSE.md" "$new/Contents/Resources/LICENSE.md"
cp -R "$SOURCE_DIR/assets/shell-completion" "$new/Contents/Resources/shell-completion"
/usr/bin/tic -x -e wezterm -o "$new/Contents/Resources/terminfo" "$SOURCE_DIR/termwiz/data/wezterm.terminfo"
version=$(tr -d '\n' < "$SOURCE_DIR/.tag")
"$PYTHON" - "$new/Contents/Info.plist" "$version" "$(comparison_key "$version")" "$flavour" <<'PY'
import plistlib, sys
path, version, key, flavour = sys.argv[1:]
with open(path, 'rb') as stream:
    data = plistlib.load(stream) if hasattr(plistlib, 'load') else plistlib.readPlist(stream)
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Sparkle updater" -- the human
#       version is CFBundleShortVersionString, and CFBundleVersion is its dotted-numeric comparison key.
data.update(CFBundleIdentifier='dev.mavergreen.wezterm', CFBundleName='Mavericks WezTerm',
            CFBundleDisplayName='Mavericks WezTerm', CFBundleExecutable='wezterm-gui',
            LSMinimumSystemVersion='10.9', MavergreenBuildIdentity=version,
            CFBundleShortVersionString=version, CFBundleVersion=key)
data['CFBundleGetInfoString'] = 'Mavericks WezTerm ' + version
# spec: PORT.md "Staging and local acceptance" -- the private acceptance bundle must not compete for
#       installed file-type associations; the product keeps upstream's.
if flavour == 'acceptance':
    del data['CFBundleDocumentTypes']
with open(path, 'wb') as stream:
    if hasattr(plistlib, 'dump'):
        plistlib.dump(data, stream)
    else:
        plistlib.writePlist(data, stream)
PY
printf '%s\n' "$REPO_ROOT" > "$new/.mavergreen-owner"
"$PYTHON" "$REPO_ROOT/build/artifacts.py" record-stage "$WORK_ROOT" "$REPO_ROOT" "$new"
"$PYTHON" "$REPO_ROOT/build/artifacts.py" verify-stage "$WORK_ROOT" "$REPO_ROOT" "$new"
if [ -d "$app" ]; then mv "$app" "$backup"; fi
if ! mv "$new" "$app"; then
    if [ -d "$backup" ] && [ ! -e "$app" ]; then mv "$backup" "$app"; fi
    fail 'staging publication failed; previous bundle restored or preserved for recovery'
fi
"$PYTHON" "$REPO_ROOT/build/artifacts.py" verify-stage "$WORK_ROOT" "$REPO_ROOT" "$app"
if [ -d "$backup" ]; then
    [ "$(cat "$backup/.mavergreen-owner")" = "$REPO_ROOT" ] || fail 'foreign backup; preserving it'
    rm -rf "$backup"
fi
printf 'Staged: %s\n' "$app"
