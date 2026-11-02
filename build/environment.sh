#!/bin/sh
# platform: macOS-only -- selects Mavericks compiler, SDK and target tools
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
. "$REPO_ROOT/build/msc.sh"
[ "$#" -gt 0 ] || fail 'usage: environment.sh COMMAND [ARG...]'
MODE=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
[ "$MODE" = native ] || fail 'local native milestone requires Mavericks; modern cross-host validation is pending'
own_work_root
SDKROOT=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
MACOSX_DEPLOYMENT_TARGET=10.9
TOOL_BIN=${MAVERGREEN_TOOL_BIN:-/usr/local/mavergreen/bin}
RUSTC=$TOOL_BIN/rustc
CARGO=$TOOL_BIN/cargo
AR=$TOOL_BIN/llvm-ar
RANLIB=$TOOL_BIN/llvm-ranlib
MAKE=$TOOL_BIN/gmake
CMAKE=$TOOL_BIN/shipyard-cmake
OTOOL=$TOOL_BIN/llvm-otool
LIPO=$TOOL_BIN/llvm-lipo
NM=$TOOL_BIN/llvm-nm
STRINGS=$TOOL_BIN/llvm-strings
for tool in "$RUSTC" "$CARGO" "$AR" "$RANLIB" "$MAKE" "$CMAKE" "$OTOOL" "$LIPO" "$NM" "$STRINGS"; do
    [ -x "$tool" ] || fail "required family tool missing: $tool"
done
mkdir -p "$WORK_ROOT/tools"
for language in cc cxx; do
    case "$language" in cc) compiler=$TOOL_BIN/clang ;; cxx) compiler=$TOOL_BIN/clang++ ;; esac
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
PATH=$TOOL_BIN:$PATH
export MODE SDKROOT MACOSX_DEPLOYMENT_TARGET RUSTC CARGO AR RANLIB MAKE CMAKE OTOOL LIPO NM STRINGS
export CC CXX CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER CARGO_TARGET_DIR CARGO_BUILD_JOBS
export CARGO_HTTP_TIMEOUT CARGO_HTTP_MULTIPLEXING CARGO_PROFILE_DEV_DEBUG CARGO_INCREMENTAL PATH
exec "$@"
