#!/bin/sh
# platform: macOS-only -- compiles native font dependencies without external git
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
[ -f "$WORK_ROOT/prepared.json" ] || { echo 'not prepared; archive build test requires verified sources'; exit 77; }
sh "$ROOT/build/prepare.sh" --verify
mkdir -p "$EVIDENCE_DIR/no-git"
cat > "$EVIDENCE_DIR/no-git/git" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$WEZTERM_GIT_CALLS"
exit 1
EOF
chmod +x "$EVIDENCE_DIR/no-git/git"
WEZTERM_GIT_CALLS=$EVIDENCE_DIR/font-build-git-calls
export WEZTERM_GIT_CALLS
: > "$WEZTERM_GIT_CALLS"
cd "$SOURCE_DIR"
sh "$ROOT/build/environment.sh" sh -c '
    PATH="$EVIDENCE_DIR/no-git:$PATH"; export PATH
    exec "$CARGO" build --locked --target x86_64-apple-darwin -p freetype -p harfbuzz
' > "$EVIDENCE_DIR/font-build.log" 2>&1 || { tail -30 "$EVIDENCE_DIR/font-build.log"; exit 1; }
if [ -s "$WEZTERM_GIT_CALLS" ]; then
    echo 'FAIL: verified archive sources attempted to invoke CLT git'
    cat "$WEZTERM_GIT_CALLS"
    exit 1
fi
echo 'PASS: verified font archives build without invoking git'
