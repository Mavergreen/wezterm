#!/bin/sh
# platform: host-agnostic
make_preparation_fixture() {
    fixture=$TEST_ROOT/checkout
    mkdir -p "$fixture" "$TEST_ROOT/builds"
    cp -R "$ROOT/build" "$ROOT/components" "$ROOT/patches" "$fixture/"
    : > "$fixture/patches/series"
    : > "$fixture/patches/crates/series"
    export MAVERICKS_BUILD_ROOT=$TEST_ROOT/builds
    work=$MAVERICKS_BUILD_ROOT/checkout-wezterm-local
    mkdir -p "$work/downloads" "$TEST_ROOT/upstream"
    printf 'one\n' > "$TEST_ROOT/upstream/message.txt"
    printf '[package]\nname="fixture"\nversion="0.0.0"\n' > "$TEST_ROOT/upstream/Cargo.toml"
    printf 'version = 4\n[[package]]\nname = "fixture"\nversion = "0.0.0"\n' > "$TEST_ROOT/upstream/Cargo.lock"
    . "$fixture/components/wezterm/version"
    tar czf "$work/downloads/wezterm-$DIGEST.tar.gz" -C "$TEST_ROOT" upstream
    for entry in "FREETYPE2:$FREETYPE2_DIGEST" "LIBPNG:$LIBPNG_DIGEST" "ZLIB:$ZLIB_DIGEST" "HARFBUZZ:$HARFBUZZ_DIGEST"; do
        name=${entry%%:*}; digest=${entry#*:}
        tar czf "$work/downloads/$name-$digest.tar.gz" -C "$TEST_ROOT" upstream
    done
    "${PYTHON:-python}" - "$fixture/components/wezterm/version" "$work/downloads" <<'PY'
import hashlib, os, sys
path, cache = sys.argv[1:]
values = dict(line.strip().split('=', 1) for line in open(path) if '=' in line)
for prefix in ('', 'FREETYPE2_', 'LIBPNG_', 'ZLIB_', 'HARFBUZZ_'):
    name = prefix.rstrip('_') or 'wezterm'
    archive = os.path.join(cache, '%s-%s.tar.gz' % (name, values[prefix + 'DIGEST']))
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
    printf 'fixture.patch\n' > "$fixture/patches/series"
}
