#!/bin/sh
# platform: host-agnostic -- packages and reads pkgs through shipyard's stevedore seams; the real stage needs this Mac's build
#   usage: tests/package.sh
#          Packages a stand-in app and updater with build/package-pkg.sh and reads the pkg back through
#          stevedore and artifact-facts.sh: components, floor, manifest, payload and the bin/ wrappers.
#          With a staged product app it then packages that, with WEZTERM_UPDATER_APP or an updater
#          build/build-updater.sh builds, and runs shipyard's artifact conformance on it.
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
package=$ROOT/build/package-pkg.sh
[ -f "$package" ] || fail 'build/package-pkg.sh is missing'
short=wezterm
id=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" identifier "$short" 2>/dev/null) ||
    { echo "the shipyard at $SHIPYARD_SCRIPTS does not register $short; install shipyard 1.0.677 or later"; exit 77; }
[ "$id" = dev.mavergreen.wezterm ] || fail "shipyard's registry gives $short the identifier $id"
upd_id=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-bundle-id "$short")
feed=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" feed "$short")
upd_rel=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-app "$short")
label=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" agent-label "$short")
STEVEDORE=$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh")
SOURCE_DATE_EPOCH=1761463588
export SOURCE_DATE_EPOCH
up=$(upstream_version)
V=$up-mavericks.7
name='Mavericks WezTerm.app'
tools='strip-ansi-escapes wezterm wezterm-gui wezterm-mux-server'

plist() {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n%s\n</dict></plist>\n' "$1"
}
fixture_app() {  # dir version [documents]
    c="$1/$name/Contents"
    mkdir -p "$c/MacOS"
    for tool in $tools; do printf '#!/bin/sh\necho %s\n' "$tool" > "$c/MacOS/$tool"; chmod 755 "$c/MacOS/$tool"; done
    docs=
    [ "${3:-documents}" != documents ] || docs='<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>Shell script</string></dict></array>'
    plist "<key>CFBundleIdentifier</key><string>dev.mavergreen.wezterm</string><key>CFBundleExecutable</key><string>wezterm-gui</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$2</string>$docs" > "$c/Info.plist"
    printf '%s\n' "$ROOT" > "$1/$name/.mavergreen-owner"
}
fixture_updater() {  # dir version
    c="$1/$short-updater.app/Contents"
    mkdir -p "$c/MacOS"
    printf '#!/bin/sh\n' > "$c/MacOS/$short-updater"; chmod 755 "$c/MacOS/$short-updater"
    plist "<key>CFBundleIdentifier</key><string>$upd_id</string><key>CFBundleExecutable</key><string>$short-updater</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$2</string><key>SUFeedURL</key><string>$feed</string>" > "$c/Info.plist"
}
refuse() {  # message, then package-pkg.sh's arguments
    message=$1; shift
    assert_run "$expect" sh "$package" "$@"
    assert_output "$message"
    [ -z "$(ls "$TEST_ROOT/out" 2>/dev/null)" ] || fail "a refused packaging left $(ls "$TEST_ROOT/out") behind"
}

f=$TEST_ROOT/f
fixture_app "$f/app" "$V"
fixture_updater "$f/upd" "$V"
fixture_app "$f/acceptance" "$V" none
fixture_app "$f/older" "$up-mavericks.6"
fixture_app "$f/partial" "$V"
rm "$f/partial/$name/Contents/MacOS/wezterm-mux-server"
fixture_updater "$f/older-upd" "$up-mavericks.6"
fixture_app "$f/foreign" 4.3-mavericks.1
fixture_updater "$f/foreign-upd" 4.3-mavericks.1
A=$f/app/$name
U=$f/upd/$short-updater.app
expect=2
refuse 'usage: build/package-pkg.sh'
refuse 'usage: build/package-pkg.sh' --app "$A" --updater-app "$U" --version "$V"
refuse 'usage: build/package-pkg.sh' --app "$A" --updater-app "$U" --version "$V" --out "$TEST_ROOT/out" --extra x
refuse 'usage: build/package-pkg.sh' --app "$A" --updater-app "$U" --version "$V" --out
expect=1
refuse "not UPSTREAM_VERSION $up" --app "$f/foreign/$name" --updater-app "$f/foreign-upd/$short-updater.app" --version 4.3-mavericks.1 --out "$TEST_ROOT/out"
refuse "is version $up-mavericks.6, not $V" --app "$f/older/$name" --updater-app "$U" --version "$V" --out "$TEST_ROOT/out"
refuse 'it is the acceptance bundle' --app "$f/acceptance/$name" --updater-app "$U" --version "$V" --out "$TEST_ROOT/out"
refuse 'has no Contents/MacOS/wezterm-mux-server' --app "$f/partial/$name" --updater-app "$U" --version "$V" --out "$TEST_ROOT/out"
refuse "$short-updater.app is version $up-mavericks.6, not $V" --app "$A" --updater-app "$f/older-upd/$short-updater.app" --version "$V" --out "$TEST_ROOT/out"
refuse 'is not the dev.mavergreen.wezterm bundle' --app "$U" --updater-app "$U" --version "$V" --out "$TEST_ROOT/out"
pass 'package-pkg.sh refuses usage errors, a foreign version, a bundle or updater at another version, the acceptance bundle and a bundle missing a tool'

ls -lR "$f" > "$TEST_ROOT/before"
assert_run 0 sh "$package" --app "$A" --updater-app "$U" --version "$V" --out "$TEST_ROOT/out"
ls -lR "$f" | cmp -s - "$TEST_ROOT/before" || fail 'package-pkg.sh changed the app or updater it packaged'
pkg=$TEST_ROOT/out/$short-$V.pkg
[ "$(ls "$TEST_ROOT/out")" = "$short-$V.pkg" ] || fail "the output holds $(ls "$TEST_ROOT/out"), not $short-$V.pkg"
assert_run 1 sh "$package" --app "$A" --updater-app "$U" --version "$V" --out "$TEST_ROOT/out"
assert_output 'already exists'

check_pkg() {  # pkg version app
    pkg=$1; v=$2; src=$3; b=$(basename "$pkg")
    sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" "$(dirname "$pkg")" "$v" "$ROOT" > "$TEST_ROOT/facts" ||
        fail "artifact-facts.sh failed: $(tail -3 "$TEST_ROOT/facts")"
    grep -qx end-of-facts "$TEST_ROOT/facts" || fail 'the fact stream is incomplete'
    grep -qx "pkg $b $v 10.9.5 $id" "$TEST_ROOT/facts" ||
        fail "the pkg is not $id $v with the 10.9.5 floor: $(grep "^pkg $b " "$TEST_ROOT/facts")"
    comps=$(awk -v b="$b" '$1 == "component" && $2 == b { printf "%s ", $3 }' "$TEST_ROOT/facts")
    [ "$comps" = "dev.mavergreen.base $id " ] || fail "the components are '$comps', not dev.mavergreen.base then $id"
    outside=$(awk -v b="$b" '$1 == "manifest-outside" && $2 == b { print $3 }' "$TEST_ROOT/facts" | sort | tr '\n' ' ')
    want=$(printf '%s\n' "Applications/$name" "$upd_rel" "Library/LaunchAgents/$label.plist" | sed 's/ /%20/g' | sort | tr '\n' ' ')
    [ "$outside" = "$want" ] || fail "the manifest's outside is '$outside', not '$want'"
    rm -rf "$TEST_ROOT/x" "$TEST_ROOT/root"
    "$STEVEDORE" expand "$pkg" "$TEST_ROOT/x" > /dev/null || fail "stevedore cannot expand $pkg"
    mkdir "$TEST_ROOT/root"
    for c in "$TEST_ROOT/x"/*.pkg; do tar -xf "$c/Payload" -C "$TEST_ROOT/root" || fail "cannot read $c/Payload"; done
    r=$TEST_ROOT/root
    m=$r/usr/local/mavergreen/$short/mavergreen.plist
    [ "$("$STEVEDORE" plist get "$m" version)" = "$v" ] || fail "the manifest's version is not $v"
    [ "$("$STEVEDORE" plist get "$m" product)" = "$short" ] || fail "the manifest's product is not $short"
    [ "$("$STEVEDORE" plist get "$m" appcast)" = "$feed" ] || fail "the manifest's appcast is not $feed"
    [ "$(ls "$r/usr/local/mavergreen/$short/bin" | tr '\n' ' ')" = "$tools " ] ||
        fail "the tree's bin holds $(ls "$r/usr/local/mavergreen/$short/bin" | tr '\n' ' '), not $tools"
    for tool in $tools; do
        w=$r/usr/local/mavergreen/$short/bin/$tool
        [ -f "$w" ] && [ ! -L "$w" ] && [ -x "$w" ] || fail "bin/$tool is not an executable file"
        printf '#!/bin/sh\nexec "/Applications/%s/Contents/MacOS/%s" "$@"\n' "$name" "$tool" | cmp -s - "$w" ||
            fail "bin/$tool is not the wrapper that execs the app's $tool: $(cat "$w")"
        cmp -s "$r/Applications/$name/Contents/MacOS/$tool" "$src/Contents/MacOS/$tool" ||
            fail "the payload's $tool is not the packaged app's"
    done
    cmp -s "$r/Applications/$name/Contents/Info.plist" "$src/Contents/Info.plist" ||
        fail "the payload's Info.plist is not the packaged app's"
    [ "$(ls -A "$r/Applications/$name")" = Contents ] ||
        fail "the payload's app holds $(ls -A "$r/Applications/$name" | tr '\n' ' '), not only Contents"
    stray=$(cd "$r" && find . \( -type f -o -type l \) | sed 's|^\./||' |
        grep -v -e "^usr/local/mavergreen/$short/" -e "^Applications/$name/Contents/" -e "^$upd_rel/" \
            -e "^Library/LaunchAgents/$label\.plist\$" -e '^usr/local/mavergreen/\.base/' || true)
    [ -z "$stray" ] || fail "the payload installs outside the tree, the app and the updater: $stray"
}
check_pkg "$pkg" "$V" "$A"
pass "the stand-in pkg is base then $id at the 10.9.5 floor; its manifest lists the app, updater and agent outside; bin/ holds one wrapper per tool"

app=$STAGE_DIR/$name
[ -d "$app" ] || { echo 'PASS: package (ran: stand-in; not run: the real stage, none is staged)'; exit 0; }
RV=$("$STEVEDORE" plist get "$app/Contents/Info.plist" CFBundleShortVersionString)
updater=${WEZTERM_UPDATER_APP:-}
if [ -z "$updater" ]; then
    updater=$TEST_ROOT/real-upd/$short-updater.app
    sh "$ROOT/build/build-updater.sh" --out "$updater" > "$TEST_ROOT/updater.log" 2>&1 ||
        { tail -20 "$TEST_ROOT/updater.log"; fail 'build-updater.sh failed'; }
fi
mkdir "$TEST_ROOT/dist"
assert_run 0 sh "$package" --app "$app" --updater-app "$updater" --version "$RV" --out "$TEST_ROOT/dist"
CL=$(sh "$ROOT/build/tools.sh" tree --root "$TOOL_ROOT" clang22)
LIPO=$CL/bin/llvm-lipo OTOOL=$CL/bin/llvm-otool NM=$CL/bin/llvm-nm
export LIPO OTOOL NM
check_pkg "$TEST_ROOT/dist/$short-$RV.pkg" "$RV" "$app"
assert_run 0 sh "$SHIPYARD_SCRIPTS/stand-in-feeds.sh" "$TEST_ROOT/dist" "$RV"
sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" "$TEST_ROOT/dist" "$RV" "$ROOT" > "$TEST_ROOT/facts"
assert_run 0 sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh" < "$TEST_ROOT/facts"
pass "the staged product $RV packages the same way and passes artifact conformance"
