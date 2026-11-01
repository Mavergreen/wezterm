#!/bin/sh
# platform: macOS-only -- tests native SecureTransport resolution and local trust
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$WORK_ROOT/prepared.json" ] || { echo 'not prepared; TLS test needs verified source'; exit 77; }
sh "$ROOT/build/prepare.sh" --verify
if [ "${1:-}" != --in-environment ]; then
    exec sh "$ROOT/build/environment.sh" sh "$0" --in-environment
fi
mkdir -p "$EVIDENCE_DIR"
cd "$SOURCE_DIR"
"$CARGO" build --locked --target x86_64-apple-darwin -p security-framework --lib \
    --message-format=json-render-diagnostics > "$EVIDENCE_DIR/tls-artifacts.jsonl" 2> "$EVIDENCE_DIR/tls-build.log"
"$PYTHON" - "$EVIDENCE_DIR/tls-artifacts.jsonl" "$TARGET_DIR/x86_64-apple-darwin/" > "$EVIDENCE_DIR/tls-artifacts.txt" <<'PY'
import json, os, sys
wanted = set(['security_framework', 'security_framework_sys', 'libc', 'core_foundation', 'core_foundation_sys'])
found = {}
for line in open(sys.argv[1]):
    row = json.loads(line)
    if row.get('reason') != 'compiler-artifact':
        continue
    name = row['target']['name']
    if name not in wanted:
        continue
    for path in row['filenames']:
        if path.endswith('.rlib') and path.startswith(sys.argv[2]) and os.path.isfile(path):
            if name in found and found[name] != path:
                raise ValueError('ambiguous TLS artifact: ' + name)
            found[name] = path
if set(found) != wanted:
    raise ValueError('missing TLS artifacts: ' + repr(wanted - set(found)))
for name in sorted(found):
    print(name + '\t' + found[name])
PY
set --
TAB=$(printf '\t')
while IFS="$TAB" read -r name artifact; do
    set -- "$@" --extern "$name=$artifact"
    if [ "$name" = security_framework ]; then
        "$NM" --undefined-only --extern-only --format=posix "$artifact" > "$EVIDENCE_DIR/tls-imports.txt" 2>&1
    fi
done < "$EVIDENCE_DIR/tls-artifacts.txt"
if grep -E '^_?SSLSetSessionTicketsEnabled[[:space:]]+U[[:space:]]' "$EVIDENCE_DIR/tls-imports.txt" >/dev/null; then
    echo 'FAIL: patched TLS artifact still strongly imports SSLSetSessionTicketsEnabled'
    exit 1
fi
TLS_CRATE_DIR=$CRATES_DIR/security-framework
export TLS_CRATE_DIR
"$RUSTC" --edition 2021 --test "$ROOT/tests/fixtures/tls.rs" --target x86_64-apple-darwin \
    -C "linker=$CXX" -C debuginfo=0 -L "dependency=$TARGET_DIR/x86_64-apple-darwin/debug/deps" \
    "$@" -o "$EVIDENCE_DIR/tls-tests"
umask 077
TLS_FIXTURE_DIR=$(mktemp -d "$WORK_ROOT/tls-fixtures.XXXXXX")
export TLS_FIXTURE_DIR
trap 'rm -f "$TLS_FIXTURE_DIR"/*; rmdir "$TLS_FIXTURE_DIR"' EXIT HUP INT TERM
/usr/bin/openssl req -new -x509 -nodes -newkey rsa:2048 -sha256 -days 2 \
    -config "$ROOT/tests/fixtures/tls.cnf" -extensions ca_ext -subj '/CN=Mavericks WezTerm Test CA' \
    -keyout "$TLS_FIXTURE_DIR/ca.key" -out "$TLS_FIXTURE_DIR/ca.pem" > "$EVIDENCE_DIR/tls-certificates.log" 2>&1
/usr/bin/openssl req -new -nodes -newkey rsa:2048 -sha256 -config "$ROOT/tests/fixtures/tls.cnf" \
    -subj '/CN=localhost' -keyout "$TLS_FIXTURE_DIR/server.key" -out "$TLS_FIXTURE_DIR/server.csr" >> "$EVIDENCE_DIR/tls-certificates.log" 2>&1
/usr/bin/openssl x509 -req -in "$TLS_FIXTURE_DIR/server.csr" -CA "$TLS_FIXTURE_DIR/ca.pem" \
    -CAkey "$TLS_FIXTURE_DIR/ca.key" -CAcreateserial -days 2 -sha256 \
    -extfile "$ROOT/tests/fixtures/tls.cnf" -extensions server_ext \
    -out "$TLS_FIXTURE_DIR/server.pem" >> "$EVIDENCE_DIR/tls-certificates.log" 2>&1
/usr/bin/openssl x509 -in "$TLS_FIXTURE_DIR/ca.pem" -outform der -out "$TLS_FIXTURE_DIR/ca.der"
find "$TARGET_DIR/x86_64-apple-darwin/debug/build" -path '*/openssl-build/install/lib/libssl.a' > "$EVIDENCE_DIR/tls-openssl-paths.txt"
[ "$(wc -l < "$EVIDENCE_DIR/tls-openssl-paths.txt" | tr -d ' ')" = 1 ] || fail 'TLS fixture needs one unambiguous native vendored OpenSSL build; run build-local.sh first'
IFS= read -r ssl < "$EVIDENCE_DIR/tls-openssl-paths.txt"
prefix=$(dirname "$(dirname "$ssl")")
"$CC" -std=c99 "$ROOT/tests/fixtures/tls-server.c" -I"$prefix/include" \
    "$ssl" "$prefix/lib/libcrypto.a" -pthread -o "$EVIDENCE_DIR/tls-server"
TLS_SERVER=$EVIDENCE_DIR/tls-server
export TLS_SERVER
"$EVIDENCE_DIR/tls-tests" --test-threads=1 --nocapture > "$EVIDENCE_DIR/tls-tests.log" 2>&1 || { tail -70 "$EVIDENCE_DIR/tls-tests.log"; exit 1; }
grep -E 'test result: ok\. [1-9][0-9]* passed; 0 failed' "$EVIDENCE_DIR/tls-tests.log"
echo 'PASS: optional TLS API resolution and real local trust/hostname/SNI/protocol checks'
