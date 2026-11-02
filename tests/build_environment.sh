#!/bin/sh
# platform: macOS-only -- compiles and executes actual Mavericks Mach-O probes
. "$(dirname "$0")/support/common.sh"
export MAVERICKS_BUILD_ROOT=$TEST_ROOT/builds
cat > "$TEST_ROOT/probe.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("C_TARGET_OK"); return 0; }
EOF
printf 'fn main() { println!("RUST_TARGET_OK"); }\n' > "$TEST_ROOT/probe.rs"
cat > "$TEST_ROOT/check.sh" <<'EOF'
set -eu
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
pass 'C, C++ and Rust execute and record pinned Mavericks floor and SDK'
