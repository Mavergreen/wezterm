#!/bin/sh
# platform: host-agnostic
. "$(dirname "$0")/support/common.sh"
. "$ROOT/build/msc.sh"
fixture=$TEST_ROOT/checkout
mkdir -p "$fixture/components/wezterm"
cp -R "$ROOT/build" "$fixture/"
pin=$fixture/components/wezterm/version
write_pin() {
    grep -v '^COMMITTED=' "$ROOT/components/wezterm/version" > "$pin"
    if [ "$#" -gt 0 ]; then printf 'COMMITTED=%s\n' "$1" >> "$pin"; fi
}

write_pin 20261026.072628
assert_run 0 sh "$fixture/build/derive-upstream-version.sh"
[ "$(cat "$fixture/UPSTREAM_VERSION")" = 20261026.072628 ] || fail 'UPSTREAM_VERSION must be the pinned commit time COMMITTED, verbatim'
pass 'derive writes the pinned commit time as UPSTREAM_VERSION'

for bad in 2026-10-26 20261026 20261026.72628 20261026.0726280 '' 'x20261026.072628'; do
    rm -f "$fixture/UPSTREAM_VERSION"
    write_pin "$bad"
    assert_run 1 sh "$fixture/build/derive-upstream-version.sh"
    assert_output 'COMMITTED'
    assert_output 'components/wezterm/version'
    [ ! -e "$fixture/UPSTREAM_VERSION" ] || fail "malformed COMMITTED '$bad' still wrote UPSTREAM_VERSION"
done
write_pin
assert_run 1 sh "$fixture/build/derive-upstream-version.sh"
assert_output 'COMMITTED'
[ ! -e "$fixture/UPSTREAM_VERSION" ] || fail 'a pin without COMMITTED still wrote UPSTREAM_VERSION'
pass 'malformed or missing COMMITTED is rejected by name'

grep -F 'components/wezterm/version' "$ROOT/build/derive-upstream-version.sh" >/dev/null &&
    grep -F 'UPSTREAM_VERSION' "$ROOT/build/derive-upstream-version.sh" >/dev/null ||
    fail 'release-state.sh accepts a derived upstream only when the derive script names both the pin and UPSTREAM_VERSION'
pass 'derive script names the pin it reads and the file it writes'

rm -rf "$fixture/components"
cp -R "$ROOT/components" "$fixture/"
assert_run 0 sh "$fixture/build/derive-upstream-version.sh"
pass 'the committed pin carries a well-formed COMMITTED'

write_pin 20261026.072628
assert_run 0 sh "$fixture/build/derive-upstream-version.sh"
assert_run 0 env MAVERICKS_TAGS= sh "$fixture/build/version.sh" auto
assert_output 'FULL=20261026.072628-mavericks.1'
. "$SHIPYARD_SCRIPTS/lib/vercmp.sh"
[ "$(comparison_key "$(sed -n 's/^FULL=//p' "$TEST_ROOT/output")")" = 20261026.072628.1 ] || fail 'comparison key must be dotted-numeric so Sparkle and the family comparator can order snapshots'
pass 'snapshot version and comparison key'
