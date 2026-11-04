#!/bin/sh
# platform: host-agnostic
. "$(dirname "$0")/support/common.sh"
git --version >/dev/null 2>&1 || { echo 'no usable git; the snapshot-order guard reads tags and runs in CI'; exit 77; }
repo=$TEST_ROOT/repo
mkdir -p "$repo/components/wezterm"
cp -R "$ROOT/build" "$repo/"
pin=$repo/components/wezterm/version
old_digest=1111111111111111111111111111111111111111
new_digest=2222222222222222222222222222222222222222
write_pin() { printf 'REF=main\nDIGEST=%s\nCOMMITTED=%s\n' "$1" "$2" > "$pin"; }
git init -q "$repo"
write_pin "$old_digest" 20261026.072628
git -C "$repo" add components
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -q -m released
git -C "$repo" tag 20261026.072628-mavericks.1
check() { assert_run "$1" sh "$repo/build/check-snapshot-order.sh" 20261026.072628-mavericks.1; }

write_pin "$new_digest" 20261026.072627
check 1
assert_output 'older'
pass 'an older snapshot is never published as a downgrade'

write_pin "$new_digest" 20261026.072628
check 1
assert_output 'DIGEST'
pass 'a different commit at the same COMMITTED would collide with the released version'

write_pin "$old_digest" 20261026.072628
check 0
pass 'the same commit at the same COMMITTED is a repackage'

write_pin "$new_digest" 20261026.072629
check 0
pass 'a newer snapshot passes'

assert_run 2 sh "$repo/build/check-snapshot-order.sh" v1.2.3
assert_run 2 sh "$repo/build/check-snapshot-order.sh"
assert_run 1 sh "$repo/build/check-snapshot-order.sh" 20261027.000000-mavericks.1
assert_output 'cannot read'
pass 'unusable previous tags are refused'
