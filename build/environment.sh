#!/bin/sh
# platform: macOS-only -- selects Mavericks compiler, SDK and target tools
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
. "$REPO_ROOT/build/msc.sh"
[ "$#" -gt 0 ] || fail 'usage: environment.sh COMMAND [ARG...]'
MODE=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
[ "$MODE" = native ] || fail 'local native milestone requires Mavericks; modern cross-host validation is pending'
sh "$REPO_ROOT/build/tools.sh" check --root "$TOOL_ROOT" --mode "$MODE" ||
    fail "install the pinned releases above (INGREDIENTS.md), then retry; build/tools.sh check --root $TOOL_ROOT"
own_work_root
SDKROOT=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
MACOSX_DEPLOYMENT_TARGET=10.9
pinned_rust "$MODE"
CLANG_BIN=$TREES/clang22/bin
MAKE_BIN=$TREES/make/bin
RUSTC=$RUST_BIN/rustc
CARGO=$RUST_BIN/cargo
AR=$CLANG_BIN/llvm-ar
RANLIB=$CLANG_BIN/llvm-ranlib
MAKE=$MAKE_BIN/gmake
CMAKE=$TREES/shipyard/bin/shipyard-cmake
OTOOL=$CLANG_BIN/llvm-otool
LIPO=$CLANG_BIN/llvm-lipo
NM=$CLANG_BIN/llvm-nm
STRINGS=$CLANG_BIN/llvm-strings
for tool in "$RUSTC" "$CARGO" "$AR" "$RANLIB" "$MAKE" "$CMAKE" "$OTOOL" "$LIPO" "$NM" "$STRINGS"; do
    [ -x "$tool" ] || fail "required family tool missing: $tool"
done
mkdir -p "$WORK_ROOT/tools"
for language in cc cxx; do
    case "$language" in cc) compiler=$CLANG_BIN/clang ;; cxx) compiler=$CLANG_BIN/clang++ ;; esac
    "$PYTHON" - "$WORK_ROOT/tools/$language" "$compiler" "$SDKROOT" <<'PY'
import os, sys
quote = lambda s: "'" + s.replace("'", "'\\''") + "'"
path, compiler, sdk = sys.argv[1:]
text = '#!/bin/sh\nexec %s -isysroot %s "$@"\n' % (quote(compiler), quote(sdk))
if not os.path.exists(path) or open(path).read() != text:
    with open(path, 'w') as target:
        target.write(text)
    os.chmod(path, 0o755)
PY
done
CC=$WORK_ROOT/tools/cc
CXX=$WORK_ROOT/tools/cxx
CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER=$CXX
CARGO_TARGET_DIR=$TARGET_DIR
CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-6}
CARGO_HTTP_TIMEOUT=${CARGO_HTTP_TIMEOUT:-60}
CARGO_HTTP_MULTIPLEXING=false
CARGO_PROFILE_DEV_DEBUG=${CARGO_PROFILE_DEV_DEBUG:-0}
CARGO_INCREMENTAL=${CARGO_INCREMENTAL:-0}
PATH=$RUST_BIN:$CLANG_BIN:$MAKE_BIN:$PATH
export MODE SDKROOT MACOSX_DEPLOYMENT_TARGET RUSTC CARGO AR RANLIB MAKE CMAKE OTOOL LIPO NM STRINGS
export CC CXX CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER CARGO_TARGET_DIR CARGO_BUILD_JOBS
export CARGO_HTTP_TIMEOUT CARGO_HTTP_MULTIPLEXING CARGO_PROFILE_DEV_DEBUG CARGO_INCREMENTAL PATH
exec "$@"
