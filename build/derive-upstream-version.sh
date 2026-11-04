#!/bin/sh
# platform: host-agnostic
#   usage: derive-upstream-version.sh
#          Writes UPSTREAM_VERSION (gitignored, at the repo root) from the COMMITTED key of
#          components/wezterm/version: the pinned commit's UTC committer time, YYYYMMDD.HHMMSS.
#          Prints the value. Fails, writing nothing, when COMMITTED is missing or malformed.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
pin=components/wezterm/version
committed=$(sed -n 's/^COMMITTED=//p' "$REPO_ROOT/$pin" | head -1)
case "$committed" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *)
        printf "derive-upstream-version: COMMITTED in %s must be the commit's UTC time as YYYYMMDD.HHMMSS (got '%s')\n" \
            "$pin" "$committed" >&2
        exit 1
        ;;
esac
printf '%s\n' "$committed" > "$REPO_ROOT/UPSTREAM_VERSION.new"
mv "$REPO_ROOT/UPSTREAM_VERSION.new" "$REPO_ROOT/UPSTREAM_VERSION"
printf '%s\n' "$committed"
