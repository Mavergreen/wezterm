#!/bin/sh
# platform: host-agnostic
. "$(dirname "$0")/support/common.sh"
. "$ROOT/tests/support/preparation.sh"
[ -f "$ROOT/components/wezterm/version" ] || fail 'verified source pin is not implemented'
[ ! -e "$ROOT/patches/series" ] || fail "source patches apply in name order through shipyard's apply_patches.sh, so patches/series must go"
make_preparation_fixture
export MAVERICKS_TAGS=
grep -v '^COMMITTED=' "$fixture/components/wezterm/version" > "$TEST_ROOT/pin"
printf 'COMMITTED=20200102.030405\n' >> "$TEST_ROOT/pin"
cp "$TEST_ROOT/pin" "$fixture/components/wezterm/version"
assert_run 0 sh "$fixture/build/prepare.sh"
[ "$(cat "$work/source/message.txt")" = two ] || fail 'patch did not change the verified source'
assert_run 0 sh "$fixture/build/prepare.sh" --verify
pass 'verified source is patched and provenance verifies'
[ "$(cat "$work/source/.mavergreen-patches" 2>/dev/null)" = "$(cd "$fixture/patches" && shasum -a 256 fixture.patch)" ] ||
    fail "the source must be patched by shipyard's apply_patches.sh, which records each patch's SHA-256 in .mavergreen-patches"
pass 'source patches apply through apply_patches.sh'
. "$fixture/components/wezterm/version"
for stamp in ".mavergreen-source:$REPO $DIGEST $SHA256" \
    "deps/freetype/freetype2/.mavergreen-source:$FREETYPE2_REPO $FREETYPE2_DIGEST $FREETYPE2_SHA256" \
    "deps/freetype/libpng/.mavergreen-source:$LIBPNG_REPO $LIBPNG_DIGEST $LIBPNG_SHA256" \
    "deps/freetype/zlib/.mavergreen-source:$ZLIB_REPO $ZLIB_DIGEST $ZLIB_SHA256" \
    "deps/harfbuzz/harfbuzz/.mavergreen-source:$HARFBUZZ_REPO $HARFBUZZ_DIGEST $HARFBUZZ_SHA256"; do
    [ "$(cat "$work/source/${stamp%%:*}" 2>/dev/null)" = "${stamp#*:}" ] ||
        fail "$work/source/${stamp%%:*} must be fetch_pinned_source.sh's stamp, \"${stamp#*:}\": the parent and every submodule come through shipyard's verified fetch of the commit's tarball"
done
pass 'the parent and each submodule are fetched through shipyard by their pinned SHA-256'
for interpreter in "${PYTHON:-python}" python3; do
    command -v "$interpreter" > /dev/null 2>&1 || continue
    for script in "$fixture"/build/*.py; do
        "$interpreter" "$script" > /dev/null 2>&1 || :
    done
done
caches=$(find "$fixture/build" -name __pycache__ -o -name '*.pyc')
[ -z "$caches" ] || fail "a build script left Python bytecode in the recipe, which provenance hashes as recipe.build: $caches"
assert_run 0 sh "$fixture/build/prepare.sh" --verify
pass 'build scripts write no bytecode into the recorded recipe'
for stray in build/provenance.pyc build/__pycache__ patches/crates/__pycache__ components/wezterm/x.pyo \
    build/._environment.sh patches/._0001-vendored-build-openssl.patch components/._wezterm; do
    case "$stray" in
        build/__pycache__) mkdir "$fixture/$stray" ;;
        */__pycache__) mkdir "$fixture/$stray"; printf 'cache\n' > "$fixture/$stray/provenance.cpython-315.pyc" ;;
        *) printf 'cache\n' > "$fixture/$stray" ;;
    esac
    assert_run 1 sh "$fixture/build/prepare.sh" --verify
    assert_output "$stray"
    assert_run 1 sh "$fixture/build/prepare.sh"
    assert_output "$stray"
    rm -rf "${fixture:?}/$stray"
done
assert_run 0 sh "$fixture/build/prepare.sh" --verify
pass 'Python bytecode and AppleDouble files in the recipe are refused by name, never hashed or skipped'
[ "$(cat "$fixture/UPSTREAM_VERSION")" = 20200102.030405 ] || fail 'preparation must derive UPSTREAM_VERSION from the pin before resolving the version'
[ "$(cat "$work/source/.tag")" = 20200102.030405-mavericks.1 ] || fail 'the build identity must be the product version, not local-<sha>'
[ "$(cat "$fixture/VERSION")" = 20200102.030405-mavericks.1 ] || fail 'preparation must resolve VERSION the family way, so every later step agrees'
pass 'prepared build identity is the snapshot version'
printf '20190101.000000-mavericks.3\n' > "$fixture/VERSION"
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'VERSION'
[ "$(cat "$work/source/.tag")" = 20200102.030405-mavericks.1 ] || fail 'a stale VERSION replaced the prepared source'
rm "$fixture/VERSION"
pass 'a VERSION left from another upstream is refused'
sed 's/^COMMITTED=.*/COMMITTED=2020-01-02/' "$TEST_ROOT/pin" > "$fixture/components/wezterm/version"
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'COMMITTED'
cp "$TEST_ROOT/pin" "$fixture/components/wezterm/version"
pass 'a malformed COMMITTED stops preparation'
mkdir "$work/.lock"
assert_run 0 sh "$fixture/build/prepare.sh" --verify
rmdir "$work/.lock"
pass 'read-only provenance verification remains available during a build'
assert_run 0 sh "$fixture/build/prepare.sh"
[ "$(cat "$work/source/message.txt")" = two ] || fail 'repreparation stacked the patch'
pass 'reprepare starts from verified upstream bytes'
cat > "$fixture/patches/stale.patch" <<'EOF'
--- a/message.txt
+++ b/message.txt
@@ -1 +1 @@
-three
+four
EOF
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'stale.patch'
[ "$(cat "$work/source/message.txt")" = two ] || fail 'a source patch that does not apply replaced the prepared source'
rm "$fixture/patches/stale.patch"
pass 'a source patch that does not apply stops preparation'
sed -e 's/^-one$/-two/' -e 's/^+two$/+three/' "$fixture/patches/fixture.patch" > "$fixture/patches/later.patch"
assert_run 0 sh "$fixture/build/prepare.sh"
[ "$(cat "$work/source/message.txt")" = three ] || fail 'source patches must apply in name order: later.patch (two to three) after fixture.patch (one to two)'
rm "$fixture/patches/later.patch"
assert_run 0 sh "$fixture/build/prepare.sh"
pass 'source patches apply in name order'
export MAVERGREEN_TOOL_ROOT=$tools CARGO=$TEST_ROOT/farm/cargo PATH=$TEST_ROOT/farm:$PATH
mkdir "$fixture/patches/crates/demo"
cp "$TEST_ROOT/demo.patch" "$fixture/patches/crates/demo/"
assert_run 0 sh "$fixture/build/prepare.sh"
[ "$(cat "$work/crates/demo/message.txt")" = two ] || fail 'crate patch did not change the verified crate'
[ "$(cat "$work/crates/demo/.mavergreen-patches" 2>/dev/null)" = "$(cd "$fixture/patches/crates/demo" && shasum -a 256 demo.patch)" ] ||
    fail "a crate's patches (patches/crates/<crate>/*.patch) must apply through shipyard's apply_patches.sh"
sed -e 's/^-one$/-two/' -e 's/^+two$/+three/' "$TEST_ROOT/demo.patch" > "$fixture/patches/crates/demo/later.patch"
assert_run 0 sh "$fixture/build/prepare.sh"
[ "$(cat "$work/crates/demo/message.txt")" = three ] || fail "a crate's patches must all apply, in name order, to one extraction of it"
rm "$fixture/patches/crates/demo/later.patch"
assert_run 0 sh "$fixture/build/prepare.sh"
grep -F 'demo = { path = "../crates/demo" }' "$work/source/Cargo.toml" > /dev/null || fail 'patched crate is not a path override'
grep -F 'stub cargo fetch --locked' "$STUB_CARGO_LOG" > /dev/null || fail 'preparation did not check the patched lock with cargo fetch --locked'
pass 'crate patches apply to verified crates'
cp "$tools/usr/local/mavergreen/rust/mavergreen.plist" "$TEST_ROOT/rust.plist"
for short in rust rust-cross; do
    sed "s/$rust_pin/0.0.1/" "$TEST_ROOT/rust.plist" > "$tools/usr/local/mavergreen/$short/mavergreen.plist"
done
: > "$STUB_CARGO_LOG"
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output "rust: pinned at $rust_pin, but 0.0.1 is installed"
[ ! -s "$STUB_CARGO_LOG" ] || fail "preparation ran cargo from a rust tree that is not at its pin: $(cat "$STUB_CARGO_LOG")"
for short in rust rust-cross; do cp "$TEST_ROOT/rust.plist" "$tools/usr/local/mavergreen/$short/mavergreen.plist"; done
pass "cargo comes only from the pinned rust tree under MAVERGREEN_TOOL_ROOT, never CARGO or PATH"
for step in fetch update; do
    STUB_CARGO_FAILS=$step
    export STUB_CARGO_FAILS
    assert_run 101 sh "$fixture/build/prepare.sh"
    assert_output "stub cargo: $step refused"
    unset STUB_CARGO_FAILS
done
pass 'a refused cargo fetch --locked or cargo update stops preparation'
sed 's/^-one$/-three/' "$TEST_ROOT/demo.patch" > "$fixture/patches/crates/demo/stale.patch"
assert_run 1 sh "$fixture/build/prepare.sh"
assert_output 'stale.patch'
for remaining in "$work"/preparing.*; do
    [ ! -d "$remaining" ] || fail 'failed preparation leaked a staging directory'
done
rm -r "$fixture/patches/crates/demo"
assert_run 0 sh "$fixture/build/prepare.sh"
pass 'a crate patch that does not apply stops preparation'
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
for archive in "wezterm-$DIGEST" "harfbuzz-$HARFBUZZ_DIGEST"; do
    printf 'not verified bytes\n' > "$MAVERICKS_SOURCE_CACHE/$archive.tar.gz"
    assert_run 1 sh "$fixture/build/prepare.sh"
    assert_output 'not the pinned'
    for remaining in "$work"/preparing.*; do
        [ ! -d "$remaining" ] || fail 'failed preparation leaked a staging directory'
    done
    assert_run 0 sh "$fixture/build/prepare.sh" --verify
done
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
