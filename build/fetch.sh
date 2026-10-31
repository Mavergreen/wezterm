#!/bin/sh
# platform: host-agnostic
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/msc.sh"
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
[ "$#" -eq 5 ] || { echo 'usage: fetch.sh URL SHA256 CACHE NAME DEST' >&2; exit 2; }
url=$1; sha=$2; cache=$3; name=$4; dest=$5
[ ! -e "$dest" ] && [ ! -L "$dest" ] || { echo "fetch: destination exists: $dest" >&2; exit 1; }
extracted=$(shipyard_fetch_extract "$url" "$sha" "$cache" "$name") || exit 1
trap 'rm -rf "$extracted"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
top=$(ls -A "$extracted")
case "$top" in ''|*[!A-Za-z0-9._-]*|.|..) echo 'fetch: expected one archive directory' >&2; exit 1 ;; esac
[ -d "$extracted/$top" ] && [ ! -L "$extracted/$top" ] || { echo 'fetch: archive root is not a directory' >&2; exit 1; }
mkdir -p "$(dirname "$dest")"
mv "$extracted/$top" "$dest"
