#!/bin/sh
# platform: host-agnostic
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
case "$#:${1:-}" in 0:|1:--verify) ;; *) fail 'usage: prepare.sh [--verify]' ;; esac
if [ "${1:-}" = --verify ]; then
    [ -f "$WORK_ROOT/.owner" ] && [ "$(cat "$WORK_ROOT/.owner")" = "$REPO_ROOT" ] || fail 'missing or foreign preparation owner'
    "$PYTHON" "$REPO_ROOT/build/provenance.py" verify "$WORK_ROOT" "$REPO_ROOT"
    exit 0
fi
lock_recipe
if [ -f "$WORK_ROOT/prepared.json" ]; then
    "$PYTHON" "$REPO_ROOT/build/provenance.py" owned "$WORK_ROOT" "$REPO_ROOT"
elif [ -e "$SOURCE_DIR" ] || [ -e "$CRATES_DIR" ]; then
    fail 'foreign source/crates without preparation provenance'
fi
sh "$REPO_ROOT/build/derive-upstream-version.sh" > /dev/null
version=$(sh "$SHIPYARD/resolve-version.sh" auto)
case "$version" in
    "$(upstream_version)"-mavericks.[1-9]*) ;;
    *) fail "VERSION $version is not a release of UPSTREAM_VERSION $(upstream_version); delete $REPO_ROOT/VERSION to re-derive" ;;
esac
. "$REPO_ROOT/components/wezterm/version"
"$PYTHON" "$REPO_ROOT/build/check-gitlinks.py" "$REPO_ROOT/components/wezterm/gitlinks.json" "$DIGEST" \
    "deps/freetype/freetype2=$FREETYPE2_DIGEST" "deps/freetype/libpng=$LIBPNG_DIGEST" \
    "deps/freetype/zlib=$ZLIB_DIGEST" "deps/harfbuzz/harfbuzz=$HARFBUZZ_DIGEST"
candidate=$(mktemp -d "$WORK_ROOT/preparing.XXXXXX")
publishing=0
cleanup_preparation() {
    cleanup_status=$?
    if [ -d "$candidate" ]; then
        if [ "$publishing" -eq 0 ]; then
            rm -rf "$candidate"
        else
            printf 'Interrupted publication; recovery data preserved: %s\n' "$candidate" >&2
        fi
    fi
    rmdir "$WORK_ROOT/.lock"
    return "$cleanup_status"
}
trap cleanup_preparation EXIT
sh "$SHIPYARD/fetch_pinned_source.sh" "$REPO" "$DIGEST" "$SHA256" "$candidate/source"
sh "$SHIPYARD/fetch_pinned_source.sh" "$FREETYPE2_REPO" "$FREETYPE2_DIGEST" "$FREETYPE2_SHA256" "$candidate/source/deps/freetype/freetype2"
sh "$SHIPYARD/fetch_pinned_source.sh" "$LIBPNG_REPO" "$LIBPNG_DIGEST" "$LIBPNG_SHA256" "$candidate/source/deps/freetype/libpng"
sh "$SHIPYARD/fetch_pinned_source.sh" "$ZLIB_REPO" "$ZLIB_DIGEST" "$ZLIB_SHA256" "$candidate/source/deps/freetype/zlib"
sh "$SHIPYARD/fetch_pinned_source.sh" "$HARFBUZZ_REPO" "$HARFBUZZ_DIGEST" "$HARFBUZZ_SHA256" "$candidate/source/deps/harfbuzz/harfbuzz"
cp "$candidate/source/Cargo.lock" "$candidate/source/Cargo.lock.upstream"
sh "$SHIPYARD/apply_patches.sh" "$candidate/source" "$REPO_ROOT/patches"
printf '%s\n' "$version" > "$candidate/source/.tag"
sh "$REPO_ROOT/build/prepare-crates.sh" "$candidate"
"$PYTHON" "$REPO_ROOT/build/provenance.py" record "$candidate" "$REPO_ROOT"
if [ -f "$WORK_ROOT/prepared.json" ]; then
    "$PYTHON" "$REPO_ROOT/build/provenance.py" owned "$WORK_ROOT" "$REPO_ROOT"
fi
publishing=1
if [ -d "$SOURCE_DIR" ]; then mv "$SOURCE_DIR" "$candidate/previous-source"; fi
if [ -d "$CRATES_DIR" ]; then mv "$CRATES_DIR" "$candidate/previous-crates"; fi
mv "$candidate/source" "$SOURCE_DIR"
mv "$candidate/crates" "$CRATES_DIR"
mv "$candidate/prepared.json" "$WORK_ROOT/prepared.json"
rm -rf "$candidate"
printf 'Prepared %s (upstream commit %s)\nWORK_ROOT=%s\n' "$version" "$DIGEST" "$WORK_ROOT"
