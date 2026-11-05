#!/bin/sh
# platform: host-agnostic -- shipyard's stevedore seams build and read the pkg
#   usage: build/package-pkg.sh --app APP --updater-app UPDATER --version V --out DIR
#          Packages APP (the product bundle build/stage-app.sh stages, never the --acceptance one) as
#          /Applications/Mavericks WezTerm.app, UPDATER (build/build-updater.sh) as the Sparkle updater,
#          and the tree /usr/local/mavergreen/wezterm, whose bin/ holds one sh wrapper per executable in
#          the app, as DIR/wezterm-V.pkg: dev.mavergreen.base first, then dev.mavergreen.wezterm, with the
#          10.9.5 floor. V is UPSTREAM_VERSION with its -mavericks.N, and both bundles' version. The pkg
#          appears in DIR only once it is made; APP and UPDATER are not changed. A caller without git
#          exports SOURCE_DATE_EPOCH, which stamps every file's mtime.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
usage() { printf 'usage: build/package-pkg.sh --app APP --updater-app UPDATER --version V --out DIR\n' >&2; exit 2; }
app=; updater=; V=; out=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app|--updater-app|--version|--out) [ "$#" -ge 2 ] || usage ;;
        *) usage ;;
    esac
    case "$1" in
        --app) app=$2 ;;
        --updater-app) updater=$2 ;;
        --version) V=$2 ;;
        --out) out=$2 ;;
    esac
    shift 2
done
[ -n "$app" ] && [ -n "$updater" ] && [ -n "$V" ] && [ -n "$out" ] || usage
short=wezterm
name='Mavericks WezTerm.app'
tools='wezterm wezterm-gui wezterm-mux-server strip-ansi-escapes'
id=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" identifier "$short" 2>/dev/null) ||
    fail "the shipyard at $SHIPYARD_SCRIPTS does not register $short"
up=$(upstream_version)
case "$V" in
    "$up"-mavericks.[1-9]*) ;;
    *) fail "--version $V is not UPSTREAM_VERSION $up with a -mavericks.N" ;;
esac
STEVEDORE=$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh") || fail 'cannot fetch stevedore'
info() { "$STEVEDORE" plist get "$1/Contents/Info.plist" "$2" 2>/dev/null; }
[ "$(info "$app" CFBundleIdentifier || true)" = dev.mavergreen.wezterm ] ||
    fail "$app is not the dev.mavergreen.wezterm bundle"
appv=$(info "$app" CFBundleShortVersionString || true)
[ "$appv" = "$V" ] || fail "$app is version $appv, not $V"
# spec: PORT.md "Staging and local acceptance" -- only the private acceptance bundle drops upstream's
#       document types, so a bundle without them is that one and never ships.
"$STEVEDORE" plist has "$app/Contents/Info.plist" CFBundleDocumentTypes > /dev/null 2>&1 ||
    fail "$app declares no document types: it is the acceptance bundle; stage the product with build/stage-app.sh"
for tool in $tools; do
    [ -f "$app/Contents/MacOS/$tool" ] && [ -x "$app/Contents/MacOS/$tool" ] ||
        fail "$app has no Contents/MacOS/$tool"
done
updv=$(info "$updater" CFBundleShortVersionString || true)
[ "$updv" = "$V" ] || fail "$updater is version $updv, not $V"

mkdir -p "$out"
out=$(CDPATH= cd "$out" && pwd)
pkg=$out/$short-$V.pkg
[ ! -e "$pkg" ] || fail "$pkg already exists"
work=$(mktemp -d "${TMPDIR:-/tmp}/wezterm-package.XXXXXX")
trap 'rm -rf "$work"' EXIT
root=$work/root
tree=$root/usr/local/mavergreen/$short
mkdir -p "$root/Applications/$name" "$tree/bin" "$work/scripts" "$work/component"
# platform: only Contents ships; the stage's ownership and receipt files sit beside it
COPYFILE_DISABLE=1 cp -Rp "$app/Contents" "$root/Applications/$name/Contents"
# spec: INGREDIENTS.md "Commands on PATH" -- upstream finds wezterm-gui and wezterm-mux-server beside
#       the path the CLI was started by, unresolved, so a symlink into the app finds neither; a wrapper
#       execs the app's own copy.
for tool in $tools; do
    printf '#!/bin/sh\nexec "/Applications/%s/Contents/MacOS/%s" "$@"\n' "$name" "$tool" > "$tree/bin/$tool"
    chmod 755 "$tree/bin/$tool"
done
sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage "$root" --product "$short" --name 'WezTerm for Mavericks' \
    --version "$V" --updater-app "$updater" --scripts-out "$work/scripts" >&2
find "$root" -name '._*' -exec rm -f {} + 2> /dev/null || true
comp=$work/component/$short.pkg
sh "$SHIPYARD_SCRIPTS/build_component_pkg.sh" --root "$root" --identifier "$id" --version "$V" \
    --install-location / --scripts "$work/scripts" --out "$comp" > /dev/null
sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" --identifier "$id" --title 'WezTerm for Mavericks' \
    --component "$comp" --out "$work/product.pkg" --host-arch x86_64 --min-os 10.9.5 --require-scripts > /dev/null
mv "$work/product.pkg" "$pkg"
printf 'package-pkg: %s\n' "$pkg" >&2
