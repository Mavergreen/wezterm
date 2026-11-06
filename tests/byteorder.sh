#!/bin/sh
# platform: macOS-only -- executes libssh fallback conversions on Mavericks
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -d "$CRATES_DIR/libssh-rs-sys" ] || { echo 'not prepared; byte-order test needs private libssh sources'; exit 77; }
sh "$ROOT/build/prepare.sh" --verify
include=
for candidate in "$TARGET_DIR"/x86_64-apple-darwin/release/build/libssh-rs-sys-*/out/include; do
    if [ -f "$candidate/libssh/libssh_version.h" ]; then include=$candidate; break; fi
done
[ -n "$include" ] || { echo 'not built; byte-order test needs generated libssh version header'; exit 77; }
mkdir -p "$EVIDENCE_DIR"
sh "$ROOT/build/environment.sh" sh -c '
    "$CC" -DHAVE_STRTOULL=1 -DHAVE_ARPA_INET_H=1 -DHAVE_COMPILER__FUNC__=1 \
        -I "$CRATES_DIR/libssh-rs-sys/vendored/include" -I "$1" \
        "$REPO_ROOT/tests/fixtures/byteorder.c" -o "$EVIDENCE_DIR/byteorder"
' sh "$include"
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "the byte-order probe"
"$EVIDENCE_DIR/byteorder"
