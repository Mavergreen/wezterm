#!/bin/sh
# platform: host-agnostic
#   usage: tools.sh check [--root DIR] [--mode native|cross]
#          tools.sh tree [--root DIR] [--mode native|cross] COMPONENT
#          Each family product the build runs must be installed at exactly the release its pin names,
#          read from <DIR>/usr/local/mavergreen/<short>/mavergreen.plist (DIR defaults to /, the mode to
#          this host's). A release's native and cross products share one pin: rust and rust-cross read
#          components/rust/version, clang22 and clang22-cross components/clang22/version. Reports every
#          mismatch, then exits 1; exits 2 on a usage error. tree checks only the product COMPONENT
#          (rust, clang22 or make) names in that mode and, when it is at its pin, prints its tree,
#          <DIR>/usr/local/mavergreen/<short>.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
PYTHON=${PYTHON:-python}
usage() {
    printf 'usage: tools.sh check [--root DIR] [--mode native|cross]\n       tools.sh tree [--root DIR] [--mode native|cross] COMPONENT\n' >&2
    exit 2
}
case "${1:-}" in check|tree) action=$1 ;; *) usage ;; esac
shift
root=/
mode=
component=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --root) [ "$#" -ge 2 ] || usage; root=$2; shift 2 ;;
        --mode) [ "$#" -ge 2 ] || usage; mode=$2; shift 2 ;;
        -*) usage ;;
        *) [ "$action" = tree ] && [ -z "$component" ] || usage; component=$1; shift ;;
    esac
done
if [ -z "$mode" ]; then
    . "$REPO_ROOT/build/msc.sh"
    mode=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
fi
case "$mode" in
    native) products='rust:rust clang22:clang22 make:make' ;;
    cross) products='rust-cross:rust clang22-cross:clang22 make:make' ;;
    *) usage ;;
esac
if [ "$action" = tree ]; then
    selected=
    for product in $products; do
        [ "${product#*:}" != "$component" ] || selected=$product
    done
    [ -n "$selected" ] || usage
    products=$selected
fi
"$PYTHON" - "$REPO_ROOT" "${root%/}" $products <<'PY'
import os, plistlib, re, sys
repo, root, products = sys.argv[1], sys.argv[2], sys.argv[3:]
load = getattr(plistlib, 'load', None)
try:
    text = basestring
except NameError:
    text = str
problems = []
for product in products:
    short, component = product.split(':')
    pin_path = os.path.join(repo, 'components', component, 'version')
    try:
        pin = open(pin_path).read().strip()
    except IOError:
        pin = ''
    if not re.match(r'^[0-9][0-9A-Za-z.]*(-mavericks\.[1-9][0-9]*)?$', pin):
        problems.append('%s: components/%s/version must hold one Mavergreen release tag' % (short, component))
        continue
    manifest = root + '/usr/local/mavergreen/%s/mavergreen.plist' % short
    if not os.path.exists(manifest):
        problems.append('%s: pinned at %s, but not installed (no %s)' % (short, pin, manifest))
        continue
    try:
        with open(manifest, 'rb') as stream:
            data = load(stream) if load else plistlib.readPlist(stream)
        installed = data['version']
    except Exception:
        installed = None
    if not isinstance(installed, text) or not installed:
        problems.append('%s: pinned at %s, but %s is unreadable or has no version' % (short, pin, manifest))
    elif installed != pin:
        problems.append('%s: pinned at %s, but %s is installed (%s)' % (short, pin, installed, manifest))
for problem in problems:
    sys.stderr.write('tools: %s\n' % problem)
sys.exit(1 if problems else 0)
PY
[ "$action" = check ] || printf '%s/usr/local/mavergreen/%s\n' "${root%/}" "${products%%:*}"
