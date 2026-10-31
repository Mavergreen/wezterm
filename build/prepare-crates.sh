#!/bin/sh
# platform: host-agnostic
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
[ "$#" -eq 1 ] || fail 'usage: prepare-crates.sh PREPARATION-DIRECTORY'
source=$1/source
crates=$1/crates
mkdir "$crates"
[ -s "$REPO_ROOT/patches/crates/series" ] || exit 0
cargo=${CARGO:-/usr/local/mavergreen/bin/cargo}
(cd "$source" && "$cargo" fetch --locked --target x86_64-apple-darwin)
names=
while read -r name patch extra; do
    [ -n "$name" ] || continue
    [ -z "$extra" ] && [ -n "$patch" ] || fail 'invalid crate patch series entry'
    case "$name/$patch" in *..*|*[!A-Za-z0-9._/-]*) fail 'invalid crate patch identity' ;; esac
    identity=$(sh "$REPO_ROOT/build/locked-crate.sh" "$name" "$source/Cargo.lock.upstream")
    set -- $identity
    version=$1; checksum=$2; url=$3
    sh "$REPO_ROOT/build/fetch.sh" "$url" "$checksum" "$WORK_ROOT/downloads" "$name-$version.crate" "$crates/$name"
    (cd "$crates/$name" && patch -p1 -F 0 -V none < "$REPO_ROOT/patches/crates/$patch")
    "$PYTHON" "$REPO_ROOT/build/add-crate-patch.py" "$source/Cargo.toml" "$name" "../crates/$name"
    names="$names $name"
done < "$REPO_ROOT/patches/crates/series"
for name in $names; do
    (cd "$source" && "$cargo" update --offline -p "$name")
done
"$PYTHON" "$REPO_ROOT/build/check-lock.py" "$source/Cargo.lock.upstream" "$source/Cargo.lock" $names
