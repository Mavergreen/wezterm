#!/bin/sh
# platform: macOS-only -- selects Mavericks compiler, SDK and target tools
#   usage: environment.sh [--mode native|cross] COMMAND [ARG...]
#          Runs COMMAND with the pinned products for the mode (default: this host's, as shipyard's
#          mavericks_mode.sh says). native: rust, clang22 and the 10.9 SDK for everything.
#          cross: rust-cross and clang22-cross build the x86_64 10.9 target; build scripts and proc
#          macros build for the host with the runner's /usr/bin/clang and its own SDK, so SDKROOT is
#          set only inside the target compiler wrappers.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
. "$REPO_ROOT/build/msc.sh"
usage() { fail 'usage: environment.sh [--mode native|cross] COMMAND [ARG...]'; }
MODE=
if [ "${1:-}" = --mode ]; then
    [ "$#" -ge 2 ] || usage
    MODE=$2
    shift 2
    case "$MODE" in native|cross) ;; *) usage ;; esac
fi
[ "$#" -gt 0 ] || usage
[ -n "$MODE" ] || MODE=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
sh "$REPO_ROOT/build/tools.sh" check --root "$TOOL_ROOT" --mode "$MODE" ||
    fail "install the pinned releases above (INGREDIENTS.md), then retry; build/tools.sh check --root $TOOL_ROOT --mode $MODE"
own_work_root
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
MACOSX_DEPLOYMENT_TARGET=10.9
pinned_rust "$MODE"
CLANG_BIN=$(sh "$REPO_ROOT/build/tools.sh" tree --root "$TOOL_ROOT" --mode "$MODE" clang22)/bin
MAKE_BIN=$(sh "$REPO_ROOT/build/tools.sh" tree --root "$TOOL_ROOT" --mode "$MODE" make)/bin
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
case "$MODE" in native) tools=$WORK_ROOT/tools ;; cross) tools=$WORK_ROOT/tools/cross ;; esac
mkdir -p "$tools"
for language in cc cxx; do
    case "$language" in cc) compiler=$CLANG_BIN/clang ;; cxx) compiler=$CLANG_BIN/clang++ ;; esac
    "$PYTHON" - "$tools/$language" "$compiler" "$SDK" "$MODE" <<'PY'
import os, sys
quote = lambda s: "'" + s.replace("'", "'\\''") + "'"
path, compiler, sdk, mode = sys.argv[1:]
if mode == 'native':
    text = '#!/bin/sh\nexec %s -isysroot %s "$@"\n' % (quote(compiler), quote(sdk))
else:
    text = ('#!/bin/sh\nSDKROOT=%s\nexport SDKROOT\nexec %s -target x86_64-apple-macos10.9 -isysroot %s "$@"\n'
            % (quote(sdk), quote(compiler), quote(sdk)))
if not os.path.exists(path) or open(path).read() != text:
    with open(path, 'w') as target:
        target.write(text)
    os.chmod(path, 0o755)
PY
done
CC=$tools/cc
CXX=$tools/cxx
CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER=$CXX
if [ "$MODE" = native ]; then
    SDKROOT=$SDK
    PATH=$RUST_BIN:$CLANG_BIN:$MAKE_BIN:$PATH
    export SDKROOT
else
    unset SDKROOT HOST_CC HOST_CXX
    CC_x86_64_apple_darwin=$CC
    CXX_x86_64_apple_darwin=$CXX
    export CC_x86_64_apple_darwin CXX_x86_64_apple_darwin
    host=$("$RUSTC" -vV | sed -n 's/^host: //p')
    case "$host" in
        x86_64-apple-darwin) ;;
        *-apple-darwin)
            case "$host" in *[!a-z0-9_-]*) fail "unexpected host triple from $RUSTC -vV: $host" ;; esac
            # platform: cargo and cc-rs name per-triple variables with the triple's dashes as
            #           underscores, upper case for cargo's
            host_cc=$(printf '%s' "$host" | tr - _)
            host_linker=CARGO_TARGET_$(printf '%s' "$host_cc" | tr a-z A-Z)_LINKER
            HOST_CC=/usr/bin/clang
            HOST_CXX=/usr/bin/clang++
            eval "CC_$host_cc=\$HOST_CC CXX_$host_cc=\$HOST_CXX $host_linker=\$HOST_CC"
            export HOST_CC HOST_CXX "CC_$host_cc" "CXX_$host_cc" "$host_linker"
            ;;
        *) fail "cross mode needs a macOS host; $RUSTC -vV says host: $host" ;;
    esac
    PATH=$RUST_BIN:$MAKE_BIN:$PATH
fi
CARGO_TARGET_DIR=$TARGET_DIR
CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-6}
CARGO_HTTP_TIMEOUT=${CARGO_HTTP_TIMEOUT:-60}
CARGO_HTTP_MULTIPLEXING=false
CARGO_PROFILE_DEV_DEBUG=${CARGO_PROFILE_DEV_DEBUG:-0}
CARGO_PROFILE_RELEASE_DEBUG=${CARGO_PROFILE_RELEASE_DEBUG:-0}
CARGO_INCREMENTAL=${CARGO_INCREMENTAL:-0}
export MODE MACOSX_DEPLOYMENT_TARGET RUSTC CARGO AR RANLIB MAKE CMAKE OTOOL LIPO NM STRINGS
export CC CXX CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER CARGO_TARGET_DIR CARGO_BUILD_JOBS
export CARGO_HTTP_TIMEOUT CARGO_HTTP_MULTIPLEXING CARGO_PROFILE_DEV_DEBUG CARGO_PROFILE_RELEASE_DEBUG
export CARGO_INCREMENTAL PATH
exec "$@"
