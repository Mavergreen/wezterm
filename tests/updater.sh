#!/bin/sh
# platform: macOS-only -- builds the Sparkle updater with clang22 and reads the bundle with llvm-otool
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$ROOT/build/build-updater.sh" ] || fail 'build/build-updater.sh is missing'
[ -f "$WORK_ROOT/prepared.json" ] || { echo 'not prepared; the updater takes its icon from the prepared source'; exit 77; }
feed=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" feed wezterm 2>/dev/null) ||
    { echo "the shipyard at $SHIPYARD_SCRIPTS does not register wezterm; install shipyard 1.0.677 or later"; exit 77; }
[ "$feed" = https://github.com/Mavergreen/wezterm/releases/latest/download/wezterm.xml ] ||
    fail "shipyard's registry gives wezterm the feed $feed"

assert_run 2 sh "$ROOT/build/build-updater.sh"
assert_run 2 sh "$ROOT/build/build-updater.sh" --out "$TEST_ROOT/a.app" --arch arm64
mkdir "$TEST_ROOT/taken.app"
assert_run 1 sh "$ROOT/build/build-updater.sh" --out "$TEST_ROOT/taken.app"
assert_output 'already exists'
cmake=$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)
assert_run 1 "$cmake" -S "$ROOT" -B "$TEST_ROOT/unprepared" -DWEZTERM_PREPARED_SOURCE="$TEST_ROOT/nowhere"
# platform: CMake wraps a message's lines and normalises the path, so its pieces are matched apart
assert_output 'no prepared WezTerm source at'
assert_output 'nowhere/assets/macos/WezTerm.app/Contents/Resources/terminal.icns'
assert_output 'run build/prepare.sh'
fake=$TEST_ROOT/fake-root/$(basename "$WORK_ROOT")
icon=assets/macos/WezTerm.app/Contents/Resources/terminal.icns
mkdir -p "$fake/source/$(dirname "$icon")"
cp "$SOURCE_DIR/$icon" "$fake/source/$icon"
printf '%s\n' "$ROOT" > "$fake/.owner"
printf '{}\n' > "$fake/prepared.json"
assert_run 1 env MAVERICKS_BUILD_ROOT="$TEST_ROOT/fake-root" sh "$ROOT/build/build-updater.sh" --out "$TEST_ROOT/fake.app"
grep -F 'compiler identification' "$TEST_ROOT/output" && fail 'build-updater.sh configured from a prepared source that did not verify'
[ ! -e "$TEST_ROOT/fake.app" ] || fail 'build-updater.sh built from a prepared source that did not verify'
pass 'build-updater.sh refuses usage errors, an existing app and an unverified prepared source; the configure refuses an unprepared source by name'

app=$TEST_ROOT/out/wezterm-updater.app
# platform: a 10.9 box without the Command Line Tools has stub readers on PATH, so the compat guard the
#           updater's build runs must be handed clang22's.
mkdir "$TEST_ROOT/stubs"
for tool in lipo otool nm strings; do
    printf '#!/bin/sh\necho "stub %s" >&2\nexit 9\n' "$tool" > "$TEST_ROOT/stubs/$tool"
    chmod +x "$TEST_ROOT/stubs/$tool"
done
# platform: 10.9's env has no -u, so a function unsets the readers' variables, rather than a ( )
#           subshell, which 10.9's sh does not handle reliably under set -e; nothing after it needs them
build_with_stub_readers() {
    unset LIPO OTOOL NM STRINGS
    env PATH="$TEST_ROOT/stubs:$PATH" sh "$ROOT/build/build-updater.sh" --out "$app"
}
build_with_stub_readers > "$TEST_ROOT/build.log" 2>&1 ||
    { tail -30 "$TEST_ROOT/build.log"; fail 'build-updater.sh failed'; }
exe=$app/Contents/MacOS/wezterm-updater
[ -x "$exe" ] || fail "no executable at $exe"
version=$(tr -d '\n' < "$SOURCE_DIR/.tag")
"$PYTHON" - "$app" "$version" "$(comparison_key "$version")" "$feed" <<'PY'
import os, plistlib, sys
app, version, key, feed = sys.argv[1:]
with open(os.path.join(app, 'Contents', 'Info.plist'), 'rb') as stream:
    info = plistlib.load(stream) if hasattr(plistlib, 'load') else plistlib.readPlist(stream)
expected = {'CFBundleIdentifier': 'dev.mavergreen.wezterm.updater', 'SUFeedURL': feed,
            'CFBundleExecutable': 'wezterm-updater', 'CFBundleShortVersionString': version,
            'CFBundleVersion': key, 'CFBundleIconFile': 'terminal'}
for name, value in sorted(expected.items()):
    if info.get(name) != value:
        sys.exit('FAIL: updater Info.plist %s is %r, not %r' % (name, info.get(name), value))
PY
cmp -s "$app/Contents/Resources/terminal.icns" \
    "$SOURCE_DIR/assets/macos/WezTerm.app/Contents/Resources/terminal.icns" ||
    fail "the updater's icon is not upstream's terminal.icns from the prepared source"
CL=$(sh "$ROOT/build/tools.sh" tree --root "$TOOL_ROOT" clang22)
"$CL/bin/llvm-otool" -L "$exe" > "$TEST_ROOT/links"
links=$(sed 1d "$TEST_ROOT/links")
[ -n "$links" ] || fail "llvm-otool -L listed nothing for $exe"
printf '%s\n' "$links" | grep -v -E '^[[:space:]]+(/usr/lib/|/System/Library/Frameworks/|@rpath/Sparkle\.framework/)' > "$TEST_ROOT/foreign" &&
    fail "the updater links something beyond the system and Sparkle: $(cat "$TEST_ROOT/foreign")"
grep -i -E 'wezterm|mavergreen' "$TEST_ROOT/links" | grep -v -F "$exe:" &&
    fail 'the updater links the product it updates'
assert_run 0 sh "$ROOT/build/check-compat.sh" --app "$app"
pass "wezterm-updater.app is dev.mavergreen.wezterm.updater on the registry's feed, at this version, with upstream's icon; it links only the system and Sparkle, and passes the compat guard"
