#!/bin/sh
# platform: macOS-only -- runs build/check-release-on-10.9.sh against the real pkg, installed into a scratch volume
#   usage: tests/release_check.sh
#          Packages the staged product (build/package-pkg.sh) and runs build/check-release-on-10.9.sh on it,
#          with an installer that lays the pkg into a scratch volume and runs its scripts there, so
#          nothing reaches the real system. The check passes on that pkg, with --repo-tests reaching a
#          stand-in shipyard through build/msc.sh while SHIPYARD_SCRIPTS is empty, and fails on a pkg whose
#          SHA256SUMS line is wrong (before installing), on a version the pkg is not, on a wezterm
#          killed when it hands ls-fonts to wezterm-gui with no LANG, on a command that runs the wrong
#          executable (its version and its --help), on a command missing from PATH, on a wezterm
#          started through a symlink with no wezterm-gui beside it, on an app without its terminfo,
#          on a wezterm whose record child sees no UTF-8 LANG, on a fixture shell that never answers
#          (over the mux and over SSH), on a fixture shell that kills its mux server, and on SSH
#          domains whose unauthorized client key sshd accepts. No sshd it starts may outlive it.
set -eu
. "$(dirname "$0")/support/common.sh"
REPO_ROOT=$ROOT
. "$ROOT/build/lib.sh"
check=$ROOT/build/check-release-on-10.9.sh
[ -f "$check" ] || fail 'build/check-release-on-10.9.sh is missing'
case "$(sw_vers -productVersion)" in 10.9|10.9.*) ;; *) echo 'the release check runs on Mac OS X 10.9 only'; exit 77 ;; esac
sh "$SHIPYARD_SCRIPTS/product-name.sh" identifier wezterm > /dev/null 2>&1 ||
    { echo "the shipyard at $SHIPYARD_SCRIPTS does not register wezterm; install shipyard 1.0.677 or later"; exit 77; }
app="$STAGE_DIR/Mavericks WezTerm.app"
[ -d "$app" ] || { echo 'nothing is staged; the release check needs the product pkg'; exit 77; }
STEVEDORE=$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh")
export STEVEDORE
V=$("$STEVEDORE" plist get "$app/Contents/Info.plist" CFBundleShortVersionString)
updater=${WEZTERM_UPDATER_APP:-}
if [ -z "$updater" ]; then
    updater=$TEST_ROOT/upd/wezterm-updater.app
    sh "$ROOT/build/build-updater.sh" --out "$updater" > "$TEST_ROOT/updater.log" 2>&1 ||
        { tail -20 "$TEST_ROOT/updater.log"; fail 'build-updater.sh failed'; }
fi
SOURCE_DATE_EPOCH=1761463588
export SOURCE_DATE_EPOCH
dist=$TEST_ROOT/dist
assert_run 0 sh "$ROOT/build/package-pkg.sh" --app "$app" --updater-app "$updater" --version "$V" --out "$dist"
(cd "$dist" && shasum -a 256 "wezterm-$V.pkg") > "$dist/SHA256SUMS"

# platform: lays each component's payload into the scratch volume and runs its scripts with that volume
#           as Installer's target, base first as the Distribution orders them; the bin/ wrappers name
#           the boot volume's /Applications, so they are pointed at the scratch volume's app.
cat > "$TEST_ROOT/installer" <<'EOF'
#!/bin/sh
set -eu
pkg=$1; root=${2%/}
printf '%s\n' "$pkg" >> "$INSTALLER_LOG"
x=$(mktemp -d "${TMPDIR:-/tmp}/release-check-installer.XXXXXX")
trap 'rm -rf "$x"' EXIT
"$STEVEDORE" expand "$pkg" "$x/x" > /dev/null
for id in dev.mavergreen.base dev.mavergreen.wezterm; do
    for c in "$x/x"/*.pkg; do
        grep -q "identifier=\"$id\"" "$c/PackageInfo" && printf '%s\n' "$c"
    done
done > "$x/order"
while IFS= read -r c; do [ ! -x "$c/Scripts/preinstall" ] || "$c/Scripts/preinstall" "$pkg" / "$root" /; done < "$x/order"
while IFS= read -r c; do tar -xf "$c/Payload" -C "$root"; done < "$x/order"
while IFS= read -r c; do [ ! -x "$c/Scripts/postinstall" ] || "$c/Scripts/postinstall" "$pkg" / "$root" /; done < "$x/order"
for w in "$root/usr/local/mavergreen/wezterm/bin/"*; do
    sed "s|\"/Applications/|\"$root/Applications/|" "$w" > "$w.new" && cat "$w.new" > "$w" && rm "$w.new"
done
bin=$root/usr/local/mavergreen/wezterm/bin
app="$root/Applications/Mavericks WezTerm.app"
for b in ${INSTALLER_BREAK:-}; do
    case $b in
        wrapper) cp "$bin/wezterm-mux-server" "$bin/wezterm" ;;
        unlinked) rm "$root/usr/local/mavergreen/bin/strip-ansi-escapes" ;;
        linked) mkdir "$root/usr/local/mavergreen/wezterm/libexec" &&
            ln -s "$app/Contents/MacOS/wezterm" "$root/usr/local/mavergreen/wezterm/libexec/wezterm" &&
            printf '#!/bin/sh\nexec "%s" "$@"\n' "$root/usr/local/mavergreen/wezterm/libexec/wezterm" > "$bin/wezterm" ;;
        terminfo) rm -r "$app/Contents/Resources/terminfo" ;;
        lang) sed 's/^exec /LANG=C; export LANG; exec /' "$bin/wezterm" > "$bin/wezterm.new" &&
            cat "$bin/wezterm.new" > "$bin/wezterm" && rm "$bin/wezterm.new" ;;
        # platform: stands in for the guarded-descriptor crash (PORT.md "Locale without LANG"): a
        #           hand-over to wezterm-gui with no LANG is killed, as unpatched close_random_fds was
        nolang) sed 's/^exec /case " $* " in *" ls-fonts "*) [ -n "${LANG:-}" ] || kill -KILL $$ ;; esac; exec /' \
            "$bin/wezterm" > "$bin/wezterm.new" && cat "$bin/wezterm.new" > "$bin/wezterm" && rm "$bin/wezterm.new" ;;
    esac
done
EOF
chmod +x "$TEST_ROOT/installer"
INSTALLER_LOG=$TEST_ROOT/installer.log
export INSTALLER_LOG

tree=$TEST_ROOT/tree
mkdir -p "$tree/build" "$tree/tests/fixtures"
cp "$check" "$ROOT/build/msc.sh" "$tree/build/"
cp "$ROOT/tests/fixtures/mux.lua" "$ROOT/tests/fixtures/mux-echo.sh" "$ROOT/tests/fixtures/tls.cnf" "$tree/tests/fixtures/"
runs=0
run() {  # expected status, dist, then the check's arguments
    expected=$1; d=$2; shift 2
    runs=$((runs + 1))
    vol=$TEST_ROOT/vol$runs
    mkdir "$vol"
    : > "$INSTALLER_LOG"
    assert_run "$expected" env MAVERICKS_DIST="$d" MAVERICKS_CHECK_ROOT="$vol" \
        MAVERICKS_CHECK_INSTALLER="$TEST_ROOT/installer" sh "$tree/build/check-release-on-10.9.sh" "$@"
    kept=$(sed -n 's|^logs kept in \(/tmp/wzcheck\.[A-Za-z0-9]*\)$|\1|p' "$TEST_ROOT/output")
    [ -z "$kept" ] || rm -rf "$kept"
    ps -A -o command | grep -F "$vol/" | grep -v grep && fail "a mux server from $vol outlived the check"
    ps -A -o command | grep -E 'sshd -f /tmp/wzcheck\.[A-Za-z0-9]+/ssh/sshd_config' && fail "an sshd from the check outlived it"
    return 0
}

assert_run 2 sh "$tree/build/check-release-on-10.9.sh"
assert_output 'usage: check-release-on-10.9.sh'
assert_run 2 env MAVERICKS_CHECK_OS=10.15.7 sh "$tree/build/check-release-on-10.9.sh" "$V"
assert_output 'run this on Mac OS X 10.9'
pass 'the release check refuses usage errors and another OS'

# platform: --repo-tests finds shipyard through build/msc.sh with SHIPYARD_SCRIPTS empty, here a stand-in
#           shipyard-cmake on PATH whose shipyard's run-repo-tests.sh records where and how it ran.
sy=$TEST_ROOT/stub-shipyard
mkdir -p "$sy/scripts" "$TEST_ROOT/stub-bin"
printf '%s\n' '#!/bin/sh' "echo '-- SHIPYARD_DIR=$sy'" > "$TEST_ROOT/stub-bin/shipyard-cmake"
printf '%s\n' 'echo "repo-tests in $(pwd -P) jobs=$MAVERICKS_TEST_JOBS" > "$REPO_TESTS_LOG"' > "$sy/scripts/run-repo-tests.sh"
chmod +x "$TEST_ROOT/stub-bin/shipyard-cmake"
saved_path=$PATH; saved_scripts=$SHIPYARD_SCRIPTS
PATH=$TEST_ROOT/stub-bin:$PATH; SHIPYARD_SCRIPTS=; REPO_TESTS_LOG=$TEST_ROOT/repo-tests.log
export PATH SHIPYARD_SCRIPTS REPO_TESTS_LOG
run 0 "$dist" --repo-tests "$V"
PATH=$saved_path; SHIPYARD_SCRIPTS=$saved_scripts
for s in verify install mavergreen-check manifest commands sibling-gui terminfo help record mux tls ssh repo-tests; do assert_output "PASS $s"; done
[ "$(cat "$REPO_TESTS_LOG")" = "repo-tests in $(cd "$tree" && pwd -P) jobs=1" ] ||
    fail "--repo-tests did not run shipyard's suite serially in the repo: $(cat "$REPO_TESTS_LOG" 2>&1)"
assert_output "ALL PASS $V"
[ "$(cat "$INSTALLER_LOG")" = "$dist/wezterm-$V.pkg" ] || fail "the check installed $(cat "$INSTALLER_LOG")"
pass "the release check passes on the staged product's pkg: install, manifest, commands, wezterm-gui found beside wezterm, terminfo, --help, a record child's LANG, mux nonce, TLS trusted/untrusted/wrong host, SSH through libssh and libssh2 with a changed host key and an unauthorized key refused, clean stops, and the repo suite run through build/msc.sh with SHIPYARD_SCRIPTS empty"

bad=$TEST_ROOT/bad-sum
mkdir "$bad"
cp "$dist/wezterm-$V.pkg" "$bad/"
printf '%064d  wezterm-%s.pkg\n' 0 "$V" > "$bad/SHA256SUMS"
run 1 "$bad" "$V"
assert_output 'FAIL verify'
assert_output 'not installing a pkg that did not verify'
[ ! -s "$INSTALLER_LOG" ] || fail 'the check installed a pkg that did not verify'
other=$TEST_ROOT/other
mkdir "$other"
cp "$dist/wezterm-$V.pkg" "$other/wezterm-$V.9.pkg"
(cd "$other" && shasum -a 256 "wezterm-$V.9.pkg") > "$other/SHA256SUMS"
INSTALLER_BREAK=nolang run 1 "$other" "$V.9"
assert_output 'FAIL manifest'
assert_output "says version $V, not $V.9"
assert_output 'FAIL sibling-gui'
assert_output 'wezterm ls-fonts, started with no LANG, was killed (status 137)'
pass 'the release check fails a pkg SHA256SUMS does not vouch for, without installing it, a pkg that is not the version asked for, and a wezterm killed handing ls-fonts to wezterm-gui with no LANG'

printf '%s\n' '#!/bin/sh' "printf 'mux-echo ready\\n'" 'cat > /dev/null' > "$tree/tests/fixtures/mux-echo.sh"
run 1 "$dist" "$V"
assert_output 'FAIL mux'
assert_output 'never answered'
assert_output 'FAIL ssh'
printf '%s\n' '#!/bin/sh' "printf 'mux-echo ready\\n'" 'kill -KILL "$PPID"' 'cat > /dev/null' > "$tree/tests/fixtures/mux-echo.sh"
run 1 "$dist" "$V"
assert_output 'FAIL mux'
assert_output '/mux died'
pass 'the release check fails when the fixture shell never answers the nonce, over the mux and over SSH, and when the mux server is killed'
cp "$ROOT/tests/fixtures/mux-echo.sh" "$tree/tests/fixtures/mux-echo.sh"

INSTALLER_BREAK=wrapper run 1 "$dist" "$V"
assert_output 'FAIL commands'
assert_output "says 'wezterm-mux-server $V', not 'wezterm $V'"
assert_output 'FAIL help'
assert_output "wezterm --help does not say 'Usage: wezterm'"
INSTALLER_BREAK='unlinked linked terminfo' run 1 "$dist" "$V"
assert_output 'FAIL commands'
assert_output 'strip-ansi-escapes is not on'
assert_output 'FAIL sibling-gui'
assert_output 'wezterm ls-fonts did not reach wezterm-gui'
assert_output 'FAIL terminfo'
assert_output 'infocmp finds no wezterm entry'
sed 's/tls-untrusted.*other-ca.pem/tls-untrusted'"'"', '"'"'localhost'"'"', '"'"'ca.pem/' "$ROOT/tests/fixtures/mux.lua" > "$tree/tests/fixtures/mux.lua"
grep -q "tls-untrusted', 'localhost', 'ca.pem'" "$tree/tests/fixtures/mux.lua" || fail 'the TLS fixture was not rewritten'
sed "s/'-unauthorized', b\[2\], 'other-client'/'-unauthorized', b[2], 'client'/" "$tree/tests/fixtures/mux.lua" > "$TEST_ROOT/mux.lua"
cp "$TEST_ROOT/mux.lua" "$tree/tests/fixtures/mux.lua"
grep -q "'-unauthorized', b\[2\], 'client'" "$tree/tests/fixtures/mux.lua" || fail 'the SSH fixture was not rewritten'
INSTALLER_BREAK=lang run 1 "$dist" "$V"
assert_output 'FAIL record'
assert_output 'sees LANG=[C], not a UTF-8 locale'
assert_output 'FAIL tls'
assert_output 'domain tls-untrusted was accepted'
assert_output 'FAIL ssh'
assert_output 'domain ssh-libssh-unauthorized was accepted'
pass 'the release check fails a command that runs the wrong tool, a command missing from PATH, a wezterm that cannot find wezterm-gui, an app without terminfo, a record child without a UTF-8 LANG, an untrusted TLS server and an unauthorized SSH key that are accepted'
