#!/bin/sh
# platform: host-agnostic
. "$(dirname "$0")/support/common.sh"
mkdir -p "$TEST_ROOT/project/src" "$TEST_ROOT/cairo/src" "$TEST_ROOT/libssh/src"
: > "$TEST_ROOT/project/src/lib.rs"
: > "$TEST_ROOT/cairo/src/lib.rs"
: > "$TEST_ROOT/libssh/src/lib.rs"
printf '[package]\nname="cairo-sys-rs"\nversion="0.18.0"\n' > "$TEST_ROOT/cairo/Cargo.toml"
printf '[package]\nname="libssh-rs-sys"\nversion="0.2.8"\n' > "$TEST_ROOT/libssh/Cargo.toml"
cat > "$TEST_ROOT/project/Cargo.toml" <<'EOF'
[package]
name = "consumer"
version = "0.0.0"
edition = "2021"
[dependencies]
cairo-sys-rs = "0.18.0"
libssh-rs-sys = "0.2.8"
[patch.crates-io]
cairo-sys-rs = { path = "../cairo" }
[profile.release]
debug = false
EOF
assert_run 0 "${PYTHON:-python}" "$ROOT/build/add-crate-patch.py" "$TEST_ROOT/project/Cargo.toml" libssh-rs-sys ../libssh
assert_run 0 sh -c 'out=$1; shift; "$@" > "$out"' sh "$TEST_ROOT/metadata.json" "${CARGO:-cargo}" metadata --offline --format-version 1 --manifest-path "$TEST_ROOT/project/Cargo.toml"
"${PYTHON:-python}" - "$TEST_ROOT/metadata.json" "$TEST_ROOT" <<'PY'
import json, os, sys
packages = json.load(open(sys.argv[1]))['packages']
paths = dict((x['name'], os.path.realpath(x['manifest_path'])) for x in packages)
assert paths['cairo-sys-rs'] == os.path.realpath(sys.argv[2] + '/cairo/Cargo.toml'), paths
assert paths['libssh-rs-sys'] == os.path.realpath(sys.argv[2] + '/libssh/Cargo.toml'), paths
PY
pass 'Cargo resolves both the upstream cairo patch and the added private crate across later tables'
assert_run 1 "${PYTHON:-python}" "$ROOT/build/add-crate-patch.py" "$TEST_ROOT/project/Cargo.toml" libssh-rs-sys ../libssh
assert_output 'already'
pass 'duplicate crate patch rejected'
