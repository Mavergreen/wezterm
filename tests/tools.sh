#!/bin/sh
# platform: host-agnostic
. "$(dirname "$0")/support/common.sh"
tools=$ROOT/build/tools.sh
[ -f "$tools" ] || fail 'build/tools.sh check is not implemented'
pin() { cat "$ROOT/components/${1%-cross}/version"; }
for component in rust clang22 make longboat; do
    [ -f "$ROOT/components/$component/version" ] || fail "components/$component/version is not pinned"
    case "$(pin "$component")" in
        *[!0-9A-Za-z.-]*|'') fail "components/$component/version must hold one release tag" ;;
    esac
done
pass 'every measured build tool is pinned to one release tag'

manifest() {
    mkdir -p "$1/usr/local/mavergreen/$2"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n  <key>product</key>\n  <string>%s</string>\n  <key>version</key>\n  <string>%s</string>\n</dict>\n</plist>\n' "$2" "$3" > "$1/usr/local/mavergreen/$2/mavergreen.plist"
}
installed() {
    rm -rf "$TEST_ROOT/root"
    for short in "$@"; do manifest "$TEST_ROOT/root" "$short" "$(pin "$short")"; done
}

installed rust clang22 make
assert_run 0 sh "$tools" check --root "$TEST_ROOT/root" --mode native
pass 'native passes with exactly rust, clang22 and make at their pins'

installed rust-cross clang22-cross make
assert_run 0 sh "$tools" check --root "$TEST_ROOT/root/" --mode cross
pass 'cross passes with exactly rust-cross, clang22-cross and make at their pins'

for mode in native cross; do
    case "$mode" in native) set -- rust clang22 make ;; cross) set -- rust-cross clang22-cross make ;; esac
    for missing in "$@"; do
        installed "$@"
        rm -r "$TEST_ROOT/root/usr/local/mavergreen/$missing"
        assert_run 1 sh "$tools" check --root "$TEST_ROOT/root" --mode "$mode"
        assert_output "$missing: pinned at $(pin "$missing"), but not installed"
        assert_output "$TEST_ROOT/root/usr/local/mavergreen/$missing/mavergreen.plist"
    done
done
pass 'a missing pinned product fails, naming it and its pin'

installed rust clang22 make
manifest "$TEST_ROOT/root" clang22 22.1.8-mavericks.5
manifest "$TEST_ROOT/root" make 0.0.1
assert_run 1 sh "$tools" check --root "$TEST_ROOT/root" --mode native
assert_output "clang22: pinned at $(pin clang22), but 22.1.8-mavericks.5 is installed"
assert_output "make: pinned at $(pin make), but 0.0.1 is installed"
pass 'an older installed product fails, and every mismatch is reported'

installed rust clang22 make
manifest "$TEST_ROOT/root" rust "$(pin rust).1"
assert_run 1 sh "$tools" check --root "$TEST_ROOT/root" --mode native
assert_output "rust: pinned at $(pin rust), but $(pin rust).1 is installed"
pass 'a newer installed product fails too: the pin is exact'

installed rust clang22 make
printf 'not a plist\n' > "$TEST_ROOT/root/usr/local/mavergreen/clang22/mavergreen.plist"
assert_run 1 sh "$tools" check --root "$TEST_ROOT/root" --mode native
assert_output "clang22: pinned at $(pin clang22), but $TEST_ROOT/root/usr/local/mavergreen/clang22/mavergreen.plist is unreadable or has no version"
installed rust clang22 make
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>product</key>\n  <string>make</string>\n</dict>\n</plist>\n' > "$TEST_ROOT/root/usr/local/mavergreen/make/mavergreen.plist"
assert_run 1 sh "$tools" check --root "$TEST_ROOT/root" --mode native
assert_output "make: pinned at $(pin make), but $TEST_ROOT/root/usr/local/mavergreen/make/mavergreen.plist is unreadable or has no version"
pass 'a malformed manifest, or one without a version, fails naming the product'

cp -R "$ROOT/build" "$TEST_ROOT/checkout-build"
mkdir -p "$TEST_ROOT/checkout/components"
mv "$TEST_ROOT/checkout-build" "$TEST_ROOT/checkout/build"
cp -R "$ROOT/components/rust" "$ROOT/components/clang22" "$TEST_ROOT/checkout/components/"
installed rust clang22 make
assert_run 1 sh "$TEST_ROOT/checkout/build/tools.sh" check --root "$TEST_ROOT/root" --mode native
assert_output 'make: components/make/version must hold one Mavergreen release tag'
mkdir "$TEST_ROOT/checkout/components/make"
printf '%s\nextra\n' "$(pin make)" > "$TEST_ROOT/checkout/components/make/version"
assert_run 1 sh "$TEST_ROOT/checkout/build/tools.sh" check --root "$TEST_ROOT/root" --mode native
assert_output 'make: components/make/version must hold one Mavergreen release tag'
pass 'a missing or malformed pin fails before any manifest is trusted'

installed rust rust-cross
for mode in native cross; do
    case "$mode" in native) short=rust ;; cross) short=rust-cross ;; esac
    assert_run 0 sh "$tools" tree --root "$TEST_ROOT/root" --mode "$mode" rust
    [ "$(cat "$TEST_ROOT/output")" = "$TEST_ROOT/root/usr/local/mavergreen/$short" ] ||
        fail "tools.sh tree rust in $mode mode must print only the pinned $short tree, not: $(cat "$TEST_ROOT/output")"
done
pass "tree prints one component's pinned tree for the mode, checking that component alone"
manifest "$TEST_ROOT/root" rust 0.0.1
assert_run 1 sh "$tools" tree --root "$TEST_ROOT/root" --mode native rust
assert_output "rust: pinned at $(pin rust), but 0.0.1 is installed"
if grep -F "$TEST_ROOT/root/usr/local/mavergreen/rust" "$TEST_ROOT/output" | grep -v 'is installed' > /dev/null; then fail 'tree printed a tree whose release is not the pin'; fi
rm -r "$TEST_ROOT/root/usr/local/mavergreen/rust"
assert_run 1 sh "$tools" tree --root "$TEST_ROOT/root" --mode native rust
assert_output "rust: pinned at $(pin rust), but not installed"
pass 'tree refuses a component installed at another release, or not at all'

for arguments in '' 'verify' 'check --mode bogus' 'check --root' 'check --mode' 'check extra' \
    'tree' 'tree --mode native' 'tree bogus' 'tree rust clang22' 'tree --mode bogus rust'; do
    assert_run 2 sh "$tools" $arguments
    assert_output 'usage: tools.sh check'
    assert_output 'tools.sh tree'
done
pass 'usage errors exit 2'
