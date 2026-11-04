#!/bin/sh
# platform: host-agnostic
. "$(dirname "$0")/support/common.sh"
fixture=$TEST_ROOT/checkout
mkdir -p "$fixture/build" "$fixture/components/wezterm" "$TEST_ROOT/elsewhere"
cp "$ROOT/build/upstream-release-notes-url.sh" "$fixture/build/"
hook=$fixture/build/upstream-release-notes-url.sh
pin=$fixture/components/wezterm/version
digest=0123456789abcdef0123456789abcdef01234567
write_pin() {
    printf 'REPO=https://github.com/wezterm/wezterm.git\nREF=main\nDIGEST=%s\nSHA256=%s\n' "$1" \
        4465c8187a0ac369742043528c6df86b597e1e95eb704ecc054f053a966e8c6e > "$pin"
    if [ "$#" -gt 1 ]; then printf 'COMMITTED=%s\n' "$2" >> "$pin"; fi
    printf 'ZLIB_DIGEST=%s\n' ffffffffffffffffffffffffffffffffffffffff >> "$pin"
}
run_hook() { (cd "$TEST_ROOT/elsewhere" && sh "$hook" "$@"); }

write_pin "$digest" 20261101.123456
assert_run 0 run_hook 20261101.123456
[ "$(cat "$TEST_ROOT/output")" = "https://github.com/wezterm/wezterm/commits/$digest" ] ||
    fail "a new upstream must link the pinned commit's history and print nothing else, got: $(cat "$TEST_ROOT/output")"
pass "the hook links the pinned DIGEST's history, from any working directory"

for other in 20261101.123455 20261101 '20261101.123456 ' x; do
    assert_run 1 run_hook "$other"
    assert_output 'COMMITTED'
    assert_output 'components/wezterm/version'
    if grep -F 'https://' "$TEST_ROOT/output" >/dev/null; then
        fail "a version that is not the pin's COMMITTED ('$other') must link nothing, since DIGEST would be another snapshot's commit"
    fi
done
pass "a version other than the pin's COMMITTED is refused, naming COMMITTED and the pin"

write_pin "$digest"
assert_run 1 run_hook 20261101.123456
assert_output 'COMMITTED'
assert_run 1 run_hook ''
assert_output 'COMMITTED'
write_pin "$digest" 20261101.123456
printf 'DIGEST=%s\n' 89abcdef0123456789abcdef0123456789abcdef >> "$pin"
assert_run 1 run_hook 20261101.123456
assert_output 'DIGEST'
write_pin 0123456789abcdef 20261101.123456
assert_run 1 run_hook 20261101.123456
assert_output 'DIGEST'
write_pin '' 20261101.123456
assert_run 1 run_hook 20261101.123456
assert_output 'DIGEST'
pass "a pin without COMMITTED, or without exactly one full DIGEST, links nothing"

write_pin "$digest" 20261101.123456
assert_run 2 run_hook
assert_output 'usage'
assert_run 2 run_hook 20261101.123456 extra
assert_output 'usage'
pass "the hook takes exactly one upstream version"

committed=$(sed -n 's/^COMMITTED=//p' "$ROOT/components/wezterm/version")
real_digest=$(sed -n 's/^DIGEST=//p' "$ROOT/components/wezterm/version")
assert_run 0 sh "$ROOT/build/upstream-release-notes-url.sh" "$committed"
[ "$(cat "$TEST_ROOT/output")" = "https://github.com/wezterm/wezterm/commits/$real_digest" ] ||
    fail "the committed pin must link its own DIGEST, got: $(cat "$TEST_ROOT/output")"
pass "the committed pin links its own commit"
