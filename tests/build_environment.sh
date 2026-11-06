#!/bin/sh
# platform: macOS-only -- compiles and executes actual Mavericks Mach-O probes
. "$(dirname "$0")/support/common.sh"
export MAVERICKS_BUILD_ROOT=$TEST_ROOT/builds
cat > "$TEST_ROOT/probe.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("C_TARGET_OK"); return 0; }
EOF
printf 'fn main() { println!("RUST_TARGET_OK"); }\n' > "$TEST_ROOT/probe.rs"
# spec: INGREDIENTS.md "On-target acceptance" -- the real toolchain needs this host's pinned
#       products, which a build host has and a 10.9 machine checking an installed release need not;
#       one installed at another release still fails below
if ! installed=$(sh "$ROOT/build/tools.sh" check --root "${MAVERGREEN_TOOL_ROOT:-/}" 2>&1); then
    if ! printf '%s\n' "$installed" | grep '^tools: ' | grep -v ', but not installed' | grep . > /dev/null; then
        echo "the pinned products are not installed, so the real toolchain is not checked here: $installed"
        exit 77
    fi
fi

cat > "$TEST_ROOT/check.sh" <<'EOF'
set -eu
trees=${MAVERGREEN_TOOL_ROOT:-/}
trees=${trees%/}/usr/local/mavergreen
expect() {
    [ "$2" = "$3" ] || { printf 'FAIL: %s is %s, not %s\n' "$1" "$2" "$3" >&2; exit 1; }
}
expect RUSTC "$RUSTC" "$trees/rust/bin/rustc"
expect CARGO "$CARGO" "$trees/rust/bin/cargo"
expect AR "$AR" "$trees/clang22/bin/llvm-ar"
expect RANLIB "$RANLIB" "$trees/clang22/bin/llvm-ranlib"
expect OTOOL "$OTOOL" "$trees/clang22/bin/llvm-otool"
expect LIPO "$LIPO" "$trees/clang22/bin/llvm-lipo"
expect NM "$NM" "$trees/clang22/bin/llvm-nm"
expect STRINGS "$STRINGS" "$trees/clang22/bin/llvm-strings"
expect MAKE "$MAKE" "$trees/make/bin/gmake"
expect CMAKE "$CMAKE" "$trees/shipyard/bin/shipyard-cmake"
expect CARGO_PROFILE_RELEASE_DEBUG "${CARGO_PROFILE_RELEASE_DEBUG-unset}" 0
expect CARGO_INCREMENTAL "${CARGO_INCREMENTAL-unset}" 0
expect 'cargo on PATH' "$(command -v cargo)" "$CARGO"
expect 'rustc on PATH' "$(command -v rustc)" "$RUSTC"
expect 'make on PATH' "$(command -v make)" "$trees/make/bin/make"
expect 'clang on PATH' "$(command -v clang)" "$trees/clang22/bin/clang"
grep -F "exec '$trees/clang22/bin/clang' " "$CC" > /dev/null || { echo "FAIL: CC does not run $trees/clang22/bin/clang" >&2; exit 1; }
grep -F "exec '$trees/clang22/bin/clang++' " "$CXX" > /dev/null || { echo "FAIL: CXX does not run $trees/clang22/bin/clang++" >&2; exit 1; }
[ "$MODE" = native ]
[ "$MACOSX_DEPLOYMENT_TARGET" = 10.9 ]
[ "$SDKROOT" = "$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)" ]
[ -x "$MAKE" ] && [ -x "$AR" ] && [ -x "$CMAKE" ] && [ -x "$RANLIB" ]
case "$RANLIB" in */llvm-ranlib) ;; *) exit 1 ;; esac
"$CC" "$1/probe.c" -o "$1/c-probe"
"$CXX" -x c++ "$1/probe.c" -o "$1/cxx-probe"
"$RUSTC" --target x86_64-apple-darwin -C "linker=$CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER" "$1/probe.rs" -o "$1/rust-probe"
"$1/c-probe"
"$1/cxx-probe"
"$1/rust-probe"
"$CC" -c "$1/probe.c" -o "$1/probe.o"
"$AR" qc "$1/probe.a" "$1/probe.o"
"$RANLIB" "$1/probe.a"
"$CC" "$1/probe.a" -o "$1/archive-probe"
"$1/archive-probe"
for executable in c-probe cxx-probe rust-probe archive-probe; do
    "$OTOOL" -l "$1/$executable" > "$1/$executable.loads"
    grep -E 'sdk 10\.9([[:space:]]|$)' "$1/$executable.loads"
    grep -E 'version 10\.9([[:space:]]|$)' "$1/$executable.loads"
done
EOF
assert_run 0 sh "$ROOT/build/environment.sh" sh "$TEST_ROOT/check.sh" "$TEST_ROOT"
assert_output 'C_TARGET_OK'
assert_output 'RUST_TARGET_OK'
pass 'C, C++ and Rust execute from the pinned products and record Mavericks floor and SDK'
mkdir -p "$TEST_ROOT/stale/usr/local/mavergreen/clang22"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>version</key>\n  <string>0.0.1</string>\n</dict>\n</plist>\n' > "$TEST_ROOT/stale/usr/local/mavergreen/clang22/mavergreen.plist"
MAVERGREEN_TOOL_ROOT=$TEST_ROOT/stale assert_run 1 sh "$ROOT/build/environment.sh" sh -c 'echo ENVIRONMENT_RAN'
assert_output "clang22: pinned at $(cat "$ROOT/components/clang22/version"), but 0.0.1 is installed"
assert_output "rust: pinned at $(cat "$ROOT/components/rust/version"), but not installed"
assert_output 'build/tools.sh'
if grep -F ENVIRONMENT_RAN "$TEST_ROOT/output" > /dev/null; then fail 'the build ran with tools other than the pinned releases'; fi
pass 'the build refuses to run unless the pinned releases are installed'
