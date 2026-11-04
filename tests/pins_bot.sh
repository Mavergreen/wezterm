#!/bin/sh
# platform: host-agnostic
#   usage: sh tests/pins_bot.sh
#          scripts/pins-bot.sh's decisions, .github/workflows/pins-bot.yml's shape and .github/renovate.json's
#          managers, offline. A fixture repository with this repo's pins stands in for Renovate's branch,
#          and a stub stands in for scripts/pin-source-tarballs.sh. Exits 77 without a git that runs.
. "$(dirname "$0")/support/common.sh"
# platform: OS X 10.9's /usr/bin/git is a Command Line Tools stub, there whether or not they are installed.
git --version >/dev/null 2>&1 || { echo 'no git that runs; the pins bot runs in CI'; exit 77; }
PYTHON=${PYTHON:-python}
T=$TEST_ROOT
R=$T/repo
mkdir -p "$R/scripts" "$R/components/wezterm" "$R/components/rust"
cp "$ROOT/scripts/pins-bot.sh" "$R/scripts/"
cp "$ROOT/components/wezterm/version" "$ROOT/components/wezterm/gitlinks.json" "$R/components/wezterm/"
cp "$ROOT/components/rust/version" "$R/components/rust/"
PIN=$R/components/wezterm/version
GL=$R/components/wezterm/gitlinks.json
gitc() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
git init -q "$R"; gitc add -A; gitc commit -qm main; gitc branch -m main 2>/dev/null || :
[ "$(git -C "$R" rev-parse --abbrev-ref HEAD)" = main ] || gitc checkout -q -b main
bot() { (cd "$R" && sh scripts/pins-bot.sh "$@"); }
edit() { sed "s|^$1=.*|$1=$2|" "$PIN" > "$T/p" && cat "$T/p" > "$PIN"; }
D1=1111111111111111111111111111111111111111
E=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee

gitc checkout -q -b renovate/rust
echo 1.99.2-mavericks.1 > "$R/components/rust/version"; gitc commit -qam rust
if bot moved main > "$T/out"; then fail "a Rust bump counted as a moved DIGEST: $(cat "$T/out")"; fi
gitc checkout -q -b renovate/hand main; edit SHA256 "$E"; gitc commit -qam 'a hand edit beside DIGEST'
if bot moved main > "$T/out"; then fail "an edit beside an unmoved DIGEST counted as a moved DIGEST: $(cat "$T/out")"; fi
gitc checkout -q main; edit DIGEST 3333333333333333333333333333333333333333; gitc commit -qam later
gitc checkout -q renovate/rust
if bot moved main > "$T/out"; then fail "main's own later DIGEST move counted as this branch's: $(cat "$T/out")"; fi
gitc checkout -q -b renovate/wezterm main~1; edit DIGEST "$D1"; gitc commit -qam wezterm
bot moved main > "$T/out" || fail 'a moved DIGEST was not seen'
[ "$(cat "$T/out")" = "-DIGEST=$(sed -n 's/^DIGEST=//p' "$ROOT/components/wezterm/version")
+DIGEST=$D1" ] ||
    fail "moved must print the DIGEST lines of this branch's own change alone: $(cat "$T/out")"
mkdir -p "$T/faildiff"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = diff ] && { echo "fatal: no diff today" >&2; exit 128; }; done\nexec "%s" "$@"\n' \
    "$(command -v git)" > "$T/faildiff/git"; chmod +x "$T/faildiff/git"
rc=0; (PATH="$T/faildiff:$PATH"; bot moved main) > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" -eq 2 ] && [ ! -s "$T/out" ] || fail "moved with a failed git diff must exit 2 (cannot tell), not 1 (did not move): exit $rc"
rc=0; bot moved nosuchref > "$T/out" 2> "$T/err" || rc=$?
[ "$rc" -eq 2 ] || fail "moved with no merge base must exit 2, got $rc"
pass 'moved sees a DIGEST moved by this branch alone, and says when git cannot tell'

gitc checkout -q main
expected=$(. "$ROOT/components/wezterm/version" && echo "DIGEST=$DIGEST SHA256=$SHA256 COMMITTED=$COMMITTED FREETYPE2_DIGEST=$FREETYPE2_DIGEST FREETYPE2_SHA256=$FREETYPE2_SHA256 LIBPNG_DIGEST=$LIBPNG_DIGEST LIBPNG_SHA256=$LIBPNG_SHA256 ZLIB_DIGEST=$ZLIB_DIGEST ZLIB_SHA256=$ZLIB_SHA256 HARFBUZZ_DIGEST=$HARFBUZZ_DIGEST HARFBUZZ_SHA256=$HARFBUZZ_SHA256")
gitc checkout -q -- components
cp "$ROOT/components/wezterm/version" "$PIN"
[ "$(bot values)" = "$expected" ] || fail "values must hand on the checked pins and the DIGEST they were checked for: $(bot values)"
for bad in 'SHA256=abc' 'COMMITTED=2026-10-26' 'ZLIB_DIGEST=51b7f2'; do
    edit "${bad%%=*}" "${bad#*=}"
    if bot values > /dev/null 2> "$T/err"; then fail "values handed on $bad"; fi
    grep -F "${bad%%=*}" "$T/err" > /dev/null || fail "values did not name ${bad%%=*}: $(cat "$T/err")"
    cp "$ROOT/components/wezterm/version" "$PIN"
done
pass 'values hands on the eleven pins and refuses a malformed one'

# shellcheck disable=SC2086
[ "$(bot apply $expected)" = unchanged ] || fail "apply of the committed values must change nothing: $(diff "$ROOT/components/wezterm/version" "$PIN"; diff "$ROOT/components/wezterm/gitlinks.json" "$GL")"
cmp -s "$ROOT/components/wezterm/gitlinks.json" "$GL" || fail 'apply must write gitlinks.json byte for byte as committed'
moved=$(printf '%s\n' "$expected" | sed -e "s/ SHA256=[0-9a-f]*/ SHA256=$E/" -e "s/ ZLIB_DIGEST=[0-9a-f]*/ ZLIB_DIGEST=$D1/")
# shellcheck disable=SC2086
[ "$(bot apply $moved)" = changed ] || fail 'apply did not say changed'
[ "$(diff "$ROOT/components/wezterm/version" "$PIN" | grep -c '^>')" = 2 ] &&
    grep -qx "SHA256=$E" "$PIN" && grep -qx "ZLIB_DIGEST=$D1" "$PIN" ||
    fail "apply must write the given lines and nothing else: $(diff "$ROOT/components/wezterm/version" "$PIN")"
sed "s|\"deps/freetype/zlib\": \"[0-9a-f]*\"|\"deps/freetype/zlib\": \"$D1\"|" "$ROOT/components/wezterm/gitlinks.json" > "$T/gl"
cmp -s "$T/gl" "$GL" || fail "apply must regenerate gitlinks.json from the pins: $(diff "$T/gl" "$GL")"
[ -z "$(ls -A "$R/components/wezterm" | grep -vx -e version -e gitlinks.json)" ] || fail "apply left $(ls -A "$R/components/wezterm")"
pass 'apply writes the given pins and gitlinks.json, and nothing else'

cp "$PIN" "$T/now.pin"; cp "$GL" "$T/now.json"
other=$(printf '%s\n' "$moved" | sed "s/^DIGEST=[0-9a-f]*/DIGEST=$D1/")
dup="$moved ZLIB_DIGEST=$D1"
missing=$(printf '%s\n' "$moved" | sed 's/ HARFBUZZ_SHA256=[0-9a-f]*//')
unknown="$moved EXTRA_SHA256=$E"
key_inject="$moved "'$(touch${IFS}'"$T"'/pwned)_SHA256='"$E"
short=$(printf '%s\n' "$moved" | sed 's/ LIBPNG_SHA256=[0-9a-f]*/ LIBPNG_SHA256=abc/')
local_time=$(printf '%s\n' "$moved" | sed 's/ COMMITTED=[0-9.]*/ COMMITTED=2026-10-26T07:26:28Z/')
inj='$(touch${IFS}'"$T"'/pwned)'
inject=$(printf '%s\n' "$moved" | sed 's/ SHA256=[0-9a-f]*/ SHA256=@/')
inject="${inject%%@*}$inj${inject#*@}"
for case in other dup missing unknown key_inject short local_time inject; do
    eval "args=\$$case"
    # shellcheck disable=SC2086
    if bot apply $args > /dev/null 2> "$T/err"; then fail "apply accepted the $case values"; fi
    cmp -s "$T/now.pin" "$PIN" && cmp -s "$T/now.json" "$GL" || fail "a refused apply ($case) wrote"
done
[ ! -e "$T/pwned" ] || fail 'apply ran a value'
bot apply $other > /dev/null 2> "$T/err" || :
grep -F 'checked for' "$T/err" > /dev/null || fail "apply must say the values were checked for another commit: $(cat "$T/err")"
pass 'apply refuses values for another commit, a missing, repeated or unknown key, or a malformed value, writing nothing'

gitc checkout -q -- components
cat > "$R/scripts/pin-source-tarballs.sh" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
exit "$STUB_FILL"
STUB
fill() {
    : > "$T/calls"
    rc=0
    (cd "$R" && env STUB_LOG="$T/calls" STUB_FILL="$2" sh scripts/pins-bot.sh fill "$1") > "$T/out" 2> "$T/err" || rc=$?
}
gitc checkout -q renovate/wezterm
fill main 0
[ "$rc" -eq 0 ] && [ ! -s "$T/out" ] && [ "$(cat "$T/calls")" = --fill ] || fail "fill, current: exit $rc, handed on [$(cat "$T/out")], calls [$(cat "$T/calls")]"
fill main 3
[ "$rc" -eq 0 ] && [ "$(cat "$T/out")" = "$(cd "$R" && sh scripts/pins-bot.sh values)" ] ||
    fail "fill, stale: exit $rc, handed on [$(cat "$T/out")]: $(cat "$T/err")"
for status in 1 2 130 143 7; do
    fill main "$status"
    [ "$rc" -eq 1 ] && [ ! -s "$T/out" ] || fail "fill, --fill exit $status: exit $rc, handed on [$(cat "$T/out")]"
done
grep -F 'exited 7' "$T/err" > /dev/null || fail "fill must name --fill's status: $(cat "$T/err")"
fill nosuchref 3
[ "$rc" -eq 1 ] && [ ! -s "$T/out" ] && [ ! -s "$T/calls" ] || fail "fill, no merge base: exit $rc, calls [$(cat "$T/calls")]"
(PATH="$T/faildiff:$PATH"; fill main 3; [ "$rc" -eq 1 ] && [ ! -s "$T/out" ] && [ ! -s "$T/calls" ]) ||
    fail 'fill, a failed git diff, must fail rather than read as DIGEST did not move'
gitc checkout -q renovate/rust
fill main 3
[ "$rc" -eq 0 ] && [ ! -s "$T/out" ] && [ ! -s "$T/calls" ] || fail "fill, a Rust bump: exit $rc, handed on [$(cat "$T/out")], calls [$(cat "$T/calls")]"
pass 'fill hands on values only when DIGEST moved and --fill exits 3, and fails on any other status'

W=$ROOT/.github/workflows/pins-bot.yml
grep -qx 'permissions: {}' "$W" || fail 'pins-bot.yml must grant no default permission'
awk '/^  pins:$/ { j = "pins" } /^  push:$/ { j = "push" } j { print j ": " $0 }' "$W" > "$T/jobs"
grep -qx 'pins:       contents: read' "$T/jobs" || fail "the pins job must read only"
if grep '^pins:' "$T/jobs" | grep -q 'write\|git push\|gh workflow'; then fail 'the pins job can write'; fi
if grep '^push:' "$T/jobs" | grep -q 'pin-source-tarballs\|fill\|curl\|install@'; then fail "the push job touches upstream's tarballs"; fi
[ "$(grep -A1 '^push:     permissions:$' "$T/jobs" | tail -1)" = 'push:       contents: read' ] &&
    ! grep '^push:' "$T/jobs" | grep -q 'contents: write$\|actions: write' || fail "the push job's GITHUB_TOKEN must read only"
grep -qx 'push:         uses: actions/create-github-app-token@v3' "$T/jobs" &&
    grep -qx 'push:           client-id: ${{ vars.PINS_BOT_CLIENT_ID }}' "$T/jobs" &&
    grep -qx 'push:           private-key: ${{ secrets.PINS_BOT_PRIVATE_KEY }}' "$T/jobs" &&
    [ "$(grep -c '^push: *permission-' "$T/jobs")" = 1 ] && grep -qx 'push:           permission-contents: write' "$T/jobs" ||
    fail "the push job must mint the pins-bot App's token for contents: write alone"
grep -qx 'push:           token: ${{ steps.app.outputs.token }}' "$T/jobs" || fail "the push job's checkout must hold the App's token, so its push starts the build"
grep -qxF "  group: pins-bot-\${{ github.ref }}\${{ github.actor == 'mavergreen-pins-bot[bot]' && format('-{0}', github.run_id) || '' }}" "$W" &&
    grep -qxF '  cancel-in-progress: true' "$W" &&
    grep -qxF "pins:     if: github.actor != 'mavergreen-pins-bot[bot]'" "$T/jobs" ||
    fail "the run the bot's own push starts must neither cancel the run that pushed nor check again"
if grep -q 'gh workflow run\|GH_TOKEN\|github.token' "$W"; then fail 'the workflow must not dispatch a run or write with GITHUB_TOKEN'; fi
grep -qF "user.email='342268518+mavergreen-pins-bot[bot]@users.noreply.github.com'" "$W" ||
    fail "the bot must commit as the App's bot user"
grep -qx 'pins:           pins="$(sh scripts/pins-bot.sh fill origin/main)"' "$T/jobs" || fail 'the pins job must decide by pins-bot.sh fill'
grep -qx 'push:           applied="$(sh scripts/pins-bot.sh apply $PINS)"' "$T/jobs" || fail 'a refused apply must fail the push job (an assignment, which set -e sees)'
grep -q '^push: .*components/wezterm/version components/wezterm/gitlinks.json$' "$T/jobs" || fail 'the push job must commit the pin and gitlinks.json'
invariants() {
    _on=$(awk '/^on:/ { on = 1; next } on && /^[^ #]/ { exit } on && !/^ *(#.*)?$/ { print }' "$1")
    [ "$_on" = "  push:
    branches: ['renovate/**']" ] || { echo "on: is not a push to renovate/** alone: [$_on]"; return 1; }
    _run=$(awk 'function ind(l) { match(l, /^ */); return RLENGTH }
        r && (/^ *$/ || ind($0) > ri) { if (index($0, "${{")) print NR ": " $0; next }
        { r = 0 }
        /^ *(- )?run:/ { ri = ind($0); r = 1; if (index($0, "${{")) print NR ": " $0 }' "$1")
    [ -z "$_run" ] || { echo "a run: block holds \${{ }}: $_run"; return 1; }
    awk '/^  pins:$/ { j = "pins" } /^  push:$/ { j = "push" } j { print j ": " $0 }' "$1" > "$T/inv-jobs"
    grep -q '^pins:           persist-credentials: false$' "$T/inv-jobs" || { echo "the pins job's checkout persists its credentials"; return 1; }
    grep -qx 'push:     needs: pins' "$T/inv-jobs" || { echo 'the push job does not need the pins job'; return 1; }
}
invariants "$W" > "$T/inv" || fail "pins-bot.yml: $(cat "$T/inv")"
mutant() {
    sed "$3" "$W" > "$T/mutant.yml"
    if cmp -s "$W" "$T/mutant.yml"; then fail "mutant '$1' changed nothing"; fi
    if invariants "$T/mutant.yml" > "$T/inv"; then fail "the invariants passed a workflow with $1"; fi
    grep -qF "$2" "$T/inv" || fail "the invariants, $1: said [$(cat "$T/inv")]"
}
mutant 'a pull_request_target trigger' 'on: is not a push' 's/^  push:$/  pull_request_target:\
  push:/'
mutant 'another branch' 'on: is not a push' "s|'renovate/\*\*'|'**'|"
mutant '${{ }} in a run: block' 'a run: block holds' 's/^          set -eu$/          echo "${{ github.event.head_commit.message }}"/'
mutant 'the pins job keeping its credentials' 'persists its credentials' 's/persist-credentials: false/persist-credentials: true/'
mutant 'a push job that needs nothing' 'does not need the pins job' '/^    needs: pins$/d'
pass "the pins job reads upstream with no write token, the push job writes with the App's token and no upstream byte"

"$PYTHON" - "$ROOT/.github/renovate.json" "$ROOT" <<'PY' || fail 'renovate.json (above)'
import json, os, re, sys
def js(rx):
    return re.sub(r'\(\?<(?![=!])', '(?P<', rx)
config = json.load(open(sys.argv[1]))
root = sys.argv[2]
problems = []
def check(ok, message):
    if not ok:
        problems.append(message)
check(config.get('extends') == ['github>Mavergreen/shipyard'], 'extends the shared preset alone')
check('342268518+mavergreen-pins-bot[bot]@users.noreply.github.com' in config.get('gitIgnoredAuthors', []),
      "gitIgnoredAuthors names the pins bot, so its commit does not mark Renovate's branch as edited")
for key in ('ignoreTests', 'automerge', 'groupName', 'separateMajorMinor'):
    check(key not in config, 'restates %s, which the shared preset owns' % key)
def owners(path):
    found = []
    for manager in config.get('customManagers', []):
        if any(re.search(js(p.strip('/')), path) for p in manager.get('managerFilePatterns', [])):
            found.append(manager)
    return found
pin = 'components/wezterm/version'
text = open(os.path.join(root, pin)).read()
managers = owners(pin)
check(len(managers) == 1, '%s has one manager, not %d' % (pin, len(managers)))
if managers:
    m = managers[0]
    match = re.search(js(m['matchStrings'][0]), text)
    digest = re.search(r'^DIGEST=(\S+)$', text, re.M).group(1)
    check(m.get('datasourceTemplate') == 'git-refs', 'the WezTerm pin is a git-refs dependency')
    check(match is not None and match.group('currentDigest') == digest and match.group('currentValue') == 'main'
          and match.group('packageName') == 'https://github.com/wezterm/wezterm',
          'the WezTerm manager captures REPO, REF=main and DIGEST from the pin')
    check(m.get('depNameTemplate') == 'wezterm/wezterm', 'the WezTerm dependency is named wezterm/wezterm')
for short, dep, shape in (('rust', 'Mavergreen/rust', 'mavericks'), ('clang22', 'Mavergreen/clang-22', 'mavericks'),
                          ('make', 'Mavergreen/make', 'mavericks'), ('longboat', 'Mavergreen/longboat', 'date')):
    path = 'components/%s/version' % short
    value = open(os.path.join(root, path)).read().strip()
    managers = owners(path)
    check(len(managers) == 1, '%s has one manager, not %d' % (path, len(managers)))
    if not managers:
        continue
    m = managers[0]
    match = re.search(js(m['matchStrings'][0]), open(os.path.join(root, path)).read(), re.M)
    check(match is not None and match.group('currentValue') == value, '%s: the manager captures %s' % (path, value))
    check(m.get('depNameTemplate') == dep and m.get('datasourceTemplate') == 'github-releases', '%s is %s releases' % (path, dep))
    vt = m.get('versioningTemplate', '')
    vm = re.match(js(vt[len('regex:'):]) + '$', value) if vt.startswith('regex:') else None
    tail = value.rsplit('-mavericks.', 1)[-1] if shape == 'mavericks' else value.split('.')[-1]
    check(vm is not None and tail in [v for k, v in vm.groupdict().items() if k in ('minor', 'patch', 'build')],
          '%s: the versioning compares %s, or every release of one upstream compares equal' % (path, tail))
check(not owners('components/recaulk/version'), 'the shared preset already manages components/recaulk/version')
scheduled = [r for r in config.get('packageRules', []) if 'schedule' in r]
check(len(scheduled) == 1 and scheduled[0].get('matchDepNames') == ['wezterm/wezterm']
      and scheduled[0].get('schedule') == ['* 4 * * 1'] and set(scheduled[0]) <= {'description', 'matchDepNames', 'schedule', 'prBodyNotes'},
      'one schedule, Mondays 04:00-05:00 UTC, on the WezTerm snapshot alone')
for r in config.get('packageRules', []):
    check(bool((r.get('description') or '').strip()), 'packageRule %s has no description' % r.get('matchDepNames'))
for p in problems:
    sys.stderr.write('renovate.json: %s\n' % p)
sys.exit(1 if problems else 0)
PY
pass 'renovate.json tracks the snapshot weekly and each Mavergreen pin with versioning that compares its build'
