#!/bin/sh
# platform: macOS-only -- Installer, PlistBuddy, openssl, sshd, script, infocmp, tput and the installed product; meant for Mac OS X 10.9
#   usage: build/check-release-on-10.9.sh [--repo-tests] VERSION
#          Run on Mac OS X 10.9 as the user who will use WezTerm, not as root (it runs
#          `sudo installer` itself). Installs DIST/wezterm-VERSION.pkg (DIST is MAVERICKS_DIST, default
#          the checkout's dist/) after checking it against DIST/SHA256SUMS, then checks the installed
#          product without a GUI session: the manifest and app name VERSION, `mavergreen check` passes,
#          every command the pkg puts on PATH runs from a login shell with no LANG and prints its usage,
#          `wezterm ls-fonts` run from / with no LANG reaches the app's wezterm-gui through the PATH
#          wrapper, the app's terminfo describes wezterm through TERMINFO_DIRS, `wezterm record` runs a
#          shell in a PTY that sees a UTF-8 LANG though wezterm was started with none, a mux server runs a
#          fixture shell that answers a nonce through the CLI, a second mux server reaches the first over
#          TLS (and refuses an untrusted CA and a wrong host name), a third reaches a private sshd it
#          starts on 127.0.0.1 through SSH domains with each backend, libssh and libssh2 (and refuses
#          a changed host key and an unauthorized client key with each), and every server stops on
#          SIGTERM.
#          --repo-tests then runs the repo's suite with shipyard's run-repo-tests.sh, found by build/msc.sh.
#          One PASS/FAIL line per step; exit 1 if any failed, 2 on a usage error. WezTerm stays
#          installed: `sudo mavergreen uninstall wezterm` removes it.
#          MAVERICKS_CHECK_ROOT and MAVERICKS_CHECK_INSTALLER let tests/release_check.sh install into a
#          scratch volume: the installer is run as `INSTALLER PKG ROOT`.
# spec: INGREDIENTS.md "On-target acceptance"
set -u
here=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
fixtures=$repo/tests/fixtures
repo_tests=false
if [ "${1:-}" = --repo-tests ]; then repo_tests=true; shift; fi
[ "$#" -eq 1 ] && [ -n "$1" ] ||
    { echo 'usage: check-release-on-10.9.sh [--repo-tests] VERSION   (e.g. 20261026.072628-mavericks.1)' >&2; exit 2; }
V=$1
os=${MAVERICKS_CHECK_OS:-$(sw_vers -productVersion 2>/dev/null)}
case "$os" in 10.9|10.9.*) ;; *) echo "check-release-on-10.9.sh: run this on Mac OS X 10.9 (this is $os)" >&2; exit 2 ;; esac
[ "$(id -u)" != 0 ] || { echo 'check-release-on-10.9.sh: run this as the user, not as root; it runs sudo installer itself' >&2; exit 2; }
R=${MAVERICKS_CHECK_ROOT:-/}
R=${R%/}
dist=${MAVERICKS_DIST:-$repo/dist}
pkg=$dist/wezterm-$V.pkg
app="$R/Applications/Mavericks WezTerm.app"
farm=$R/usr/local/mavergreen/bin
user=$(id -un)
# platform: a Unix socket's path must fit in 104 bytes, and the default per-user temp dir does not leave room
w=$(mktemp -d /tmp/wzcheck.XXXXXX) || exit 1
bad=0
step() {
    name=$1; shift
    if ( "$@" ) > "$w/$name.log" 2>&1; then echo "PASS $name"; else
        echo "FAIL $name (log: $w/$name.log)"; tail -n 20 "$w/$name.log" | sed 's/^/    /'; bad=1
    fi
}
cleanup() {
    # platform: steps run in subshells, so the servers they start are recorded in a file
    if [ -f "$w/pids" ]; then
        while read -r p; do
            ! ps -p "$p" -o command= 2> /dev/null | grep -q wezterm-mux-server || kill -KILL "$p"
        done < "$w/pids"
    fi
    # platform: sshd writes its own pid file; its sessions are its children
    if [ -s "$w/ssh/sshd.pid" ]; then
        p=$(tr -dc 0-9 < "$w/ssh/sshd.pid")
        if ps -p "$p" -o command= 2> /dev/null | grep -qF "$w/ssh/"; then
            pkill -KILL -P "$p"; kill -KILL "$p"
        fi
    fi
    if [ "$bad" = 0 ]; then rm -rf "$w"; else echo "logs kept in $w"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

verify() {
    [ -f "$pkg" ] || { echo "no $pkg"; return 1; }
    n=$(grep -c " wezterm-$V.pkg\$" "$dist/SHA256SUMS") || true
    [ "$n" = 1 ] || { echo "wezterm-$V.pkg is listed ${n:-0} times in $dist/SHA256SUMS"; return 1; }
    want=$(grep " wezterm-$V.pkg\$" "$dist/SHA256SUMS" | cut -d' ' -f1)
    got=$(shasum -a 256 "$pkg" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "$pkg has sha256 $got; SHA256SUMS says $want"; return 1; }
}
install_pkg() {
    if [ -n "${MAVERICKS_CHECK_INSTALLER:-}" ]; then
        $MAVERICKS_CHECK_INSTALLER "$pkg" "$R/"
    else
        sudo /usr/sbin/installer -pkg "$pkg" -target /
    fi
}
helper_check() { "$R/usr/local/bin/mavergreen" --root "$R/" check; }
manifest() {
    m=$R/usr/local/mavergreen/wezterm/mavergreen.plist
    got=$(/usr/libexec/PlistBuddy -c 'Print :version' "$m") || return 1
    [ "$got" = "$V" ] || { echo "the installed manifest says version $got, not $V"; return 1; }
    got=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist") || return 1
    [ "$got" = "$V" ] || { echo "the installed app is version $got, not $V"; return 1; }
}
# platform: /usr/local/mavergreen/bin reaches PATH only through a login shell's paths.d, and with
#           env -i that shell has no LANG, as when the Finder or launchd starts a program; an empty
#           HOME keeps the user's own profile out of it
L() {
    mkdir -p "$w/login"
    if [ "$R" = '' ]; then env -i HOME="$w/login" USER="$user" /bin/bash -lc "$1"
    else env -i HOME="$w/login" USER="$user" PATH="$farm:/usr/bin:/bin" /bin/sh -c "$1"; fi
}
commands() {
    for tool in wezterm wezterm-gui wezterm-mux-server strip-ansi-escapes; do
        where=$(L "command -v $tool") || { echo "$tool is not on a login shell's PATH"; return 1; }
        [ "$where" = "$farm/$tool" ] || { echo "a login shell finds $tool at $where, not $farm/$tool"; return 1; }
    done
    for tool in wezterm wezterm-gui wezterm-mux-server; do
        out=$(L "$tool --version") || { echo "$tool --version failed: $out"; return 1; }
        [ "$out" = "$tool $V" ] || { echo "$tool --version says '$out', not '$tool $V'"; return 1; }
        echo "$out"
    done
    out=$(L "printf 'A\\033[1mB\\033[0mC\\n' | strip-ansi-escapes") || { echo 'strip-ansi-escapes failed'; return 1; }
    [ "$out" = ABC ] || { echo "strip-ansi-escapes printed '$out', not ABC"; return 1; }
}
# spec: INGREDIENTS.md "Commands on PATH" -- upstream finds wezterm-gui beside the path wezterm was
#       started by, which the wrapper makes the app's own Contents/MacOS
# spec: PORT.md "Locale without LANG" -- with no LANG, as from launchd, the hand-over still reaches
#       wezterm-gui; a SIGKILL (status 137) is the guarded-descriptor crash described there
# platform: another executable behind the wrapper may never exit (wezterm-mux-server takes ls-fonts or
#           record for a program to run), so these run bounded, the shell exec'ing the command so that
#           it is the process bounded kills
sibling_gui() {
    st=0
    out=$(bounded 60 L 'cd / && exec wezterm --skip-config ls-fonts' < /dev/null 2>&1) || st=$?
    [ "$st" != 137 ] ||
        { printf '%s\n' "$out" | tail -n 5; echo 'wezterm ls-fonts, started with no LANG, was killed (status 137)'; return 1; }
    [ "$st" = 0 ] && printf '%s\n' "$out" | grep -q '^Primary font:' ||
        { printf '%s\n' "$out" | tail -n 5; echo 'wezterm ls-fonts did not reach wezterm-gui beside it'; return 1; }
    echo 'wezterm ls-fonts, run from / with no LANG, reached wezterm-gui'
}
terminfo() {
    t=$app/Contents/Resources/terminfo
    out=$(env -i TERMINFO_DIRS="$t" /usr/bin/infocmp wezterm 2>&1) ||
        { echo "$out"; echo "infocmp finds no wezterm entry in $t"; return 1; }
    printf '%s\n' "$out" | grep -qF "from file: $t/" || { echo "$out"; echo "infocmp read wezterm from outside $t"; return 1; }
    colors=$(env -i TERMINFO_DIRS="$t" /usr/bin/tput -T wezterm colors) || { echo "tput -T wezterm failed"; return 1; }
    [ "$colors" = 256 ] || { echo "the wezterm entry has $colors colors, not 256"; return 1; }
    echo "the app's terminfo describes wezterm, with $colors colors"
}
helps() {
    for tool in wezterm wezterm-gui wezterm-mux-server strip-ansi-escapes; do
        out=$(L "$tool --help" < /dev/null) || { echo "$tool --help failed: $out"; return 1; }
        printf '%s\n' "$out" | grep -Eq "^Usage: $tool( |\$)" ||
            { printf '%s\n' "$out" | head -n 5; echo "$tool --help does not say 'Usage: $tool'"; return 1; }
    done
    echo 'every command prints its usage'
}
# spec: PORT.md "Locale without LANG" -- a program wezterm starts with no LANG gets a UTF-8 one
record() {
    d=$w/record
    mkdir "$d" || return 1
    n=$(nonce)
    printf '%s\n' "printf 'recorded $n LANG=[%s]\\n' \"\$LANG\"" > "$d/child.sh"
    # platform: wezterm record needs a terminal of its own, and script(1) gives it a PTY
    # platform: what script(1) runs is its child, not bounded's, so a timeout also kills whatever names this cast
    bounded 60 L "cd / && exec /usr/bin/script -q $d/transcript wezterm --skip-config record -o $d/cast -- /bin/sh $d/child.sh" \
        < /dev/null > "$d/driver.log" 2>&1 ||
        { pkill -KILL -f "$d/cast"; cat "$d/driver.log"; echo 'wezterm record failed'; return 1; }
    sed -n 1p "$d/cast" | grep -q '^{"version":2,' || { sed -n 1p "$d/cast"; echo 'the recording is not asciicast version 2'; return 1; }
    sed -n '2,$p' "$d/cast" | grep -q "recorded $n LANG=" ||
        { cat "$d/cast"; echo "the shell under wezterm record never printed $n"; return 1; }
    lang=$(sed -n '2,$p' "$d/cast" | sed -n "s/.*recorded $n LANG=\\[\\([^]]*\\)\\].*/\\1/p")
    printf '%s\n' "$lang" | grep -Eq '^[a-z]{2,3}(_[A-Z]{2})?\.UTF-8$' ||
        { echo "a child of wezterm started with no LANG sees LANG=[$lang], not a UTF-8 locale"; return 1; }
    echo "a shell under wezterm record printed $n, with LANG=$lang"
}


# platform: a mux server keeps its runtime dir, socket and pid file under HOME, so each gets its own
wz() {  # home, then wezterm's arguments
    h=$1; shift
    env -i HOME="$h" USER="$user" PATH="$farm:/usr/bin:/bin" WEZTERM_CHECK_TLS_DIR="$w/tls" \
        ${WZ_SERVER:+WEZTERM_CHECK_TLS_SERVER="$WZ_SERVER"} ${WZ_CLIENT:+WEZTERM_CHECK_TLS_CLIENT="$WZ_CLIENT"} \
        WEZTERM_CHECK_SSH_DIR="$w/ssh" ${WZ_SSH:+WEZTERM_CHECK_SSH_PORT="$WZ_SSH"} \
        "$@"
}
# platform: 10.9 has no timeout(1); bounded SECONDS COMMAND... gives the command's status, or 124 when it outlives SECONDS
bounded() {
    limit=$1; shift
    "$@" & bp=$!
    # platform: sh has no local variables, and the callers' loops count with i
    bi=0
    while kill -0 "$bp" 2> /dev/null; do
        [ "$bi" -lt "$limit" ] || {
            # platform: a function run in the background is a subshell, so its command is a child of $bp
            pkill -KILL -P "$bp" 2> /dev/null; kill -KILL "$bp" 2> /dev/null; wait "$bp" 2> /dev/null
            echo "timed out after ${limit}s: $*"; return 124
        }
        sleep 1; bi=$((bi + 1))
    done
    wait "$bp"
}
start_server() {  # home
    mkdir -p "$1"
    bounded 30 wz "$1" "$farm/wezterm-mux-server" --config-file "$fixtures/mux.lua" --daemonize || return 1
    pidfile=$1/.local/share/wezterm/pid
    i=0
    until [ -s "$pidfile" ]; do
        [ "$i" -lt 30 ] || { echo "the mux server for $1 wrote no pid file"; return 1; }
        sleep 1; i=$((i + 1))
    done
    p=$(tr -dc 0-9 < "$pidfile")
    echo "$p" > "$1/server.pid"
    echo "$p" >> "$w/pids"
    alive "$1" || return 1
    i=0
    until bounded 10 wz "$1" "$farm/wezterm" --config-file "$fixtures/mux.lua" cli --no-auto-start list > /dev/null 2>&1; do
        [ "$i" -lt 30 ] || { echo "the mux server for $1 never answered"; return 1; }
        sleep 1; i=$((i + 1))
    done
    echo "mux server for $1 is pid $p"
}
cli() {  # home, then cli arguments
    h=$1; shift
    bounded 60 wz "$h" "$farm/wezterm" --config-file "$fixtures/mux.lua" cli --no-auto-start "$@"
}
alive() {  # home
    kill -0 "$(cat "$1/server.pid")" 2> /dev/null || { echo "the mux server for $1 died"; return 1; }
}
nonce() { od -An -N8 -tx1 /dev/urandom | tr -d ' \n' | tr '0-9a-f' 'g-v'; }
round_trip() {
    h=$1; set -- --new-window ${2:+--domain-name "$2"}
    # platform: a fixture shell can kill its server before the server answers the spawn, so a failed
    #           spawn first gives a dying server 5 seconds to go, and then reports it as dead.
    pane=$(cli "$h" spawn "$@" -- /bin/sh "$fixtures/mux-echo.sh") || {
        i=0
        while [ "$i" -lt 5 ] && alive "$h" > /dev/null; do sleep 1; i=$((i + 1)); done
        alive "$h" || return 1
        echo "spawn failed: $pane"; return 1
    }
    case "$pane" in ''|*[!0-9]*) echo "spawn printed '$pane', not a pane id"; return 1 ;; esac
    n=$(nonce)
    answer=answer:$(printf '%s' "$n" | tr 'A-Za-z' 'N-ZA-Mn-za-m')
    i=0
    until cli "$h" get-text --pane-id "$pane" | grep -q 'mux-echo ready'; do
        alive "$h" || return 1
        [ "$i" -lt 30 ] || { echo "the fixture shell in pane $pane never started"; return 1; }
        sleep 1; i=$((i + 1))
    done
    cli "$h" send-text --pane-id "$pane" --no-paste "$(printf '%s\r' "$n")" || { echo 'send-text failed'; return 1; }
    i=0
    until cli "$h" get-text --pane-id "$pane" > "$h/text" && grep -qx "$answer" "$h/text"; do
        alive "$h" || return 1
        [ "$i" -lt 30 ] || { sed "/^[[:space:]]*\$/d" "$h/text"; echo "pane $pane never answered $n with $answer"; return 1; }
        sleep 1; i=$((i + 1))
    done
    cli "$h" list > "$h/list" || { echo 'list failed'; return 1; }
    awk -v p="$pane" '$3 == p { found = 1 } END { exit !found }' "$h/list" ||
        { cat "$h/list"; echo "list does not show pane $pane"; return 1; }
    echo "pane $pane answered $n with $answer"
}
stop_server() {  # home
    p=$(cat "$1/server.pid") || return 1
    kill -0 "$p" || { echo "the mux server for $1 (pid $p) died before it was stopped"; return 1; }
    kill -TERM "$p"
    i=0
    while kill -0 "$p" 2> /dev/null; do
        [ "$i" -lt 15 ] || { echo "the mux server for $1 (pid $p) outlived SIGTERM by 15s"; return 1; }
        sleep 1; i=$((i + 1))
    done
    ! grep -i 'panic' "$1/.local/share/wezterm/log" 2> /dev/null || { echo "the mux server for $1 panicked"; return 1; }
    echo "the mux server for $1 (pid $p) stopped on SIGTERM"
}
mux() {
    start_server "$w/mux" || return 1
    round_trip "$w/mux" || return 1
    stop_server "$w/mux"
}
certificates() {
    mkdir "$w/tls" && cd "$w/tls" || return 1
    # platform: 10.9's openssl 0.9.8 takes the subject from the config's prompt-free [dn], not -subj,
    #           so each certificate gets a copy of the fixture's config with its own CN
    cn() { sed "s/^CN = .*/CN = $1/" "$fixtures/tls.cnf" > "$2.cnf"; }
    for ca in ca other-ca; do
        cn "Mavericks WezTerm check $ca" "$ca"
        /usr/bin/openssl req -new -x509 -nodes -newkey rsa:2048 -sha256 -days 2 -config "$ca.cnf" -extensions ca_ext \
            -keyout "$ca.key" -out "$ca.pem" || return 1
    done
    # spec: INGREDIENTS.md "On-target acceptance" -- the mux server accepts a client certificate whose CN
    #       is the user it runs as
    for leaf in server:localhost:server_ext "client:$user:client_ext"; do
        name=${leaf%%:*}; rest=${leaf#*:}; ext=${rest#*:}
        cn "${rest%%:*}" "$name"
        /usr/bin/openssl req -new -nodes -newkey rsa:2048 -sha256 -config "$name.cnf" \
            -keyout "$name.key" -out "$name.csr" || return 1
        /usr/bin/openssl x509 -req -in "$name.csr" -CA ca.pem -CAkey ca.key -CAcreateserial -days 2 -sha256 \
            -extfile "$name.cnf" -extensions "$ext" -out "$name.pem" || return 1
    done
}
tls() {
    certificates || return 1
    port=$((20000 + $$ % 20000))
    WZ_SERVER=127.0.0.1:$port start_server "$w/tls-server" || return 1
    WZ_CLIENT=$port start_server "$w/tls-client" || return 1
    round_trip "$w/tls-client" tls || return 1
    for refused in tls-untrusted:'certificate verify failed' tls-wrong-host:'address mismatch'; do
        domain=${refused%%:*}; why=${refused#*:}
        if out=$(cli "$w/tls-client" spawn --new-window --domain-name "$domain" -- /bin/sh "$fixtures/mux-echo.sh" 2>&1); then
            echo "domain $domain was accepted: $out"; return 1
        fi
        printf '%s\n' "$out" | grep -q "$why" || { echo "domain $domain failed, but not with '$why': $out"; return 1; }
        echo "domain $domain refused: $why"
    done
    stop_server "$w/tls-client" || return 1
    stop_server "$w/tls-server"
}
# spec: INGREDIENTS.md "On-target acceptance" -- a private, unprivileged sshd with its own host key,
#       client keys, authorized_keys, config, pid file and log under $w/ssh, listening on 127.0.0.1
#       only; nothing reads or changes ~/.ssh, the system's sshd or the user's agent
sshd_start() {
    d=$w/ssh
    mkdir "$d" || return 1
    for key in host other-host client other-client; do
        /usr/bin/ssh-keygen -q -t ecdsa -N '' -C "wezterm check $key" -f "$d/$key" < /dev/null || return 1
    done
    cp "$d/client.pub" "$d/authorized_keys" || return 1
    i=0
    while :; do
        port=$((40000 + ($$ + i * 997) % 20000))
        printf '%s\n' "ListenAddress 127.0.0.1:$port" "HostKey $d/host" "PidFile $d/sshd.pid" \
            "AuthorizedKeysFile $d/authorized_keys" 'PubkeyAuthentication yes' 'PasswordAuthentication no' \
            'ChallengeResponseAuthentication no' 'UsePAM no' 'StrictModes no' 'PermitUserRC no' \
            'LogLevel DEBUG1' > "$d/sshd_config"
        # platform: an sshd since OpenSSH 9.8 turns a client address away for a while after it fails to
        #           log in, which would refuse every connection after the first refusal; an older sshd has
        #           no such penalty and no option for it
        ! /usr/sbin/sshd -t -f "$d/sshd_config" -o PerSourcePenalties=no 2> /dev/null ||
            echo 'PerSourcePenalties no' >> "$d/sshd_config"
        # platform: sshd exits at once when its port is taken, and otherwise only after it listens
        bounded 30 /usr/sbin/sshd -f "$d/sshd_config" -E "$d/sshd.log" && break
        [ "$i" -lt 10 ] || { tail -n 5 "$d/sshd.log"; echo 'sshd could not listen on any of 11 ports'; return 1; }
        i=$((i + 1))
    done
    i=0
    until [ -s "$d/sshd.pid" ]; do
        [ "$i" -lt 30 ] || { echo 'sshd wrote no pid file'; return 1; }
        sleep 1; i=$((i + 1))
    done
    for known in known_hosts:host other_known_hosts:other-host; do
        printf '[127.0.0.1]:%s %s\n' "$port" "$(cut -d' ' -f1-2 "$d/${known#*:}.pub")" > "$d/${known%%:*}" || return 1
    done
    echo "sshd is pid $(tr -dc 0-9 < "$d/sshd.pid") on 127.0.0.1:$port"
}
backend() {  # libssh or ssh2: sets lib, the client sshd logs, and using, the line WezTerm prints
    case $1 in
        libssh) lib=libssh_ using='Using libssh-rs to connect' ;;
        ssh2) lib=libssh2_ using='Using ssh2 to connect' ;;
    esac
}
sshd_since() { sed -n "$(($1 + 1)),\$p" "$w/ssh/sshd.log"; }
sshd_saw() {  # the log's line count before a connection, then what sshd must log for it
    si=0
    until sshd_since "$1" | grep -q "$2"; do
        [ "$si" -lt 10 ] || { sshd_since "$1"; echo "sshd never logged '$2' for this connection"; return 1; }
        sleep 1; si=$((si + 1))
    done
}
sshd_stop() {
    p=$(tr -dc 0-9 < "$w/ssh/sshd.pid")
    i=0
    while pgrep -P "$p" > /dev/null; do
        [ "$i" -lt 15 ] || { echo "sshd (pid $p) kept a session 15s after its client stopped"; return 1; }
        sleep 1; i=$((i + 1))
    done
    kill -TERM "$p" || { echo "sshd (pid $p) died before it was stopped"; return 1; }
    i=0
    while kill -0 "$p" 2> /dev/null; do
        [ "$i" -lt 15 ] || { echo "sshd (pid $p) outlived SIGTERM by 15s"; return 1; }
        sleep 1; i=$((i + 1))
    done
    echo "sshd (pid $p) stopped on SIGTERM, with no session left"
}
# spec: INGREDIENTS.md "On-target acceptance" -- a domain that does not connect says why in its pane
#       and runs nothing; one that asks to trust an unknown host or for a passphrase waits there
ssh_domains() {
    sshd_start || return 1
    c=$w/ssh-client
    WZ_SSH=$port start_server "$c" || return 1
    for b in libssh ssh2; do
        backend "$b"
        mark=$(wc -l < "$w/ssh/sshd.log" | tr -dc 0-9)
        round_trip "$c" "ssh-$b" || return 1
        grep -qF "$using" "$c/text" || { echo "domain ssh-$b did not say '$using'"; return 1; }
        sshd_saw "$mark" "remote software version $lib" || return 1
        sshd_saw "$mark" "Accepted publickey for $user " || return 1
        echo "domain ssh-$b connected through ${lib%_}"
    done
    for refused in libssh-wrong-host:'Host key verification failed' ssh2-wrong-host:'Host key verification failed' \
        libssh-unauthorized:'PUBLIC_KEY: Denied' ssh2-unauthorized:'Passphrase to decrypt'; do
        domain=ssh-${refused%%:*}; why=${refused#*:}
        b=${domain#ssh-}; backend "${b%%-*}"
        mark=$(wc -l < "$w/ssh/sshd.log" | tr -dc 0-9)
        pane=$(cli "$c" spawn --new-window --domain-name "$domain" -- /bin/sh "$fixtures/mux-echo.sh") ||
            { echo "spawn on $domain failed: $pane"; return 1; }
        case "$pane" in ''|*[!0-9]*) echo "spawn printed '$pane', not a pane id"; return 1 ;; esac
        i=0
        until cli "$c" get-text --pane-id "$pane" > "$c/text" && grep -qF "$why" "$c/text"; do
            alive "$c" || return 1
            ! grep -q 'mux-echo ready' "$c/text" || break
            [ "$i" -lt 30 ] || { sed "/^[[:space:]]*\$/d" "$c/text"; echo "domain $domain never said '$why'"; return 1; }
            sleep 1; i=$((i + 1))
        done
        ! grep -q 'mux-echo ready' "$c/text" || { echo "domain $domain was accepted"; return 1; }
        grep -qF "$using" "$c/text" || { echo "domain $domain did not say '$using'"; return 1; }
        sshd_saw "$mark" "remote software version $lib" || return 1
        case $domain in
            *-wrong-host)
                ! sshd_since "$mark" | grep -q 'publickey for' ||
                    { echo "domain $domain logged in to a host whose key it does not know"; return 1; } ;;
            *)
                sshd_saw "$mark" "Failed publickey for $user " || return 1
                ! sshd_since "$mark" | grep -q 'Accepted publickey' ||
                    { echo "sshd accepted the key of domain $domain"; return 1; } ;;
        esac
        echo "domain $domain refused through ${lib%_}: $why"
    done
    stop_server "$c" || return 1
    sshd_stop
}
repo_suite() {
    . "$repo/build/msc.sh" || return 1
    [ -f "$SHIPYARD_SCRIPTS/run-repo-tests.sh" ] ||
        { echo "no run-repo-tests.sh in $SHIPYARD_SCRIPTS"; return 1; }
    cd "$repo" && MAVERICKS_TEST_JOBS=1 sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"
}

step verify verify
[ "$bad" = 0 ] || { echo "SOME FAILED $V -- not installing a pkg that did not verify"; exit 1; }
step install install_pkg
[ "$bad" = 0 ] || { echo "SOME FAILED $V -- the pkg did not install"; exit 1; }
step mavergreen-check helper_check
step manifest manifest
step commands commands
step sibling-gui sibling_gui
step terminfo terminfo
step help helps
step record record
step mux mux
step tls tls
step ssh ssh_domains
if [ "$repo_tests" = true ]; then step repo-tests repo_suite; fi
if [ "$bad" = 0 ]; then echo "ALL PASS $V"; else echo "SOME FAILED $V"; exit 1; fi
