#!/bin/sh
# platform: macOS-only -- links fixture Mach-O files with the pinned clang22 and reads the staged app
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
guard=$ROOT/build/check-compat.sh
[ -f "$guard" ] || fail 'build/check-compat.sh is missing'
CL=$(sh "$ROOT/build/tools.sh" tree --root "$TOOL_ROOT" clang22) ||
    fail 'the pinned clang22 is not installed (build/tools.sh tree clang22)'
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
link() {
    out=$1; shift
    "$CL/bin/clang" --no-default-config -target x86_64-apple-macos10.9 -isysroot "$SDK" -fuse-ld=lld \
        "$@" -o "$TEST_ROOT/$out" "$TEST_ROOT/$out.c" || fail "could not link the fixture $out"
}
printf 'int main(void) { return 0; }\n' > "$TEST_ROOT/clean.c"
cp "$TEST_ROOT/clean.c" "$TEST_ROOT/minos11.c"
printf 'struct timespec;\nint clock_gettime(int, struct timespec *);\nint main(void) { return clock_gettime(0, 0); }\n' \
    > "$TEST_ROOT/gettime.c"
printf 'struct timespec;\nint clock_gettime(int, struct timespec *) __attribute__((weak_import));\nint main(void) { return clock_gettime ? clock_gettime(0, 0) : 0; }\n' \
    > "$TEST_ROOT/weak.c"
link clean
link minos11 -Wl,-platform_version,macos,11.0,10.9
link gettime -Wl,-U,_clock_gettime
link weak -Wl,-U,_clock_gettime

# platform: the readers on PATH are 10.9's Command Line Tools stubs on a box without them, so the guard
#           must take clang22's whatever the caller exported or put first on PATH.
mkdir "$TEST_ROOT/stubs"
for tool in otool lipo nm strings; do
    printf '#!/bin/sh\necho "stub %s" >&2\nexit 9\n' "$tool" > "$TEST_ROOT/stubs/$tool"
    chmod +x "$TEST_ROOT/stubs/$tool"
done
mkdir -p "$TEST_ROOT/lenient"
printf '# Build ingredients\n\n## Conformance deviations\n\n- sdk-pin: every file, for this test\n' > "$TEST_ROOT/lenient/INGREDIENTS.md"
caller() {
    env PATH="$TEST_ROOT/stubs:$PATH" OTOOL=/usr/bin/false LIPO=/usr/bin/false NM=/usr/bin/false STRINGS=/usr/bin/false \
        MAVERICKS_ALLOW_ARCHS='x86_64 arm64' MAVERICKS_REQUIRE_DEFINED_SYMBOLS=_not_defined_anywhere \
        MAVERICKS_ALLOW_GUARDED_WEAK=_clock_gettime MAVERICKS_DEVIATIONS_ROOT="$TEST_ROOT/lenient" "$@"
}

assert_run 0 caller sh "$guard" "$TEST_ROOT/clean"
assert_output 'compat guard: 1 binaries clean (x86_64'
pass 'a 10.9 fixture passes with clang22 readers, whatever readers, arches or required symbols the caller set'

assert_run 1 caller sh "$guard" "$TEST_ROOT/minos11"
assert_output 'records minos 11.0'
assert_run 1 caller sh "$guard" "$TEST_ROOT/clean" "$TEST_ROOT/minos11"
assert_output 'records minos 11.0'
pass 'an 11.0 minos fails, alone or beside a clean binary, despite a caller deviation excusing every file'

assert_run 1 caller sh "$guard" "$TEST_ROOT/gettime"
assert_output '_clock_gettime'
assert_run 1 caller sh "$guard" "$TEST_ROOT/weak"
assert_output '_clock_gettime'
pass 'an import of _clock_gettime fails, hard or weak, despite a caller allowing it weak'

app=$TEST_ROOT/Fixture.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/deep"
assert_run 1 sh "$guard" --app "$app"
assert_output 'no Mach-O file in'
cp "$TEST_ROOT/clean" "$app/Contents/MacOS/fixture"
cp "$TEST_ROOT/clean.c" "$app/Contents/Resources/source.c"
printf '#!/bin/sh\nexit 0\n' > "$app/Contents/Resources/helper.sh"
chmod +x "$app/Contents/Resources/helper.sh"
assert_run 0 sh "$guard" --app "$app"
assert_output 'compat guard: 1 binaries clean'
cp "$TEST_ROOT/minos11" "$app/Contents/Resources/deep/hidden"
assert_run 1 sh "$guard" --app "$app"
assert_output "$app/Contents/Resources/deep/hidden: x86_64 records minos 11.0"
assert_run 2 sh "$guard" --app
assert_run 2 sh "$guard" --app "$app" "$TEST_ROOT/clean"
pass 'an app is guarded on every Mach-O file anywhere inside it, and only those; an app without one fails closed'

staged="$STAGE_DIR/Mavericks WezTerm.app"
[ -d "$staged" ] || { echo "no staged app at $staged; build/build-native.sh stages it"; exit 77; }
# platform: not a case inside $( ), which 10.9's bash 3.2 cannot parse
find "$staged" -type f > "$TEST_ROOT/staged-files"
machos=0
while IFS= read -r file; do
    case "$(od -An -tx1 -N4 "$file" | tr -d ' \n')" in
        cffaedfe|cefaedfe|feedface|feedfacf|cafebabe|bebafeca) machos=$((machos + 1)) ;;
    esac
done < "$TEST_ROOT/staged-files"
[ "$machos" -ge 4 ] || fail "the staged app holds only $machos Mach-O files"
assert_run 0 sh "$guard"
assert_output "compat guard: $machos binaries clean (x86_64, pinned minos and SDK per arch, no post-10.9 imports)"
cp "$TEST_ROOT/output" "$EVIDENCE_DIR/compat-guard.log"
pass "the staged app's $machos Mach-O files pass the guard"
