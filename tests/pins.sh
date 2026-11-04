#!/bin/sh
# platform: host-agnostic
#   usage: sh tests/pins.sh
#          scripts/pin-source-tarballs.sh, offline. Fixture git repositories stand in for wezterm and its
#          four submodules; their tarballs are made as GitHub's codeload makes them (git archive under
#          NAME-COMMIT/, the gitlinks as empty directories) and served from a file:// tree through shipyard's
#          own fetch_pinned_source.sh --url; a stand-in for shipyard's clone_pinned.sh clones the fixtures.
#          Exits 77 without a git that runs.
. "$(dirname "$0")/support/common.sh"
# platform: OS X 10.9's /usr/bin/git is a Command Line Tools stub, there whether or not they are installed.
git --version >/dev/null 2>&1 || { echo 'no git that runs; the pins script runs in CI'; exit 77; }
command -v python3 >/dev/null 2>&1 || { echo 'no python3; the pins script runs in CI'; exit 77; }
. "$ROOT/build/msc.sh"
T=$(CDPATH= cd -P -- "$TEST_ROOT" && pwd -P)
R=$T/repo
mkdir -p "$R/scripts" "$R/build" "$R/components/wezterm" "$T/shipyard" "$T/tmp" "$T/up"
cp "$ROOT/scripts/pin-source-tarballs.sh" "$ROOT/scripts/pins-bot.sh" "$R/scripts/"
cp "$ROOT/build/msc.sh" "$R/build/"
cp "$SHIPYARD/mavericks_fetch.sh" "$SHIPYARD/fetch_pinned_source.sh" "$T/shipyard/"
cat > "$T/shipyard/clone_pinned.sh" <<F
#!/bin/sh
n=\${1##*/}; n=\${n%.git}
git clone -q "$T/up/\$n" "\$4" && git -C "\$4" checkout -q "\$3" && [ "\$(git -C "\$4" rev-parse HEAD)" = "\$3" ]
F
commit() {
    repo=$1; shift
    (cd "$repo" && GIT_AUTHOR_DATE='2001-01-01T00:00:00+0000' GIT_COMMITTER_DATE="$1" \
        git -c user.name=t -c user.email=t@t commit -q -m "$2")
    git -C "$repo" rev-parse HEAD
}
gitlink() { git -C "$1" update-index --add --cacheinfo 160000 "$2" "$3"; }
tarball() {
    owner=$1; name=$2; commit=$3
    mkdir -p "$T/codeload/$owner/$name/tar.gz"
    git -C "$T/up/$name" archive --format=tar --prefix="$name-$commit/" "$commit" | gzip -n \
        > "$T/codeload/$owner/$name/tar.gz/$commit"
}
sum() { shasum -a 256 < "$T/codeload/$1/$2/tar.gz/$3" | cut -c1-64; }
sub() {
    g=$T/up/$2; mkdir -p "$g/src"
    git init -q "$g"
    echo "$2" > "$g/src/file.c"; printf '#!/bin/sh\n' > "$g/configure"; chmod +x "$g/configure"
    ln -s src/file.c "$g/link"
    git -C "$g" add -A
}
sub freetype freetype2
gitlink "$T/up/freetype2" 1111111111111111111111111111111111111111 subprojects/dlg
FT=$(commit "$T/up/freetype2" '2026-10-01T00:00:00+0000' freetype2)
sub glennrp libpng; PNG=$(commit "$T/up/libpng" '2026-10-01T00:00:00+0000' libpng)
sub madler zlib; ZL=$(commit "$T/up/zlib" '2026-10-01T00:00:00+0000' zlib)
sub harfbuzz harfbuzz; HB=$(commit "$T/up/harfbuzz" '2026-10-01T00:00:00+0000' harfbuzz)
W=$T/up/wezterm; mkdir -p "$W/term"; git init -q "$W"
echo wezterm > "$W/term/lib.rs"; printf '[submodule "x"]\n' > "$W/.gitmodules"
git -C "$W" add -A
gitlink "$W" "$FT" deps/freetype/freetype2
gitlink "$W" "$PNG" deps/freetype/libpng
gitlink "$W" "$ZL" deps/freetype/zlib
gitlink "$W" "$HB" deps/harfbuzz/harfbuzz
WZ=$(commit "$W" '2026-11-01T12:34:56+0200' wezterm)
tarball wezterm wezterm "$WZ"; tarball freetype freetype2 "$FT"; tarball glennrp libpng "$PNG"
tarball madler zlib "$ZL"; tarball harfbuzz harfbuzz "$HB"

write_pin() {  # write_pin DIGEST SHA256 COMMITTED FT FT_SHA PNG PNG_SHA ZL ZL_SHA HB HB_SHA > file
    printf 'REPO=https://github.com/wezterm/wezterm.git\nREF=main\nDIGEST=%s\nSHA256=%s\nCOMMITTED=%s\n' "$1" "$2" "$3"
    printf 'FREETYPE2_REPO=https://github.com/freetype/freetype2.git\nFREETYPE2_DIGEST=%s\nFREETYPE2_SHA256=%s\n' "$4" "$5"
    printf 'LIBPNG_REPO=https://github.com/glennrp/libpng.git\nLIBPNG_DIGEST=%s\nLIBPNG_SHA256=%s\n' "$6" "$7"
    printf 'ZLIB_REPO=https://github.com/madler/zlib.git\nZLIB_DIGEST=%s\nZLIB_SHA256=%s\n' "$8" "$9"
    printf 'HARFBUZZ_REPO=https://github.com/harfbuzz/harfbuzz.git\nHARFBUZZ_DIGEST=%s\nHARFBUZZ_SHA256=%s\n' "${10}" "${11}"
}
write_gitlinks() {  # write_gitlinks COMMIT FT PNG ZL HB > file
    printf '{\n  "commit": "%s",\n  "gitlinks": {\n' "$1"
    printf '    "deps/freetype/freetype2": "%s",\n    "deps/freetype/libpng": "%s",\n' "$2" "$3"
    printf '    "deps/freetype/zlib": "%s",\n    "deps/harfbuzz/harfbuzz": "%s"\n  }\n}\n' "$4" "$5"
}
Z=0000000000000000000000000000000000000000000000000000000000000000
D0=2222222222222222222222222222222222222222
PIN=$R/components/wezterm/version
GL=$R/components/wezterm/gitlinks.json
write_pin "$WZ" "$(sum wezterm wezterm "$WZ")" 20261101.103456 "$FT" "$(sum freetype freetype2 "$FT")" \
    "$PNG" "$(sum glennrp libpng "$PNG")" "$ZL" "$(sum madler zlib "$ZL")" "$HB" "$(sum harfbuzz harfbuzz "$HB")" > "$T/current.pin"
write_gitlinks "$WZ" "$FT" "$PNG" "$ZL" "$HB" > "$T/current.json"
put() { cp "$1" "$PIN"; cp "${2:-$T/current.json}" "$GL"; }
pins() {
    env TMPDIR="$T/tmp" SHIPYARD_SCRIPTS="$T/shipyard" MAVERICKS_CODELOAD="file://$T/codeload" SHIPYARD_FETCH_TRIES=1 \
        sh "$R/scripts/pin-source-tarballs.sh" "$@"
}
left() { ls -A "$T/tmp"; ls -A "$R/components/wezterm" | grep -vx -e version -e gitlinks.json || true; }
unchanged() {  # unchanged PIN JSON what
    cmp -s "$1" "$PIN" && cmp -s "$2" "$GL" || fail "$3 wrote: $(diff "$1" "$PIN"; diff "$2" "$GL")"
    [ -z "$(left)" ] || fail "$3 left $(left)"
}
set_key() { sed "s|^$1=.*|$1=$2|" "$3"; }

own_urls=$(cat "$ROOT/build/prepare.sh" "$ROOT/scripts/pin-source-tarballs.sh" | grep -v '^[[:space:]]*#' |
    grep -e 'github\.com/repos' -e 'codeload\.github' -e '/tarball/' -e '/tar\.gz/' || true)
grep -F '"$SHIPYARD/fetch_pinned_source.sh" "$' "$ROOT/build/prepare.sh" >/dev/null &&
    grep -F '"$SHIPYARD/fetch_pinned_source.sh" --url' "$ROOT/scripts/pin-source-tarballs.sh" >/dev/null &&
    [ -z "$own_urls" ] ||
    fail "the pins script must hash the tarball prepare.sh fetches: both must take it from shipyard's fetch_pinned_source.sh, neither may spell a URL of its own"
pass 'the pins script and prepare.sh name the same tarball'

put "$T/current.pin"
for a in '' --bogus '--check --fill' '--check extra' --; do
    # shellcheck disable=SC2086
    assert_run 2 pins $a
    assert_output 'usage'
done
unchanged "$T/current.pin" "$T/current.json" 'a usage error'
pass 'usage errors exit 2 and write nothing'

put "$T/current.pin"
touch -t 200001010000 "$PIN" "$GL"
assert_run 0 pins --check
assert_run 0 pins --fill
unchanged "$T/current.pin" "$T/current.json" 'a current pin'
[ -z "$(find "$PIN" "$GL" -newer "$T/current.pin")" ] || fail '--fill rewrote a current pin'
pass 'a current pin exits 0 and is not rewritten'

set_key SHA256 "$Z" "$T/current.pin" | set_key HARFBUZZ_SHA256 "$Z" /dev/stdin > "$T/stale.pin"
put "$T/stale.pin"
assert_run 3 pins --check
assert_output 'SHA256'
assert_output 'HARFBUZZ_SHA256'
unchanged "$T/stale.pin" "$T/current.json" '--check on a stale pin'
assert_run 3 pins --fill
unchanged "$T/current.pin" "$T/current.json" '--fill on a stale pin'
assert_run 0 pins --check
pass 'a stale pin exits 3; --fill writes the tarballs SHA-256s'

set_key COMMITTED 20261101.123456 "$T/current.pin" > "$T/committed.pin"
put "$T/committed.pin"
assert_run 3 pins --check
assert_output 'COMMITTED'
assert_run 3 pins --fill
unchanged "$T/current.pin" "$T/current.json" '--fill on a COMMITTED in local time'
pass "COMMITTED is the commit's UTC committer time; a wrong one is stale and fixed"

write_gitlinks "$WZ" "$FT" "$PNG" "$D0" "$HB" > "$T/stale.json"
put "$T/current.pin" "$T/stale.json"
assert_run 3 pins --check
assert_output 'gitlinks.json'
unchanged "$T/current.pin" "$T/stale.json" '--check on a stale gitlinks.json'
assert_run 3 pins --fill
unchanged "$T/current.pin" "$T/current.json" '--fill on a stale gitlinks.json'
pass 'gitlinks.json is regenerated from the pin'

echo zlib2 > "$T/up/zlib/src/file.c"; git -C "$T/up/zlib" add -A
ZL2=$(commit "$T/up/zlib" '2026-10-02T00:00:00+0000' zlib2); tarball madler zlib "$ZL2"
gitlink "$W" "$ZL2" deps/freetype/zlib
WZ2=$(commit "$W" '2026-11-02T01:02:03+0000' 'zlib moves'); tarball wezterm wezterm "$WZ2"
set_key DIGEST "$WZ2" "$T/current.pin" > "$T/renovate.pin"
put "$T/renovate.pin"
assert_run 3 pins --check
for key in SHA256 COMMITTED ZLIB_DIGEST ZLIB_SHA256; do assert_output "$key"; done
if grep '^stale:' "$TEST_ROOT/output" | grep -e FREETYPE2 -e LIBPNG -e HARFBUZZ >/dev/null; then fail "--check named a gitlink that did not move: $(cat "$T/output")"; fi
assert_run 3 pins --fill
write_pin "$WZ2" "$(sum wezterm wezterm "$WZ2")" 20261102.010203 "$FT" "$(sum freetype freetype2 "$FT")" \
    "$PNG" "$(sum glennrp libpng "$PNG")" "$ZL2" "$(sum madler zlib "$ZL2")" "$HB" "$(sum harfbuzz harfbuzz "$HB")" > "$T/moved.pin"
write_gitlinks "$WZ2" "$FT" "$PNG" "$ZL2" "$HB" > "$T/moved.json"
unchanged "$T/moved.pin" "$T/moved.json" '--fill after a moved gitlink'
assert_run 0 pins --check
pass 'a moved DIGEST whose zlib gitlink moved updates SHA256, COMMITTED, ZLIB_DIGEST, ZLIB_SHA256 and gitlinks.json'

put "$T/renovate.pin"
mv "$T/codeload/harfbuzz/harfbuzz/tar.gz/$HB" "$T/hb.tar.gz"
for mode in --check --fill; do
    assert_run 1 pins "$mode"
    assert_output 'could not fetch'
    unchanged "$T/renovate.pin" "$T/current.json" "$mode with harfbuzz's tarball unfetchable"
done
mv "$T/hb.tar.gz" "$T/codeload/harfbuzz/harfbuzz/tar.gz/$HB"
pass 'a fetch failure exits 1 and writes nothing, though earlier rows moved'

retar() {  # retar OWNER NAME COMMIT 'shell command': that tarball, changed by the command run in its tree
    rm -rf "$T/fake"; mkdir -p "$T/fake"
    gzip -dc "$T/codeload/$1/$2/tar.gz/$3" | tar xf - -C "$T/fake"
    (cd "$T/fake"/*/ && eval "$4")
    (cd "$T/fake" && tar cf - ./* | gzip -n > "$T/codeload/$1/$2/tar.gz/$3")
}
cp "$T/codeload/wezterm/wezterm/tar.gz/$WZ2" "$T/wz.tar.gz"
cp "$T/codeload/glennrp/libpng/tar.gz/$PNG" "$T/png.tar.gz"
missed=
while IFS='|' read -r owner name commit change; do
    eval "commit=$commit"
    retar "$owner" "$name" "$commit" "$change"
    for mode in --check --fill; do
        rc=0; pins "$mode" > "$TEST_ROOT/output" 2>&1 || rc=$?
        if [ "$rc" -ne 1 ] || ! grep -F "is not commit $commit's tree" "$TEST_ROOT/output" >/dev/null; then
            missed="$missed
  $name [$change] $mode: exit $rc: $(tail -1 "$TEST_ROOT/output")"
        fi
        unchanged "$T/renovate.pin" "$T/current.json" "$mode on a tampered $name tarball"
    done
    cp "$T/wz.tar.gz" "$T/codeload/wezterm/wezterm/tar.gz/$WZ2"
    cp "$T/png.tar.gz" "$T/codeload/glennrp/libpng/tar.gz/$PNG"
done <<'M'
wezterm|wezterm|$WZ2|echo tampered > term/lib.rs
wezterm|wezterm|$WZ2|echo extra > term/extra.rs
wezterm|wezterm|$WZ2|mkdir -p .git/hooks && echo x > .git/hooks/post-checkout
wezterm|wezterm|$WZ2|echo 'gitdir: /elsewhere' > term/.git
wezterm|wezterm|$WZ2|mkdir term/empty
wezterm|wezterm|$WZ2|echo x > deps/freetype/zlib/zlib.h
wezterm|wezterm|$WZ2|rmdir deps/harfbuzz/harfbuzz
glennrp|libpng|$PNG|echo tampered > src/file.c
glennrp|libpng|$PNG|chmod -x configure
M
[ -z "$missed" ] || fail "tarballs that are not their commit's tree were not refused:$missed"
for shape in file empty legacy; do
    rm -rf "$T/fake"; mkdir -p "$T/fake"
    case "$shape" in
        file) echo libpng > "$T/fake/libpng-$PNG" ;;
        legacy) gzip -dc "$T/png.tar.gz" | tar xf - -C "$T/fake"; mv "$T/fake/libpng-$PNG" "$T/fake/glennrp-libpng-$(printf %.7s "$PNG")" ;;
    esac
    tar cf - -C "$T/fake" . | gzip -n > "$T/codeload/glennrp/libpng/tar.gz/$PNG"
    assert_run 1 pins --fill
    assert_output "is not commit $PNG's tree"
    unchanged "$T/renovate.pin" "$T/current.json" "--fill on a libpng tarball whose one directory is not libpng-COMMIT ($shape)"
    cp "$T/png.tar.gz" "$T/codeload/glennrp/libpng/tar.gz/$PNG"
done
mkdir -p "$T/badsed"
printf '#!/bin/sh
case "$*" in *"s/^REPO=//p"*) exit 2 ;; esac
exec /usr/bin/sed "$@"
' > "$T/badsed/sed"; chmod +x "$T/badsed/sed"
rc=0; (PATH="$T/badsed:$PATH"; pins --check) > "$TEST_ROOT/output" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a command's own status 2 must exit 1, since the pins bot reads 2 as usage and 3 as stale: exit $rc"
pass "a tampered parent or submodule tarball exits 1 and writes nothing"

gitlink "$W" "$PNG" deps/extra/libpng
WZ3=$(commit "$W" '2026-11-03T00:00:00+0000' 'a fifth submodule'); tarball wezterm wezterm "$WZ3"
set_key DIGEST "$WZ3" "$T/current.pin" > "$T/fifth.pin"
put "$T/fifth.pin"
assert_run 1 pins --fill
assert_output 'deps/extra/libpng'
unchanged "$T/fifth.pin" "$T/current.json" 'a new submodule'
git -C "$W" rm -q --cached deps/extra/libpng deps/harfbuzz/harfbuzz
WZ4=$(commit "$W" '2026-11-04T00:00:00+0000' 'harfbuzz goes'); tarball wezterm wezterm "$WZ4"
set_key DIGEST "$WZ4" "$T/current.pin" > "$T/fewer.pin"
put "$T/fewer.pin"
assert_run 1 pins --fill
assert_output 'deps/harfbuzz/harfbuzz'
unchanged "$T/fewer.pin" "$T/current.json" 'a removed submodule'
pass 'a parent whose submodules are not the four the build assembles exits 1, naming the path'

for bad in 'DIGEST=2222' "DIGEST=$D0" 'REPO=https://example.com/wezterm.git'; do
    set_key "${bad%%=*}" "${bad#*=}" "$T/current.pin" > "$T/bad.pin"
    put "$T/bad.pin"
    assert_run 1 pins --fill
    unchanged "$T/bad.pin" "$T/current.json" "a pin with $bad"
done
grep -v '^LIBPNG_SHA256=' "$T/current.pin" > "$T/bad.pin"; put "$T/bad.pin"
assert_run 1 pins --fill
assert_output 'LIBPNG_SHA256'
unchanged "$T/bad.pin" "$T/current.json" 'a pin without LIBPNG_SHA256'
{ cat "$T/current.pin"; echo "ZLIB_DIGEST=$D0"; } > "$T/bad.pin"; put "$T/bad.pin"
assert_run 1 pins --fill
assert_output 'ZLIB_DIGEST'
unchanged "$T/bad.pin" "$T/current.json" 'a pin with ZLIB_DIGEST twice'
pass 'a malformed pin, an unknown commit or a key missing or repeated exits 1 and writes nothing'
