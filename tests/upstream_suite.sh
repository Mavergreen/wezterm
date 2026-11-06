#!/bin/sh
# platform: macOS-only -- runs upstream's own cargo tests natively, reusing the release build
. "$(CDPATH= cd "$(dirname "$0")" && pwd)/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$WORK_ROOT/prepared.json" ] || { echo 'not prepared; the upstream suite needs verified source'; exit 77; }
[ -f "$WORK_ROOT/build.json" ] || { echo 'not built; the upstream suite reuses the release build'; exit 77; }
sh "$ROOT/build/prepare.sh" --verify
runner="$ROOT/tests/support/upstream-tests.py"
exclusions="$ROOT/tests/upstream-exclusions"
out=$EVIDENCE_DIR/upstream-suite
rm -rf "$out"
mkdir -p "$out/fixture" "$out/logs"

# spec: PORT.md "Upstream's own tests" -- the runner's own failure modes, on a fixture binary with
#       a passing test, a failing one and one that needs the variables cargo sets.
sh "$ROOT/build/environment.sh" sh -c '
    "$RUSTC" --edition 2021 --test --crate-name fixture --target x86_64-apple-darwin -C linker="$CC" \
        -o "$1/fixture/fixture" "$2"
' sh "$out" "$ROOT/tests/fixtures/upstream-tests.rs" > "$out/fixture/rustc.log" 2>&1 ||
    { cat "$out/fixture/rustc.log"; fail 'fixture did not compile'; }
fixture_case() {
    expected=$1 env=$2 excluded=$3 probe=$4
    "$PYTHON" - "$out/fixture" "$env" > "$out/fixture/manifest" <<'PY'
import json, sys
d, env = sys.argv[1:]
env = {'CARGO_PKG_NAME': 'fixture', 'CARGO_MANIFEST_DIR': d} if env == 'cargo' else {}
print(json.dumps({'set': 'fixture', 'key': 'fixture/lib/fixture', 'exe': d + '/fixture', 'cwd': d, 'env': env}))
PY
    printf '%s' "$excluded" > "$out/fixture/exclusions"
    rm -rf "$out/fixture/logs" && mkdir "$out/fixture/logs"
    set -- "$PYTHON" "$runner" run "$out/fixture/manifest" "$out/fixture/exclusions" "$out/fixture/logs"
    [ -z "$probe" ] || set -- "$@" --ssh-probe fixture/lib/fixture
    assert_run "$expected" "$@"
}

# spec: PORT.md "Upstream's own tests" -- a proc macro's test binary is host code. Where the host is
#       not the target, cargo runs it itself rather than through the target's capture runner.
mkdir -p "$out/manifest-case/capture" "$out/manifest-case/target/x86_64-apple-darwin/release/deps" \
    "$out/manifest-case/target/release/deps"
manifest_case() {
    "$PYTHON" - "$out/manifest-case" "$1" > "$out/manifest-case/messages.jsonl" <<'PY'
import json, sys
d, host_captured = sys.argv[1:]
def artifact(name, kind, exe):
    return json.dumps({'reason': 'compiler-artifact', 'profile': {'test': True}, 'executable': exe,
                       'package_id': 'path+file:///src/%s#0.1.0' % name, 'target': {'kind': [kind], 'name': name}})
target = d + '/target/x86_64-apple-darwin/release/deps/lib-1'
host = d + '/target/release/deps/derive-1'
print(artifact('lib', 'lib', target))
print(artifact('derive', 'proc-macro', host))
json.dump({'exe': target, 'args': [], 'cwd': d, 'env': {}}, open(d + '/capture/lib-1.json', 'w'))
if host_captured == 'target-only':
    print(artifact('stray', 'lib', d + '/target/x86_64-apple-darwin/release/deps/stray-1'))
PY
    for exe in target/x86_64-apple-darwin/release/deps/lib-1 target/release/deps/derive-1 \
        target/x86_64-apple-darwin/release/deps/stray-1; do
        : > "$out/manifest-case/$exe"
    done
}
manifest_case host
assert_run 0 "$PYTHON" "$runner" manifest case "$out/manifest-case/messages.jsonl" "$out/manifest-case/capture"
assert_output '"key": "lib/lib/lib"'
assert_output 'derive/proc-macro/derive is a host test binary'
[ "$(grep -c '"set": "case"' "$TEST_ROOT/output")" = 1 ] || fail "the manifest must hold only the captured target binary: $(cat "$TEST_ROOT/output")"
manifest_case target-only
assert_run 2 "$PYTHON" "$runner" manifest case "$out/manifest-case/messages.jsonl" "$out/manifest-case/capture"
assert_output 'cargo built stray/lib/stray'
pass 'the manifest leaves out host test binaries cargo ran itself, and refuses an uncaptured target binary'
# spec: PORT.md "Upstream's own tests" -- on-target has the test binaries but no build root, so pack
#       copies the target's binaries beside a manifest whose paths are relative to it; the build
#       host's paths in the recorded variables do not exist there, and its toolchain is not there.
pack_dir=$out/pack-case
mkdir -p "$pack_dir/target/x86_64-apple-darwin/release/deps" "$pack_dir/other/x86_64-apple-darwin" \
    "$pack_dir/target/release/deps"
cp "$out/fixture/fixture" "$pack_dir/target/x86_64-apple-darwin/release/deps/fixture-1"
: > "$pack_dir/target/release/deps/derive-1"
: > "$pack_dir/other/x86_64-apple-darwin/fixture-1"
pack_manifest() {
    "$PYTHON" - "$pack_dir" "$1" > "$pack_dir/manifest" <<'PY'
import json, sys
d, shape = sys.argv[1:]
def row(key, exe):
    env = {'CARGO_PKG_NAME': 'fixture', 'CARGO_MANIFEST_DIR': d,
           'DYLD_FALLBACK_LIBRARY_PATH': d + '/lib', 'DYLD_LIBRARY_PATH': d + '/lib'}
    print(json.dumps({'set': 'fixture', 'key': key, 'exe': exe, 'cwd': d, 'env': env}))
row('fixture/lib/fixture', d + '/target/x86_64-apple-darwin/release/deps/fixture-1')
row('derive/proc-macro/derive', d + '/target/release/deps/derive-1')
if shape == 'twins':
    row('other/lib/fixture', d + '/other/x86_64-apple-darwin/fixture-1')
PY
}
pack_manifest one
assert_run 0 "$PYTHON" "$runner" pack "$pack_dir/manifest" "$pack_dir/packed"
assert_output 'derive/proc-macro/derive is a host test binary'
"$PYTHON" - "$pack_dir" <<'PY'
import filecmp, json, os, sys
d = sys.argv[1]
packed = os.path.join(d, 'packed')
rows = [json.loads(line) for line in open(os.path.join(packed, 'manifest.jsonl'))]
if [r['key'] for r in rows] != ['fixture/lib/fixture']:
    sys.exit('FAIL: the packed manifest holds %r, not the target binary alone' % [r['key'] for r in rows])
row = rows[0]
if row['exe'] != 'bin/fixture-1' or row['cwd'] != 'work':
    sys.exit('FAIL: packed paths are not relative to the manifest: %r %r' % (row['exe'], row['cwd']))
want = {'CARGO_PKG_NAME': 'fixture', 'CARGO_MANIFEST_DIR': '/nonexistent' + d}
if row['env'] != want:
    sys.exit('FAIL: packed variables are %r, not %r' % (row['env'], want))
exe = os.path.join(packed, 'bin', 'fixture-1')
source = os.path.join(d, 'target/x86_64-apple-darwin/release/deps/fixture-1')
if not filecmp.cmp(exe, source, shallow=False) or not os.access(exe, os.X_OK):
    sys.exit('FAIL: the packed binary is not an executable copy of the one cargo built')
if sorted(os.listdir(packed)) != ['bin', 'manifest.jsonl', 'work'] or os.listdir(os.path.join(packed, 'work')):
    sys.exit('FAIL: the pack holds %r, with work %r' % (os.listdir(packed), os.listdir(os.path.join(packed, 'work'))))
PY
assert_run 2 "$PYTHON" "$runner" pack "$pack_dir/manifest" "$pack_dir/packed"
assert_output "$pack_dir/packed already exists"
pack_manifest twins
assert_run 2 "$PYTHON" "$runner" pack "$pack_dir/manifest" "$pack_dir/twins"
assert_output 'two test binaries named fixture-1'
[ ! -e "$pack_dir/twins" ] || fail 'a refused pack left its directory behind'
pass "pack copies the target's test binaries beside a relative manifest, without the build host's paths or its toolchain's libraries"
# spec: PORT.md "Upstream's own tests" -- the product build's release profile and features, so
#       the dependencies it already compiled are reused. cargo builds every test binary and hands
#       each to the capture runner, which records how to run it.
cd "$SOURCE_DIR"
build_set() {
    name=$1; shift
    mkdir "$out/capture-$name"
    UPSTREAM_TESTS_CAPTURE=$out/capture-$name sh "$ROOT/build/environment.sh" cargo test \
        --config "target.x86_64-apple-darwin.runner = [\"$PYTHON\", \"$runner\", \"capture\"]" \
        --release --locked --target x86_64-apple-darwin --no-fail-fast --lib --bins --tests \
        --message-format=json-render-diagnostics "$@" \
        > "$out/messages-$name.jsonl" 2> "$out/cargo-$name.log" ||
        { tail -30 "$out/cargo-$name.log"; fail "cargo could not build the $name tests"; }
    "$PYTHON" "$runner" manifest "$name" "$out/messages-$name.jsonl" "$out/capture-$name" \
        >> "$out/manifest.jsonl"
}
build_set workspace --workspace --features wezterm-gui/distro-defaults
# spec: PORT.md "Upstream's own tests" -- upstream's CI also tests wezterm-escape-parser alone,
#       with its default (no_std) features.
build_set no-std -p wezterm-escape-parser
"$PYTHON" - "$out/manifest.jsonl" <<'PY'
import json, os, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
sets = sorted(set(row['set'] for row in rows))
if sets != ['no-std', 'workspace']:
    sys.exit('FAIL: the manifest holds sets %r, not no-std and workspace' % sets)
missing = [row['exe'] for row in rows if not os.access(row['exe'], os.X_OK)]
if missing:
    sys.exit('FAIL: the manifest names test binaries that are not there: %r' % missing[:5])
counts = ', '.join('%s %d' % (name, len([r for r in rows if r['set'] == name])) for name in sets)
print('manifest: %d test binaries (%s)' % (len(rows), counts))
PY
pass 'cargo built every upstream test binary through the capture runner, which ran none of them'
# spec: PORT.md "Upstream's own tests" -- the pack is what a cross host hands to on-target, and what
#       runs below on an x86_64 host.
"$PYTHON" "$runner" pack "$out/manifest.jsonl" "$out/packed" > "$out/pack.log" 2>&1 ||
    { cat "$out/pack.log"; fail 'the upstream test binaries did not pack'; }
cat "$out/pack.log"
. "$ROOT/tests/support/host.sh"
x86_64_or_skip "upstream's test binaries (the pack above is what a cross host hands to on-target)"
fixture_case 0 cargo 'fixture/lib/fixture fails
' ''
assert_output 'binaries 1, tests listed 3, passed 2, failed 0, ignored 0, excluded 1'
mv "$pack_dir/packed" "$pack_dir/moved"
printf 'fixture/lib/fixture fails\n' > "$pack_dir/exclusions"
mkdir "$pack_dir/logs" "$pack_dir/logs2"
assert_run 1 "$PYTHON" "$runner" run "$pack_dir/moved/manifest.jsonl" "$pack_dir/exclusions" "$pack_dir/logs"
assert_output 'reads_cargo_env'
printf 'fixture/lib/fixture fails\nfixture/lib/fixture reads_cargo_env\n' > "$pack_dir/exclusions"
assert_run 0 "$PYTHON" "$runner" run "$pack_dir/moved/manifest.jsonl" "$pack_dir/exclusions" "$pack_dir/logs2"
assert_output 'binaries 1, tests listed 3, passed 1, failed 0, ignored 0, excluded 2'
pass 'a moved pack runs its binaries from where it lies, and the build root it came from is not there'
fixture_case 1 cargo '' ''
assert_output 'FAIL: fixture fixture/lib/fixture: exited 101, 1 failed'
assert_output ': fails'
fixture_case 1 cargo 'fixture/lib/fixture fails
fixture/lib/fixture fail
' ''
assert_output 'FAIL: fixture/lib/fixture: excluded test does not exist: fail'
fixture_case 1 cargo 'fixture/lib/fixture fails
fixture/lib/fixture passes
fixture/lib/fixture reads_cargo_env
' ''
assert_output 'FAIL: fixture fixture/lib/fixture: has 3 tests but 0 passed'
fixture_case 1 none 'fixture/lib/fixture fails
' ''
assert_output 'reads_cargo_env'
fixture_case 1 cargo 'other/lib/other fails
fixture/lib/fixture fails
' ''
assert_output 'FAIL: exclusion names an unknown test binary: other/lib/other'
fixture_case 1 cargo 'fixture/lib/fixture fails
' probe
assert_output 'FAIL: fixture/lib/fixture: its sshd probe never succeeded'
pass 'runner fails on a failing, stale, empty, misdirected or vacuous run'
status=0
# spec: PORT.md "Upstream's own tests" -- the pack, outside the build environment, as on-target runs it
"$PYTHON" "$runner" run "$out/packed/manifest.jsonl" "$exclusions" "$out/logs" \
    --ssh-probe wezterm-ssh/test/lib > "$out/run.log" 2>&1 || status=$?
cat "$out/run.log"
[ "$status" -eq 0 ] || fail "upstream's tests failed (logs in $out/logs)"

# spec: PORT.md "Upstream's own tests" -- doctests compile at test time, so cargo runs them here.
sh "$ROOT/build/environment.sh" cargo test --release --locked --target x86_64-apple-darwin \
    --no-fail-fast --workspace --features wezterm-gui/distro-defaults --doc > "$out/doc.log" 2>&1 ||
    { grep -E '^test |FAILED|failures' "$out/doc.log" | tail -30; fail 'doctests failed'; }
doc_passed=$(sed -n 's/^test result: ok\. \([0-9]*\) passed.*/\1/p' "$out/doc.log" |
    awk '{ n += $1 } END { print n + 0 }')
[ "$doc_passed" -gt 0 ] || fail 'no doctest passed'
echo "doctests passed: $doc_passed"
pass "upstream's tests"
