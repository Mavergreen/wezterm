#!/bin/sh
# platform: host-agnostic
make_preparation_fixture() {
    fixture=$TEST_ROOT/checkout
    mkdir -p "$fixture" "$TEST_ROOT/builds"
    cp -R "$ROOT/build" "$ROOT/components" "$fixture/"
    mkdir -p "$fixture/patches/crates"
    export MAVERICKS_BUILD_ROOT=$TEST_ROOT/builds
    work=$MAVERICKS_BUILD_ROOT/checkout-wezterm-local
    mkdir -p "$work/downloads" "$TEST_ROOT/upstream"
    printf 'one\n' > "$TEST_ROOT/upstream/message.txt"
    printf '[package]\nname="fixture"\nversion="0.0.0"\n' > "$TEST_ROOT/upstream/Cargo.toml"
    mkdir -p "$TEST_ROOT/crate/demo-1.0.0"
    printf 'one\n' > "$TEST_ROOT/crate/demo-1.0.0/message.txt"
    tar czf "$work/downloads/demo-1.0.0.crate" -C "$TEST_ROOT/crate" demo-1.0.0
    crate_sha256=$(shasum -a 256 "$work/downloads/demo-1.0.0.crate" | cut -d ' ' -f 1)
    printf 'version = 4\n[[package]]\nname = "fixture"\nversion = "0.0.0"\n[[package]]\nname = "demo"\nversion = "1.0.0"\nsource = "registry+https://github.com/rust-lang/crates.io-index"\nchecksum = "%s"\n' "$crate_sha256" > "$TEST_ROOT/upstream/Cargo.lock"
    . "$fixture/components/wezterm/version"
    export MAVERICKS_SOURCE_CACHE=$TEST_ROOT/sources
    export MAVERICKS_CODELOAD=file://$TEST_ROOT/codeload
    export SHIPYARD_FETCH_TRIES=1
    for repository in "$REPO:$DIGEST" "$FREETYPE2_REPO:$FREETYPE2_DIGEST" "$LIBPNG_REPO:$LIBPNG_DIGEST" \
        "$ZLIB_REPO:$ZLIB_DIGEST" "$HARFBUZZ_REPO:$HARFBUZZ_DIGEST"; do
        digest=${repository##*:}; repository=${repository%:*}
        repository=${repository#https://github.com/}; repository=${repository%.git}
        rm -rf "$TEST_ROOT/archive"; mkdir -p "$TEST_ROOT/archive" "$TEST_ROOT/codeload/$repository/tar.gz"
        cp -R "$TEST_ROOT/upstream" "$TEST_ROOT/archive/${repository#*/}-$digest"
        tar czf "$TEST_ROOT/codeload/$repository/tar.gz/$digest" -C "$TEST_ROOT/archive" "${repository#*/}-$digest"
    done
    "${PYTHON:-python}" - "$fixture/components/wezterm/version" "$TEST_ROOT/codeload" <<'PY'
import hashlib, os, sys
path, codeload = sys.argv[1:]
values = dict(line.strip().split('=', 1) for line in open(path) if '=' in line)
for prefix in ('', 'FREETYPE2_', 'LIBPNG_', 'ZLIB_', 'HARFBUZZ_'):
    repository = values[prefix + 'REPO'][len('https://github.com/'):-len('.git')]
    archive = os.path.join(codeload, repository, 'tar.gz', values[prefix + 'DIGEST'])
    values[prefix + 'SHA256'] = hashlib.sha256(open(archive, 'rb').read()).hexdigest()
open(path, 'w').write(''.join('%s=%s\n' % (key, values[key]) for key in sorted(values)))
PY
    cat > "$fixture/patches/fixture.patch" <<'EOF'
--- a/message.txt
+++ b/message.txt
@@ -1 +1 @@
-one
+two
EOF
    cat > "$TEST_ROOT/demo.patch" <<'EOF'
--- a/message.txt
+++ b/message.txt
@@ -1 +1 @@
-one
+two
EOF
    tools=$TEST_ROOT/tools
    rust_pin=$(cat "$ROOT/components/rust/version")
    for short in rust rust-cross; do
        mkdir -p "$tools/usr/local/mavergreen/$short/bin"
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>version</key>\n  <string>%s</string>\n</dict>\n</plist>\n' "$rust_pin" \
            > "$tools/usr/local/mavergreen/$short/mavergreen.plist"
        cat > "$tools/usr/local/mavergreen/$short/bin/cargo" <<'EOF'
#!/bin/sh
printf 'stub cargo %s\n' "$*" >> "$STUB_CARGO_LOG"
[ "$1" != "${STUB_CARGO_FAILS:-}" ] || { printf 'stub cargo: %s refused\n' "$1" >&2; exit 101; }
EOF
        chmod +x "$tools/usr/local/mavergreen/$short/bin/cargo"
    done
    mkdir -p "$TEST_ROOT/farm"
    printf '#!/bin/sh\necho "farm cargo ran: $*" >&2\nexit 99\n' > "$TEST_ROOT/farm/cargo"
    chmod +x "$TEST_ROOT/farm/cargo"
    STUB_CARGO_LOG=$TEST_ROOT/cargo.log
    export STUB_CARGO_LOG
}
