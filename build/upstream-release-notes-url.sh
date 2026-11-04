#!/bin/sh
# platform: host-agnostic
#   usage: upstream-release-notes-url.sh <upstream-version>      (bare: 20261026.072628)
#          Prints the URL of what changed upstream for one WezTerm snapshot; shipyard's
#          upstream-notes.sh links it from the release notes of a release that ships a new upstream.
#          WezTerm's snapshots of main have no release notes, and the version is the pinned commit's
#          UTC committer time, which cannot be mapped back to a commit, so this links the history
#          leading up to DIGEST in components/wezterm/version. It refuses a version that is not that
#          pin's COMMITTED, since DIGEST would then be another snapshot's commit. Exit 1 on a refusal
#          or an unreadable pin, 2 on a usage error.
set -eu
[ "$#" -eq 1 ] || { echo 'usage: upstream-release-notes-url.sh <upstream-version>' >&2; exit 2; }
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
pin=components/wezterm/version
value() { sed -n "s/^$1=//p" "$REPO_ROOT/$pin"; }
committed=$(value COMMITTED)
digest=$(value DIGEST)
[ -n "$committed" ] && [ "$1" = "$committed" ] || {
    printf "upstream-release-notes-url: %s is not COMMITTED in %s ('%s'), so DIGEST is not its commit\n" "$1" "$pin" "$committed" >&2
    exit 1
}
case "$digest" in
    *[!0-9a-f]*|'') digest_ok=no ;;
    *) if [ "${#digest}" -eq 40 ]; then digest_ok=yes; else digest_ok=no; fi ;;
esac
[ "$digest_ok" = yes ] || { printf "upstream-release-notes-url: DIGEST in %s is not a commit ('%s')\n" "$pin" "$digest" >&2; exit 1; }
printf 'https://github.com/wezterm/wezterm/commits/%s\n' "$digest"
