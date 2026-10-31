#!/bin/sh
# platform: host-agnostic
. "$(dirname "$0")/support/common.sh"
. "$ROOT/tests/support/preparation.sh"
[ -f "$ROOT/components/wezterm/version" ] || fail 'verified source pin is not implemented'
[ -f "$ROOT/patches/series" ] || fail 'ordered patch preparation is not implemented'
make_preparation_fixture
assert_run 0 sh "$fixture/build/prepare.sh"
[ "$(cat "$work/source/message.txt")" = two ] || fail 'patch did not change the verified source'
assert_run 0 sh "$fixture/build/prepare.sh" --verify
pass 'verified source is patched and provenance verifies'
mkdir "$work/.lock"
assert_run 0 sh "$fixture/build/prepare.sh" --verify
rmdir "$work/.lock"
pass 'read-only provenance verification remains available during a build'
assert_run 0 sh "$fixture/build/prepare.sh"
[ "$(cat "$work/source/message.txt")" = two ] || fail 'repreparation stacked the patch'
pass 'reprepare starts from verified upstream bytes'
printf 'edited\n' > "$work/source/message.txt"
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'modified'
[ "$(cat "$work/source/message.txt")" = edited ] || fail 'dirty source was removed'
pass 'dirty prepared source is preserved and rejected'
printf 'two\n' > "$work/source/message.txt"
assert_run 0 sh "$fixture/build/prepare.sh" --verify
printf 'different\n' >> "$fixture/patches/fixture.patch"
assert_run 1 sh "$fixture/build/prepare.sh" --verify
assert_output 'recipe'
pass 'changed patches invalidate reuse'
sed '$d' "$fixture/patches/fixture.patch" > "$TEST_ROOT/patch-restored"
cp "$TEST_ROOT/patch-restored" "$fixture/patches/fixture.patch"
printf 'not verified bytes\n' > "$work/downloads/wezterm-$DIGEST.tar.gz"
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'not the pinned'
for remaining in "$work"/preparing.*; do
    [ ! -d "$remaining" ] || fail 'failed preparation leaked a staging directory'
done
assert_run 0 sh "$fixture/build/prepare.sh" --verify
pass 'bad archive checksum leaves the prepared source intact'
"${PYTHON:-python}" - "$fixture/components/wezterm/version" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
lines = [x if not x.startswith('HARFBUZZ_DIGEST=') else 'HARFBUZZ_DIGEST=' + '0' * 40 for x in s.splitlines()]
open(path, 'w').write('\n'.join(lines) + '\n')
PY
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'gitlink'
pass 'submodule pin must match recorded parent gitlink'
mkdir "$TEST_ROOT/foreign"
printf 'owned by someone else\n' > "$TEST_ROOT/foreign/keep"
export MAVERICKS_BUILD_ROOT=$TEST_ROOT/foreign
mkdir "$TEST_ROOT/foreign/checkout-wezterm-local"
printf 'foreign\n' > "$TEST_ROOT/foreign/checkout-wezterm-local/keep"
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'foreign'
[ "$(cat "$TEST_ROOT/foreign/checkout-wezterm-local/keep")" = foreign ] || fail 'foreign build directory was overwritten'
pass 'foreign directory is preserved'
export MAVERICKS_BUILD_ROOT=$fixture/output
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'outside'
[ ! -d "$fixture/output" ] || fail 'in-tree output directory was created before validation'
pass 'in-tree output is rejected before writing'
