#!/bin/sh
# platform: host-agnostic
#   usage: check-snapshot-order.sh PREV_TAG
#          CI only: reads PREV_TAG's components/wezterm/version with git. Fails (1) when the
#          working tree's COMMITTED is older than PREV_TAG's upstream part, or equal to it with a
#          different DIGEST; an equal COMMITTED with the same DIGEST is a repackage and passes.
#          Exits 2 when PREV_TAG is not a YYYYMMDD.HHMMSS-mavericks.N tag.
# platform: a stock 10.9 has no git (/usr/bin/git there is a Command Line Tools stub).
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
pin=components/wezterm/version
fail() { printf 'check-snapshot-order: %s\n' "$*" >&2; exit 1; }
snapshot='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].[0-9][0-9][0-9][0-9][0-9][0-9]'
prev_tag=${1:-}
case "$#:$prev_tag" in
    1:$snapshot-mavericks.[1-9]*) ;;
    *) printf 'usage: check-snapshot-order.sh YYYYMMDD.HHMMSS-mavericks.N\n' >&2; exit 2 ;;
esac
prev=${prev_tag%%-mavericks.*}
prev_pin=$(git -C "$REPO_ROOT" show "$prev_tag:$pin" 2>/dev/null) || fail "cannot read $pin at $prev_tag"
prev_digest=$(printf '%s\n' "$prev_pin" | sed -n 's/^DIGEST=//p' | head -1)
digest=$(sed -n 's/^DIGEST=//p' "$REPO_ROOT/$pin" | head -1)
committed=$(sed -n 's/^COMMITTED=//p' "$REPO_ROOT/$pin" | head -1)
case "$committed" in $snapshot) ;; *) fail "COMMITTED in $pin is not YYYYMMDD.HHMMSS: '$committed'" ;; esac
[ -n "$prev_digest" ] || fail "no DIGEST in $pin at $prev_tag"
now=$(printf '%s' "$committed" | tr -d .)
then_=$(printf '%s' "$prev" | tr -d .)
if [ "$now" -lt "$then_" ]; then
    fail "COMMITTED $committed is older than $prev_tag; a snapshot must never be published as a downgrade"
fi
if [ "$now" -eq "$then_" ] && [ "$digest" != "$prev_digest" ]; then
    fail "COMMITTED $committed equals $prev_tag's but DIGEST $digest differs from its $prev_digest; two commits cannot share one version"
fi
printf 'check-snapshot-order: %s after %s ok\n' "$committed" "$prev_tag"
