#!/bin/sh
# platform: macOS-only -- compiles Mavericks Mach-O probes, executing them only where x86_64 runs natively
. "$(dirname "$0")/support/common.sh"
. "$ROOT/tests/support/host.sh"
. "$ROOT/build/msc.sh"
export MAVERICKS_BUILD_ROOT=$TEST_ROOT/builds
sdk=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64) || fail 'shipyard could not fetch the pinned 10.9 SDK'
cat > "$TEST_ROOT/probe.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("C_TARGET_OK"); return 0; }
EOF
printf 'fn main() { println!("RUST_TARGET_OK"); }\n' > "$TEST_ROOT/probe.rs"
cat > "$TEST_ROOT/expect.sh" <<'EOF'
expect() {
    [ "$2" = "$3" ] || { printf 'FAIL: %s is %s, not %s\n' "$1" "$2" "$3" >&2; exit 1; }
}
EOF

manifest() {
    mkdir -p "$1/usr/local/mavergreen/$2/bin"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>version</key>\n  <string>%s</string>\n</dict>\n</plist>\n' "$3" > "$1/usr/local/mavergreen/$2/mavergreen.plist"
}
stub() {
    printf '#!/bin/sh\nprintf "%%s|%%s|%%s\\n" "$0" "${SDKROOT-unset}" "$*" >> "$FIXTURE_LOG"\n' > "$1"
    chmod +x "$1"
}
cross_root() {  # cross_root DIR HOST-TRIPLE: the cross products at their pins, as recording stand-ins
    rm -rf "$1"
    manifest "$1" rust-cross "$(cat "$ROOT/components/rust/version")"
    manifest "$1" clang22-cross "$(cat "$ROOT/components/clang22/version")"
    manifest "$1" make "$(cat "$ROOT/components/make/version")"
    mkdir -p "$1/usr/local/mavergreen/shipyard/bin"
    trees=$1/usr/local/mavergreen
    printf '#!/bin/sh\n[ "$1" != -vV ] || printf "rustc 0.0.0\\nhost: %s\\n"\n' "$2" > "$trees/rust-cross/bin/rustc"
    chmod +x "$trees/rust-cross/bin/rustc"
    stub "$trees/rust-cross/bin/cargo"
    for tool in clang clang++ llvm-ar llvm-ranlib llvm-otool llvm-lipo llvm-nm llvm-strings; do
        stub "$trees/clang22-cross/bin/$tool"
    done
    stub "$trees/make/bin/gmake"
    stub "$trees/make/bin/make"
    stub "$trees/shipyard/bin/shipyard-cmake"
}
cat > "$TEST_ROOT/check-cross.sh" <<'EOF'
set -eu
. "$2/expect.sh"
t=$MAVERGREEN_TOOL_ROOT/usr/local/mavergreen
expect MODE "$MODE" cross
expect RUSTC "$RUSTC" "$t/rust-cross/bin/rustc"
expect CARGO "$CARGO" "$t/rust-cross/bin/cargo"
expect AR "$AR" "$t/clang22-cross/bin/llvm-ar"
expect RANLIB "$RANLIB" "$t/clang22-cross/bin/llvm-ranlib"
expect OTOOL "$OTOOL" "$t/clang22-cross/bin/llvm-otool"
expect LIPO "$LIPO" "$t/clang22-cross/bin/llvm-lipo"
expect NM "$NM" "$t/clang22-cross/bin/llvm-nm"
expect STRINGS "$STRINGS" "$t/clang22-cross/bin/llvm-strings"
expect MAKE "$MAKE" "$t/make/bin/gmake"
expect CMAKE "$CMAKE" "$t/shipyard/bin/shipyard-cmake"
expect 'SDKROOT (the host build scripts must see the runner'"'"'s own SDK)' "${SDKROOT-unset}" unset
expect MACOSX_DEPLOYMENT_TARGET "$MACOSX_DEPLOYMENT_TARGET" 10.9
expect CC_x86_64_apple_darwin "${CC_x86_64_apple_darwin-unset}" "$CC"
expect CXX_x86_64_apple_darwin "${CXX_x86_64_apple_darwin-unset}" "$CXX"
expect CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER "$CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER" "$CXX"
case "$1" in
    aarch64-apple-darwin)
        expect 'host CC_aarch64_apple_darwin' "${CC_aarch64_apple_darwin-unset}" /usr/bin/clang
        expect 'host CXX_aarch64_apple_darwin' "${CXX_aarch64_apple_darwin-unset}" /usr/bin/clang++
        expect HOST_CC "${HOST_CC-unset}" /usr/bin/clang
        expect HOST_CXX "${HOST_CXX-unset}" /usr/bin/clang++
        expect 'host linker' "${CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER-unset}" /usr/bin/clang
        ;;
    x86_64-apple-darwin)
        expect 'HOST_CC (the host is the target)' "${HOST_CC-unset}" unset
        expect 'HOST_CXX (the host is the target)' "${HOST_CXX-unset}" unset
        ;;
esac
expect 'cargo on PATH' "$(command -v cargo)" "$CARGO"
expect 'make on PATH' "$(command -v make)" "$t/make/bin/make"
case ":$PATH:" in
    *":$t/clang22-cross/bin:"*) echo 'FAIL: the target clang is on PATH, where host tools would find it' >&2; exit 1 ;;
esac
"$CC" -c probe.c
"$CXX" -c probe.cc
EOF
for host in aarch64-apple-darwin x86_64-apple-darwin; do
    cross_root "$TEST_ROOT/cross" "$host"
    FIXTURE_LOG=$TEST_ROOT/cross.log
    : > "$FIXTURE_LOG"
    trees=$TEST_ROOT/cross/usr/local/mavergreen
    assert_run 0 env FIXTURE_LOG="$FIXTURE_LOG" MAVERGREEN_TOOL_ROOT="$TEST_ROOT/cross" SDKROOT=/hostile \
        CC_x86_64_apple_darwin=/hostile CXX_x86_64_apple_darwin=/hostile HOST_CC=/hostile HOST_CXX=/hostile \
        sh "$ROOT/build/environment.sh" --mode cross sh "$TEST_ROOT/check-cross.sh" "$host" "$TEST_ROOT"
    for compiler in clang:probe.c clang++:probe.cc; do
        line="$trees/clang22-cross/bin/${compiler%%:*}|$sdk|-target x86_64-apple-macos10.9 -isysroot $sdk -c ${compiler#*:}"
        grep -F -x "$line" "$FIXTURE_LOG" > /dev/null ||
            fail "the cross target compiler wrapper did not run '$line'; it ran: $(cat "$FIXTURE_LOG")"
    done
done
pass 'cross mode: rust-cross and clang22-cross for the 10.9 target, the runner'"'"'s clang for the host, no global SDKROOT'

for arguments in '--mode' '--mode bogus true' '--mode cross'; do
    assert_run 1 sh "$ROOT/build/environment.sh" $arguments
    assert_output 'usage: environment.sh [--mode native|cross] COMMAND'
done
pass 'environment.sh refuses an unknown mode or a missing command'

mkdir -p "$TEST_ROOT/stale/usr/local/mavergreen/clang22" "$TEST_ROOT/stale/usr/local/mavergreen/clang22-cross"
for short in clang22 clang22-cross; do
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>version</key>\n  <string>0.0.1</string>\n</dict>\n</plist>\n' > "$TEST_ROOT/stale/usr/local/mavergreen/$short/mavergreen.plist"
done
for mode in native cross; do
    case "$mode" in native) clang=clang22 rust=rust ;; cross) clang=clang22-cross rust=rust-cross ;; esac
    assert_run 1 env MAVERGREEN_TOOL_ROOT="$TEST_ROOT/stale" sh "$ROOT/build/environment.sh" --mode "$mode" sh -c 'echo ENVIRONMENT_RAN'
    assert_output "$clang: pinned at $(cat "$ROOT/components/clang22/version"), but 0.0.1 is installed"
    assert_output "$rust: pinned at $(cat "$ROOT/components/rust/version"), but not installed"
    assert_output 'build/tools.sh'
    if grep -F ENVIRONMENT_RAN "$TEST_ROOT/output" > /dev/null; then fail "the $mode build ran with tools other than the pinned releases"; fi
done
pass 'the build refuses to run unless the pinned releases for its mode are installed'
# spec: INGREDIENTS.md "CI" -- the real toolchain needs this host's pinned products, which a build
#       host has and the 10.9 guest does not; one installed at another release still fails below
if ! installed=$(sh "$ROOT/build/tools.sh" check --root "${MAVERGREEN_TOOL_ROOT:-/}" 2>&1); then
    if ! printf '%s\n' "$installed" | grep '^tools: ' | grep -v ', but not installed' | grep . > /dev/null; then
        echo "the pinned products are not installed, so the real toolchain is not checked here: $installed"
        exit 77
    fi
fi

cat > "$TEST_ROOT/check.sh" <<'EOF'
set -eu
. "$2/expect.sh"
trees=${MAVERGREEN_TOOL_ROOT:-/}
trees=${trees%/}/usr/local/mavergreen
case "$MODE" in native) rust=rust clang=clang22 ;; cross) rust=rust-cross clang=clang22-cross ;; esac
expect RUSTC "$RUSTC" "$trees/$rust/bin/rustc"
expect CARGO "$CARGO" "$trees/$rust/bin/cargo"
expect AR "$AR" "$trees/$clang/bin/llvm-ar"
expect RANLIB "$RANLIB" "$trees/$clang/bin/llvm-ranlib"
expect OTOOL "$OTOOL" "$trees/$clang/bin/llvm-otool"
expect LIPO "$LIPO" "$trees/$clang/bin/llvm-lipo"
expect NM "$NM" "$trees/$clang/bin/llvm-nm"
expect STRINGS "$STRINGS" "$trees/$clang/bin/llvm-strings"
expect MAKE "$MAKE" "$trees/make/bin/gmake"
expect CMAKE "$CMAKE" "$trees/shipyard/bin/shipyard-cmake"
expect CARGO_PROFILE_RELEASE_DEBUG "${CARGO_PROFILE_RELEASE_DEBUG-unset}" 0
expect CARGO_INCREMENTAL "${CARGO_INCREMENTAL-unset}" 0
expect 'cargo on PATH' "$(command -v cargo)" "$CARGO"
expect 'rustc on PATH' "$(command -v rustc)" "$RUSTC"
expect 'make on PATH' "$(command -v make)" "$trees/make/bin/make"
if [ "$MODE" = native ]; then
    expect 'clang on PATH' "$(command -v clang)" "$trees/clang22/bin/clang"
    expect SDKROOT "$SDKROOT" "$3"
else
    expect SDKROOT "${SDKROOT-unset}" unset
fi
grep -F "exec '$trees/$clang/bin/clang' " "$CC" > /dev/null || { echo "FAIL: CC does not run $trees/$clang/bin/clang" >&2; exit 1; }
grep -F "exec '$trees/$clang/bin/clang++' " "$CXX" > /dev/null || { echo "FAIL: CXX does not run $trees/$clang/bin/clang++" >&2; exit 1; }
[ "$MACOSX_DEPLOYMENT_TARGET" = 10.9 ]
"$CC" "$2/probe.c" -o "$2/c-probe"
"$CXX" -x c++ "$2/probe.c" -o "$2/cxx-probe"
"$RUSTC" --target x86_64-apple-darwin -C "linker=$CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER" "$2/probe.rs" -o "$2/rust-probe"
"$CC" -c "$2/probe.c" -o "$2/probe.o"
"$AR" qc "$2/probe.a" "$2/probe.o"
"$RANLIB" "$2/probe.a"
"$CC" "$2/probe.a" -o "$2/archive-probe"
for executable in c-probe cxx-probe rust-probe archive-probe; do
    "$OTOOL" -l "$2/$executable" > "$2/$executable.loads"
    grep -E 'sdk 10\.9([[:space:]]|$)' "$2/$executable.loads"
    grep -E 'version 10\.9([[:space:]]|$)' "$2/$executable.loads"
    [ "$1" != run ] || "$2/$executable"
done
EOF
if runs_x86_64; then run=run; else run=inspect; fi
assert_run 0 sh "$ROOT/build/environment.sh" sh "$TEST_ROOT/check.sh" "$run" "$TEST_ROOT" "$sdk"
if [ "$run" = run ]; then
    assert_output 'C_TARGET_OK'
    assert_output 'RUST_TARGET_OK'
    pass 'C, C++ and Rust execute from the pinned products and record Mavericks floor and SDK'
else
    pass "C, C++ and Rust from the pinned products record Mavericks floor and SDK (not executed: this $(uname -m) host does not run x86_64 natively)"
fi
