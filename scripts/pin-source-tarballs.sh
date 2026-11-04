#!/bin/sh
# platform: host-agnostic
#   usage: sh scripts/pin-source-tarballs.sh --check|--fill
#          CI-only (the pins bot, .github/workflows/pins-bot.yml, on Linux; or by hand on a modern Mac): needs
#          git, python3, curl, tar, shasum and shipyard (build/msc.sh). A 10.9 build never runs it.
#          Renovate moves DIGEST in components/wezterm/version but cannot compute what the build verifies
#          beside it. This computes, for the commit DIGEST names: SHA256, the SHA-256 of the tarball
#          build/prepare.sh fetches, GitHub's tarball of the commit, whose URL shipyard's
#          fetch_pinned_source.sh --url prints and whose one directory is <name>-<commit>;
#          COMMITTED, the commit's UTC committer time as YYYYMMDD.HHMMSS; and, for each of the four
#          submodules prepare.sh assembles, its gitlink at that commit as <NAME>_DIGEST and its tarball's
#          SHA-256 as <NAME>_SHA256; and components/wezterm/gitlinks.json from those. A tarball counts only
#          if it holds exactly its commit's tree: the commit is cloned with shipyard's clone_pinned.sh and
#          git compares the two, every path, mode, link and byte, the commit's own gitlinks being empty
#          directories. Nothing fetched is run. A parent whose gitlinks are not those four paths fails.
#          --check writes nothing and names each stale value; --fill writes them all with
#          scripts/pins-bot.sh apply, only after every row is verified, so a failure anywhere writes
#          nothing.
#          Exits (the pins bot relies on them): 0 the pins are current; 3 they were stale (and, with
#          --fill, are now written); 1 any failure (a tarball not its commit's tree, a failed fetch or
#          clone, a malformed pin, a failed command); 2 usage, and only usage; 130/143 on INT/TERM.
#          MAVERICKS_CODELOAD reaches fetch_pinned_source.sh --url (the tests serve a file:// tree).
set -eu
case "$#:${1:-}" in
    1:--check|1:--fill) MODE=$1 ;;
    *) echo 'usage: sh scripts/pin-source-tarballs.sh --check|--fill' >&2; exit 2 ;;
esac
T=; want=
trap 'rc=$?; [ -z "$T" ] || rm -rf "$T"; [ "$rc" = "$want" ] || rc=1; exit "$rc"' EXIT
trap 'want=130; exit 130' INT
trap 'want=143; exit 143' TERM
finish() { want=$1; exit "$1"; }
fail() { echo "pin-source-tarballs: $*" >&2; finish 1; }
HERE=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
PIN=components/wezterm/version
. "$HERE/build/msc.sh"
for script in mavericks_fetch.sh clone_pinned.sh fetch_pinned_source.sh; do
    [ -f "$SHIPYARD/$script" ] || fail "the shipyard at $SHIPYARD has no $script"
done
. "$SHIPYARD/mavericks_fetch.sh"
pinned() {
    [ "$(grep -c "^$1=" "$HERE/$PIN")" = 1 ] || fail "$PIN has no single $1= line"
    sed -n "s/^$1=//p" "$HERE/$PIN"
}
github_name() {
    case "$1" in https://github.com/*/*) ;; *) fail "$1 is not a GitHub repository URL" ;; esac
    n=${1#https://github.com/}; n=${n%.git}
    case "$n" in */*/*|/*|*/) fail "$1 is not a GitHub repository URL" ;; esac
    printf '%s\n' "$n"
}
is_commit() { case "$1" in *[!0-9a-f]*|'') return 1 ;; esac; [ "${#1}" -eq 40 ]; }
gitlinks() { git -C "$1" ls-tree -r HEAD | awk -F '\t' '$1 ~ /^160000 commit / { split($1, a, " "); print $2 " " a[3] }'; }
verify() {
    row=$1; repo=$2; commit=$3
    is_commit "$commit" || fail "$row: '$commit' is not a commit (40 hex digits)"
    name=$(github_name "$repo")
    url=$(sh "$SHIPYARD/fetch_pinned_source.sh" --url "$repo" "$commit") || fail "fetch_pinned_source.sh has no URL for $repo at $commit"
    sh "$SHIPYARD/clone_pinned.sh" "$repo" "$4" "$commit" "$T/$row.git" || fail "could not clone $repo at $commit"
    echo "==> $row: $url" >&2
    shipyard_curl "$url" "$T/$row.tar.gz" || fail "could not fetch $url"
    sha=$(shasum -a 256 < "$T/$row.tar.gz") || fail "could not hash $url"
    sha=${sha%% *}
    mkdir "$T/$row.x" && tar xzf "$T/$row.tar.gz" -C "$T/$row.x" || fail "could not extract $url"
    top=${name#*/}-$commit
    [ "$(ls -A "$T/$row.x")" = "$top" ] && [ -d "$T/$row.x/$top" ] ||
        fail "$url is not commit $commit's tree: it holds $(ls -A "$T/$row.x" | tr '\n' ' ')rather than the one directory $top"
    tree=$T/$row.x/$top
    links=$(gitlinks "$T/$row.git" | cut -d' ' -f1 | tr '\n' ' ')
    for link in $links; do
        [ -d "$tree/$link" ] && [ -z "$(ls -A "$tree/$link")" ] ||
            fail "$url is not commit $commit's tree: its gitlink $link is not an empty directory"
    done
    # platform: git status never looks at an entry named .git (a directory, or a gitdir file), never
    #           reports an empty directory, and does not look inside a gitlink's directory, so a tarball
    #           could carry any of these unseen; only the commit's own gitlinks may be empty directories.
    (cd "$tree" && find . \( -name .git -o -type d -empty \) -print) > "$T/$row.found" || fail "could not list $url's tree"
    extra=$(sed 's|^\./||' "$T/$row.found" |
        awk -v links="$links" 'BEGIN { n = split(links, l, " "); for (i = 1; i <= n; i++) ok[l[i]] = 1 } !($0 in ok)') ||
        fail "could not list $url's tree"
    [ -z "$extra" ] || { printf '%s\n' "$extra" | head -5 >&2; fail "$url is not commit $commit's tree: it holds the .git or empty directory above"; }
    # platform: some macOS gits fail with iconv_open(UTF-8, UTF-8-MAC) on unicode paths unless
    #           core.precomposeunicode is off; the rest make the comparison the same on every host
    #           rather than leave case, mode, symlink and line-ending handling to the host's git.
    diffs=$(git -c core.precomposeunicode=false -c core.ignorecase=false -c core.autocrlf=false -c core.fileMode=true \
        -c core.symlinks=true --git-dir="$T/$row.git/.git" --work-tree="$tree" status --porcelain --untracked-files=all --ignored) ||
        fail "git could not compare $url with commit $commit"
    [ -z "$diffs" ] || { printf '%s\n' "$diffs" | head -20 >&2; fail "$url is not commit $commit's tree (the differences above)"; }
    echo "    $sha (the commit's tree, file for file)" >&2
    rm -rf "$T/$row.tar.gz" "$T/$row.x" "$T/$row.found"
}
REPO=$(pinned REPO); REF=$(pinned REF); DIGEST=$(pinned DIGEST)
for key in SHA256 COMMITTED; do pinned "$key" > /dev/null; done
for row in FREETYPE2 LIBPNG ZLIB HARFBUZZ; do
    for key in REPO DIGEST SHA256; do pinned "${row}_$key" > /dev/null; done
done
T=$(mktemp -d "${TMPDIR:-/tmp}/pin-source-tarballs.XXXXXX")
verify WEZTERM "$REPO" "$DIGEST" "$REF"
values="DIGEST=$DIGEST SHA256=$sha"
seconds=$(git -C "$T/WEZTERM.git" log -1 --format=%ct HEAD) || fail "git could not read $DIGEST's committer time"
committed=$(python3 -c 'import sys, time; print(time.strftime("%Y%m%d.%H%M%S", time.gmtime(int(sys.argv[1]))))' "$seconds") ||
    fail "could not convert $DIGEST's committer time ($seconds)"
values="$values COMMITTED=$committed"
gitlinks "$T/WEZTERM.git" | sort > "$T/gitlinks"
cut -d' ' -f1 "$T/gitlinks" > "$T/paths"
printf '%s\n' deps/freetype/freetype2 deps/freetype/libpng deps/freetype/zlib deps/harfbuzz/harfbuzz > "$T/expected"
cmp -s "$T/paths" "$T/expected" || {
    diff "$T/expected" "$T/paths" | sed -n 's/^[<>]/  &/p' >&2
    fail "$DIGEST's submodules are not the four prepare.sh assembles (< expected, > at $DIGEST): review the change"
}
for row in FREETYPE2:deps/freetype/freetype2 LIBPNG:deps/freetype/libpng ZLIB:deps/freetype/zlib HARFBUZZ:deps/harfbuzz/harfbuzz; do
    key=${row%%:*}; path=${row#*:}
    commit=$(awk -v p="$path" '$1 == p { print $2 }' "$T/gitlinks")
    verify "$key" "$(pinned "${key}_REPO")" "$commit" HEAD
    values="$values ${key}_DIGEST=$commit ${key}_SHA256=$sha"
    rm -rf "$T/$key.git"
done
stale=0
for kv in $values; do
    key=${kv%%=*}; new=${kv#*=}; old=$(pinned "$key")
    [ "$old" = "$new" ] || { echo "stale: $PIN's $key is '$old', but it is $new" >&2; stale=3; }
done
cp "$HERE/$PIN" "$T/pin"
cp "$HERE/components/wezterm/gitlinks.json" "$T/gitlinks.json" 2>/dev/null || : > "$T/gitlinks.json"
mkdir -p "$T/probe/scripts" "$T/probe/components/wezterm"
cp "$HERE/scripts/pins-bot.sh" "$T/probe/scripts/"
cp "$T/pin" "$T/probe/components/wezterm/version"
cp "$T/gitlinks.json" "$T/probe/components/wezterm/gitlinks.json"
# shellcheck disable=SC2086  # KEY=VALUE words, each validated by pins-bot.sh
sh "$T/probe/scripts/pins-bot.sh" apply $values > /dev/null || fail "could not compose the pins"
cmp -s "$T/probe/components/wezterm/gitlinks.json" "$T/gitlinks.json" ||
    { echo "stale: components/wezterm/gitlinks.json does not record $DIGEST's gitlinks" >&2; stale=3; }
[ "$stale" = 3 ] || { echo "$PIN: current" >&2; finish 0; }
[ "$MODE" = --fill ] || { echo "run sh scripts/pin-source-tarballs.sh --fill and commit $PIN and components/wezterm/gitlinks.json" >&2; finish 3; }
# shellcheck disable=SC2086
sh "$HERE/scripts/pins-bot.sh" apply $values >&2 || fail "could not write the pins"
finish 3
