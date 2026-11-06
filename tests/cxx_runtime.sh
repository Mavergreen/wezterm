#!/bin/sh
# platform: macOS-only -- links fixture Mach-O files with the pinned clang22 and reads the staged app
#   usage: sh tests/cxx_runtime.sh
#          The shipped executables carry no C++ runtime: none loads a libc++, libc++abi or libstdc++,
#          and none defines or imports the runtime's symbols, so there is neither a second static copy
#          nor a dependency on libcxx22. harfbuzz is C++, built without exceptions or RTTI.
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
cl=$(sh "$ROOT/build/tools.sh" tree clang22) || { echo "the pinned clang22 for this host is not installed"; exit 77; }
cl=$cl/bin
sdk=$(sh "$SHIPYARD/fetch_sdk.sh" --arch x86_64) || fail 'shipyard could not fetch the pinned 10.9 SDK'
runtime_free() {  # runtime_free MACHO: says why MACHO carries a C++ runtime, and fails, if it does
    "$cl/llvm-otool" -L "$1" > "$TEST_ROOT/loads" || fail "llvm-otool cannot read $1"
    "$cl/llvm-nm" "$1" > "$TEST_ROOT/symbols" || fail "llvm-nm cannot read $1"
    if grep -E 'libc\+\+|libstdc\+\+' "$TEST_ROOT/loads"; then
        echo "$1 loads a C++ runtime"
        return 1
    fi
    if grep -E ' [A-Za-z] (___cxa_|___gxx_personality|__ZTVN10__cxxabiv1|__ZNSt3__1|__ZSt9terminate|__Znwm$|__ZdlPv$)' "$TEST_ROOT/symbols" | head -5 | grep .; then
        echo "$1 defines or imports C++ runtime symbols"
        return 1
    fi
}
cat > "$TEST_ROOT/dylib.cc" <<'EOF'
#include <string>
int main(int argc, char **argv) { try { throw std::string(argv[0]); } catch (...) { return argc; } }
EOF
printf 'void __cxa_throw(void) {}\nint main(void) { return 0; }\n' > "$TEST_ROOT/static.c"
"$cl/clang++" --no-default-config -fuse-ld=lld -target x86_64-apple-macos10.9 -isysroot "$sdk" \
    "$TEST_ROOT/dylib.cc" -o "$TEST_ROOT/dylib" || fail 'the libc++ fixture did not link'
"$cl/clang" --no-default-config -fuse-ld=lld -target x86_64-apple-macos10.9 -isysroot "$sdk" \
    "$TEST_ROOT/static.c" -o "$TEST_ROOT/static" || fail 'the static-runtime fixture did not link'
assert_run 1 runtime_free "$TEST_ROOT/dylib"
assert_output 'loads a C++ runtime'
assert_run 1 runtime_free "$TEST_ROOT/static"
assert_output 'defines or imports C++ runtime symbols'
pass 'a binary loading libc++, or carrying a copy of its runtime, is refused'
app="$STAGE_DIR/Mavericks WezTerm.app"
[ -d "$app" ] || { echo "no staged app at $app; build/build-native.sh stages it"; exit 77; }
for name in wezterm-gui wezterm wezterm-mux-server strip-ansi-escapes; do
    assert_run 0 runtime_free "$app/Contents/MacOS/$name"
done
"$cl/llvm-nm" "$app/Contents/MacOS/wezterm-gui" | grep ' [Tt] _hb_' > /dev/null ||
    fail 'wezterm-gui carries no harfbuzz, so this check no longer covers the C++ it was written for'
pass 'the shipped executables carry no C++ runtime, though wezterm-gui links harfbuzz'
