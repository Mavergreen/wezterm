#!/bin/sh
# platform: host-agnostic -- needs the pinned cargo, an installed clang22 (any release: it links only the build
#           scripts, nothing that ships) and the verified sources
#   usage: sh tests/libssh2_git.sh
#          libssh2-sys's build script, compiled by the pinned rust and run against the prepared copy
#          of the crate with a git on PATH that records each call. Nothing is compiled from C:
#          openssl-sys's and libz-sys's build scripts are overridden by links, and CC is a stand-in
#          that records its call and refuses, so the build script stops once it starts compiling.
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/lib.sh"
. "$REPO_ROOT/tests/support/common.sh"
. "$ROOT/tests/support/rust.sh"
pinned_cargo_or_skip "libssh2-sys's build-script check"
[ -n "$(ls "$ROOT"/patches/crates/libssh2-sys/*.patch 2>/dev/null)" ] ||
    fail 'libssh2-sys has no crate patch in patches/crates/libssh2-sys, so its build script runs git submodule update --init'
. "$ROOT/components/wezterm/version"
assert_run 0 sh "$SHIPYARD/fetch_pinned_source.sh" "$REPO" "$DIGEST" "$SHA256" "$TEST_ROOT/source"
identity=$(sh "$ROOT/build/locked-crate.sh" libssh2-sys "$TEST_ROOT/source/Cargo.lock")
set -- $identity
version=$1
mkdir -p "$TEST_ROOT/crates"
for copy in upstream prepared; do
    assert_run 0 sh "$ROOT/build/fetch.sh" "$3" "$2" "$WORK_ROOT/downloads" "libssh2-sys-$version.crate" "$TEST_ROOT/crates/$copy"
done
assert_run 0 sh "$SHIPYARD/apply_patches.sh" "$TEST_ROOT/crates/prepared" "$ROOT/patches/crates/libssh2-sys"
[ -f "$TEST_ROOT/crates/prepared/libssh2/include/libssh2.h" ] || fail "the libssh2-sys crate no longer carries libssh2's source"
mkdir -p "$TEST_ROOT/stub"
host=$("$rust/bin/rustc" -vV | sed -n 's/^host: //p')
if [ "$host" = x86_64-apple-darwin ]; then
    clang=$TREES/clang22/bin/clang++
    [ -x "$clang" ] || clang=$TREES/clang22-cross/bin/clang++
    [ -x "$clang" ] || { echo "no clang22 under $TREES to link build scripts with"; exit 77; }
    sdk=$(sh "$SHIPYARD/fetch_sdk.sh" --arch x86_64) || fail 'shipyard could not fetch the 10.9 SDK the build scripts link against'
    printf '#!/bin/sh\nexec "%s" -target x86_64-apple-macos10.9 -isysroot "%s" "$@"\n' "$clang" "$sdk" > "$TEST_ROOT/cxx"
    chmod +x "$TEST_ROOT/cxx"
    linker=CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER=$TEST_ROOT/cxx
else
    # platform: on a cross host the build script is host code, linked by cargo's host linker, which
    #           the stand-in cc on PATH below would otherwise be
    linker=CARGO_TARGET_$(printf '%s' "$host" | tr a-z- A-Z_)_LINKER=/usr/bin/clang
fi
printf '#!/bin/sh\necho "git $*" >> "$STUB_LOG"\nexit 1\n' > "$TEST_ROOT/stub/git"
printf '#!/bin/sh\necho "cc $*" >> "$STUB_LOG"\nexit 1\n' > "$TEST_ROOT/stub/cc"
chmod +x "$TEST_ROOT/stub/git" "$TEST_ROOT/stub/cc"
build_script() {  # build_script COPY: runs that copy's build script; its log is $TEST_ROOT/COPY.log
    project=$TEST_ROOT/probe-$1
    mkdir -p "$project/src" "$project/.cargo"
    : > "$project/src/lib.rs"
    printf '[package]\nname = "probe"\nversion = "0.0.0"\nedition = "2021"\n[dependencies]\nlibssh2-sys = "=%s"\n[patch.crates-io]\nlibssh2-sys = { path = "%s" }\n' \
        "$version" "$TEST_ROOT/crates/$1" > "$project/Cargo.toml"
    printf '[target.x86_64-apple-darwin.openssl]\nrustc-link-lib = []\ninclude = "%s"\n[target.x86_64-apple-darwin.z]\nrustc-link-lib = []\n' \
        "$TEST_ROOT/crates/$1/libssh2/include" > "$project/.cargo/config.toml"
    : > "$TEST_ROOT/$1.log"
    (cd "$project" && env STUB_LOG="$TEST_ROOT/$1.log" "$linker" PATH="$TEST_ROOT/stub:$PATH" CC="$TEST_ROOT/stub/cc" \
        CARGO_TARGET_DIR="$TEST_ROOT/target" "$cargo" build --offline --target x86_64-apple-darwin -p libssh2-sys) \
        > "$TEST_ROOT/$1.out" 2>&1 || :
    grep '^cc ' "$TEST_ROOT/$1.log" > /dev/null || {
        tail -20 "$TEST_ROOT/$1.out" >&2
        fail "libssh2-sys's build script ($1 copy) did not get as far as compiling libssh2, so it proves nothing about git"
    }
}
build_script upstream
grep '^git submodule update --init' "$TEST_ROOT/upstream.log" > /dev/null ||
    fail "the upstream libssh2-sys build script no longer runs git submodule update --init, so this check cannot see it: $(cat "$TEST_ROOT/upstream.log")"
pass 'the probe sees the upstream build script run git'
build_script prepared
if grep '^git' "$TEST_ROOT/prepared.log" > /dev/null; then
    fail "the prepared libssh2-sys build script runs git, which on 10.9 without the Command Line Tools is the stub that offers to install them: $(grep '^git' "$TEST_ROOT/prepared.log")"
fi
pass 'the prepared libssh2-sys build script, whose libssh2 source is complete, never runs git'
