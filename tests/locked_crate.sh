#!/bin/sh
# platform: host-agnostic
. "$(dirname "$0")/support/common.sh"
lock=$TEST_ROOT/Cargo.lock
cat > "$lock" <<'EOF'
version = 4

[[package]]
name = "one"
version = "1.2.3"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

[[package]]
name = "two"
version = "2.0.0"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
EOF
assert_run 0 sh "$ROOT/build/locked-crate.sh" one "$lock"
[ "$(cat "$TEST_ROOT/output")" = '1.2.3 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef https://static.crates.io/crates/one/one-1.2.3.crate' ] || fail 'lookup must bind the name, version and checksum of the same registry record'
pass 'exact locked crate identity'
cat "$lock" "$lock" > "$TEST_ROOT/duplicate.lock"
assert_run 1 sh "$ROOT/build/locked-crate.sh" one "$TEST_ROOT/duplicate.lock"
assert_output 'ambiguous'
pass 'ambiguous locked crate rejected'
assert_run 1 sh "$ROOT/build/locked-crate.sh" missing "$lock"
assert_output 'missing'
sed '/checksum =/d' "$lock" > "$TEST_ROOT/no-checksum.lock"
assert_run 1 sh "$ROOT/build/locked-crate.sh" one "$TEST_ROOT/no-checksum.lock"
assert_output 'checksum'
pass 'missing identity or checksum rejected'
sed '/^source =/d; /^checksum =/d' "$lock" > "$TEST_ROOT/path.lock"
assert_run 1 sh "$ROOT/build/locked-crate.sh" one "$TEST_ROOT/path.lock"
assert_output 'registry'
pass 'path source cannot masquerade as verified registry bytes'
cp "$lock" "$TEST_ROOT/changed.lock"
assert_run 0 /usr/bin/python "$ROOT/build/check-lock.py" "$lock" "$TEST_ROOT/changed.lock"
sed '/^source =/d; /^checksum =/d' "$lock" > "$TEST_ROOT/changed.lock"
assert_run 1 /usr/bin/python "$ROOT/build/check-lock.py" "$lock" "$TEST_ROOT/changed.lock" one
assert_output 'two'
pass 'undeclared source replacements rejected'
/usr/bin/python - "$lock" "$TEST_ROOT/changed.lock" <<'PY'
import sys
text = open(sys.argv[1]).read()
first, second = text.split('[[package]]')[1:]
first = '\n'.join(x for x in first.split('\n') if not x.startswith(('source =', 'checksum =')))
open(sys.argv[2], 'w').write('version = 4\n\n[[package]]' + first + '[[package]]' + second)
PY
assert_run 0 /usr/bin/python "$ROOT/build/check-lock.py" "$lock" "$TEST_ROOT/changed.lock" one
sed 's/1.2.3/1.2.4/' "$TEST_ROOT/changed.lock" > "$TEST_ROOT/bumped.lock"
assert_run 1 /usr/bin/python "$ROOT/build/check-lock.py" "$lock" "$TEST_ROOT/bumped.lock" one
assert_output 'one'
pass 'allowed path substitution cannot upgrade a dependency'
