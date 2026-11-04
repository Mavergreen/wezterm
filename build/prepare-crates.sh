#!/bin/sh
# platform: host-agnostic
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
[ "$#" -eq 1 ] || fail 'usage: prepare-crates.sh PREPARATION-DIRECTORY'
preparation=$(CDPATH= cd "$1" && pwd)
source=$preparation/source
crates=$preparation/crates
mkdir "$crates"
names=
for patch in "$REPO_ROOT"/patches/crates/*/*.patch; do
    [ -f "$patch" ] || continue
    name=${patch%/*}; name=${name##*/}
    case " $names " in *" $name "*) ;; *) names="$names $name" ;; esac
done
[ -n "$names" ] || exit 0
pinned_rust
cargo=$RUST_BIN/cargo
cd "$source"
"$cargo" fetch --locked --target x86_64-apple-darwin
for name in $names; do
    case "$name" in *[!A-Za-z0-9_-]*) fail "invalid crate patch directory: patches/crates/$name" ;; esac
    identity=$(sh "$REPO_ROOT/build/locked-crate.sh" "$name" "$source/Cargo.lock.upstream")
    set -- $identity
    version=$1; checksum=$2; url=$3
    sh "$REPO_ROOT/build/fetch.sh" "$url" "$checksum" "$WORK_ROOT/downloads" "$name-$version.crate" "$crates/$name"
    sh "$SHIPYARD/apply_patches.sh" "$crates/$name" "$REPO_ROOT/patches/crates/$name"
    "$PYTHON" "$REPO_ROOT/build/add-crate-patch.py" "$source/Cargo.toml" "$name" "../crates/$name"
done
for name in $names; do
    "$cargo" update --offline -p "$name"
done
"$PYTHON" "$REPO_ROOT/build/check-lock.py" "$source/Cargo.lock.upstream" "$source/Cargo.lock" $names
