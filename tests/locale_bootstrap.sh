#!/bin/sh
# platform: macOS-only -- runs the release executables with no LANG, as Finder, launchd and ssh start them
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
bin=$TARGET_DIR/x86_64-apple-darwin/release
for name in wezterm wezterm-gui wezterm-mux-server; do
    [ -x "$bin/$name" ] || { echo "not built; $name is missing"; exit 77; }
done
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "the no-LANG startup test"
mkdir "$TEST_ROOT/home"
bare() { env -i PATH=/usr/bin:/bin HOME="$TEST_ROOT/home" "$@"; }
for name in wezterm wezterm-gui wezterm-mux-server; do
    assert_run 0 bare "$bin/$name" --version
    assert_output "$(upstream_version)-mavericks."
done
pass 'the CLI, GUI and mux report their version when started with no LANG'
# spec: PORT.md "Locale without LANG" -- a subcommand that hands over to wezterm-gui gets there with no LANG
assert_run 0 bare "$bin/wezterm" --skip-config ls-fonts
assert_output 'Primary font:'
pass 'wezterm ls-fonts, started with no LANG, hands over to wezterm-gui'
# spec: PORT.md "Locale without LANG" -- the bootstrap exports a UTF-8 LANG its children inherit
bare /usr/bin/script -q "$TEST_ROOT/transcript" "$bin/wezterm" --skip-config record \
    -o "$TEST_ROOT/recording.cast" -- /bin/sh -c 'printf "LANG=[%s]\n" "$LANG"' > "$TEST_ROOT/driver.log" 2>&1 ||
    { cat "$TEST_ROOT/driver.log" >&2; fail 'wezterm record failed with no LANG'; }
lang=$("$PYTHON" - "$TEST_ROOT/recording.cast" <<'PY'
import json, re, sys
lines = open(sys.argv[1]).readlines()
output = ''.join(item[2] for item in (json.loads(line) for line in lines[1:]) if item[1] == 'o')
found = re.search(r'LANG=\[([^\]]*)\]', output)
print(found.group(1) if found else '')
PY
)
printf '%s\n' "$lang" | grep -E '^[a-z]{2,3}(_[A-Z]{2})?\.UTF-8$' > /dev/null ||
    fail "a child of wezterm started with no LANG sees LANG=[$lang], not a UTF-8 locale"
pass "a child of wezterm started with no LANG inherits LANG=$lang"
