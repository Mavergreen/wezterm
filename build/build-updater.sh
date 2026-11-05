#!/bin/sh
# platform: macOS-only -- verifies the prepared source the updater's icon comes from, which a Mac prepares
#   usage: build-updater.sh --out APP
#          Builds the Sparkle updater (CMakeLists.txt), x86_64 for 10.9 only, with the clang22 release
#          components/clang22 pins (shipyard's fetch_clang22.sh) and shipyard's MavericksToolchain.cmake,
#          in a fresh directory under the build root that is removed afterwards, and copies the app to
#          APP, which must not exist. Its icon is upstream's terminal.icns from the verified prepared
#          source, and its version that source's. The build log goes to stderr.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
usage() { printf 'usage: build-updater.sh --out APP\n' >&2; exit 2; }
[ "$#" -eq 2 ] && [ "$1" = --out ] || usage
out=$2
case "$out" in /*) ;; *) out=$(pwd)/$out ;; esac
[ ! -e "$out" ] && [ ! -L "$out" ] || fail "$out already exists"
sh "$REPO_ROOT/build/prepare.sh" --verify
CL=$(sh "$SHIPYARD_SCRIPTS/fetch_clang22.sh" "$REPO_ROOT/components/clang22") ||
    fail 'cannot get the pinned clang22 (shipyard fetch_clang22.sh said why above)'
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Sparkle updater" -- the compat
#       guard the updater's build runs reads it with clang22's readers, not the host's.
LIPO=$CL/bin/llvm-lipo
OTOOL=$CL/bin/llvm-otool
NM=$CL/bin/llvm-nm
STRINGS=$CL/bin/llvm-strings
export LIPO OTOOL NM STRINGS
cmake=$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)
[ -x "$cmake" ] || fail 'no shipyard-cmake; install the shipyard pkg'
work=$(mktemp -d "$WORK_ROOT/updater.XXXXXX")
trap 'rm -rf "$work"' EXIT
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Sparkle updater" -- one
#       configure per arch, with clang22 and the documented OBJC flags; x86_64 alone, since the product
#       ships no arm64 slice.
"$cmake" -S "$REPO_ROOT" -B "$work/x86_64" \
    -DCMAKE_TOOLCHAIN_FILE="$(dirname "$SHIPYARD_SCRIPTS")/MavericksToolchain.cmake" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9 \
    -DCMAKE_OBJC_COMPILER="$CL/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET=x86_64-apple-macos10.9 \
    -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld \
    -DWEZTERM_PREPARED_SOURCE="$SOURCE_DIR" >&2 || fail 'the updater did not configure'
"$cmake" --build "$work/x86_64" -v >&2 || fail 'the updater did not build'
mkdir -p "$(dirname "$out")"
cp -Rp "$work/x86_64/wezterm-updater.app" "$out"
printf 'build-updater: x86_64 updater at %s\n' "$out" >&2
