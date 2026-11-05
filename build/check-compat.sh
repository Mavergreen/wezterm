#!/bin/sh
# platform: macOS-only -- reads Mach-O files with the pinned clang22 tree under /usr/local/mavergreen
#   usage: check-compat.sh [--app APP | MACHO...]
#          Runs shipyard's assert_binary_compatible.sh on each MACHO named or, with none, on every
#          Mach-O file inside APP (default: the staged "Mavericks WezTerm.app"). The guard reads them
#          with the pinned clang22's llvm-otool, llvm-lipo, llvm-nm and llvm-strings, allows x86_64
#          alone, requires no symbol to be defined, allows no weak import or selector, and reads
#          deviations from this repo's INGREDIENTS.md, whatever the caller's environment says. Exits 1
#          when a file fails, or when APP holds no Mach-O file; 2 on a usage error.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
usage() { printf 'usage: check-compat.sh [--app APP | MACHO...]\n' >&2; exit 2; }
app=
if [ "${1:-}" = --app ]; then
    [ "$#" -eq 2 ] || usage
    app=$2
    set --
elif [ "$#" -eq 0 ]; then
    app="$STAGE_DIR/Mavericks WezTerm.app"
fi
if [ -n "$app" ]; then
    [ -d "$app" ] || fail "no app at $app; build/build-native.sh stages it"
    list=$(mktemp "${TMPDIR:-/tmp}/check-compat.XXXXXX")
    trap 'rm -f "$list"' EXIT
    find "$app" -type f > "$list"
    while IFS= read -r file; do
        # platform: thin (32- or 64-bit, either byte order) and fat Mach-O magic numbers, read with od
        #           rather than parsed from file(1), whose wording differs between hosts
        case "$(od -An -tx1 -N4 "$file" | tr -d ' \n')" in
            cffaedfe|cefaedfe|feedface|feedfacf|cafebabe|bebafeca) set -- "$@" "$file" ;;
        esac
    done < "$list"
    [ "$#" -gt 0 ] || fail "no Mach-O file in $app"
fi
MODE=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
CLANG=$(sh "$REPO_ROOT/build/tools.sh" tree --root "$TOOL_ROOT" --mode "$MODE" clang22) ||
    fail "install the pinned clang22 release above (INGREDIENTS.md), then retry"
OTOOL=$CLANG/bin/llvm-otool
LIPO=$CLANG/bin/llvm-lipo
NM=$CLANG/bin/llvm-nm
STRINGS=$CLANG/bin/llvm-strings
MAVERICKS_ALLOW_ARCHS=x86_64
MAVERICKS_REQUIRE_DEFINED_SYMBOLS=
MAVERICKS_ALLOW_GUARDED_WEAK=
MAVERICKS_ALLOW_SELECTORS=
MAVERICKS_DEVIATIONS_ROOT=$REPO_ROOT
export OTOOL LIPO NM STRINGS MAVERICKS_ALLOW_ARCHS MAVERICKS_REQUIRE_DEFINED_SYMBOLS
export MAVERICKS_ALLOW_GUARDED_WEAK MAVERICKS_ALLOW_SELECTORS MAVERICKS_DEVIATIONS_ROOT
sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$@"
