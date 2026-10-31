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
. "$REPO_ROOT/components/wezterm/version"
"$PYTHON" "$REPO_ROOT/build/check-gitlinks.py" "$REPO_ROOT/components/wezterm/gitlinks.json" "$DIGEST" \
    "deps/freetype/freetype2=$FREETYPE2_DIGEST" "deps/freetype/libpng=$LIBPNG_DIGEST" \
    "deps/freetype/zlib=$ZLIB_DIGEST" "deps/harfbuzz/harfbuzz=$HARFBUZZ_DIGEST"
. "$REPO_ROOT/build/msc.sh"
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
archive_source() {
    repository=${1#https://github.com/}; repository=${repository%.git}
    sh "$REPO_ROOT/build/fetch.sh" "https://api.github.com/repos/$repository/tarball/$2" "$3" "$WORK_ROOT/downloads" "$4-$2.tar.gz" "$5"
}
archive_source "$REPO" "$DIGEST" "$SHA256" wezterm "$candidate/source"
archive_source "$FREETYPE2_REPO" "$FREETYPE2_DIGEST" "$FREETYPE2_SHA256" FREETYPE2 "$candidate/freetype2"
archive_source "$LIBPNG_REPO" "$LIBPNG_DIGEST" "$LIBPNG_SHA256" LIBPNG "$candidate/libpng"
archive_source "$ZLIB_REPO" "$ZLIB_DIGEST" "$ZLIB_SHA256" ZLIB "$candidate/zlib"
archive_source "$HARFBUZZ_REPO" "$HARFBUZZ_DIGEST" "$HARFBUZZ_SHA256" HARFBUZZ "$candidate/harfbuzz"
mkdir -p "$candidate/source/deps/freetype" "$candidate/source/deps/harfbuzz"
for module in freetype2 libpng zlib; do
    destination=$candidate/source/deps/freetype/$module
    if [ -d "$destination" ]; then rmdir "$destination"; fi
    mv "$candidate/$module" "$destination"
done
if [ -d "$candidate/source/deps/harfbuzz/harfbuzz" ]; then rmdir "$candidate/source/deps/harfbuzz/harfbuzz"; fi
mv "$candidate/harfbuzz" "$candidate/source/deps/harfbuzz/harfbuzz"
cp "$candidate/source/Cargo.lock" "$candidate/source/Cargo.lock.upstream"
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in *..*|/*|*[!A-Za-z0-9._/-]*) fail 'invalid source patch entry' ;; esac
    (cd "$candidate/source" && patch -p1 -F 0 -V none < "$REPO_ROOT/patches/$entry")
done < "$REPO_ROOT/patches/series"
printf 'local-%s\n' "$DIGEST" > "$candidate/source/.tag"
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
printf 'Prepared local-%s\nWORK_ROOT=%s\n' "$DIGEST" "$WORK_ROOT"
