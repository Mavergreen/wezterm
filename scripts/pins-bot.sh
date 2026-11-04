#!/bin/sh
# platform: host-agnostic
#   usage: sh scripts/pins-bot.sh moved <base-ref>
#          sh scripts/pins-bot.sh values
#          sh scripts/pins-bot.sh apply <KEY=VALUE>...
#          sh scripts/pins-bot.sh fill <base-ref>
#          CI-only: what .github/workflows/pins-bot.yml decides and writes when it fills a WezTerm bump's
#          pins on Renovate's branch (scripts/pin-source-tarballs.sh computes and checks the values). Needs
#          git; never fetches or runs anything upstream.
#          moved   exit 0, printing them, when DIGEST in components/wezterm/version differs from that of the
#                  commit where this branch left <base-ref>; else 1; 2 when git cannot tell (no merge base, a
#                  failed diff), never 1.
#          values  prints the checked pins as KEY=VALUE, one line: DIGEST (the commit they were checked for),
#                  SHA256, COMMITTED and each submodule's _DIGEST and _SHA256. Refuses a malformed one.
#          apply   writes exactly those keys into components/wezterm/version, all of them and nothing else,
#                  and regenerates components/wezterm/gitlinks.json from them. DIGEST is not written: it must
#                  equal the pin's, so values checked for another commit are refused. Refuses an unknown,
#                  missing or repeated key or a malformed value before writing anything. Both files are
#                  written by renames from beside them, once every value is valid, with INT and TERM ignored
#                  between the two. Prints "changed" or "unchanged".
#          fill    the pins job's whole decision: exit 0 printing nothing when DIGEST did not move (moved) or
#                  pin-source-tarballs.sh --fill exits 0 (current); when it exits 3 (it wrote stale pins),
#                  prints values. Any other status, or a failed moved, exits 1 having printed nothing.
#                  Progress goes to stderr: stdout is the values or nothing.
set -eu
HERE=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
PIN=$HERE/components/wezterm/version
GITLINKS=$HERE/components/wezterm/gitlinks.json
KEYS='DIGEST SHA256 COMMITTED FREETYPE2_DIGEST FREETYPE2_SHA256 LIBPNG_DIGEST LIBPNG_SHA256 ZLIB_DIGEST ZLIB_SHA256 HARFBUZZ_DIGEST HARFBUZZ_SHA256'
die() { echo "pins-bot: $*" >&2; exit 1; }
hex() { case "$2" in *[!0-9a-f]*|'') return 1 ;; esac; [ "${#2}" -eq "$1" ]; }
valid() {
    case "$1" in
        COMMITTED) case "$2" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].[0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) return 1 ;; esac ;;
        *SHA256) hex 64 "$2" ;;
        *DIGEST) hex 40 "$2" ;;
        *) return 1 ;;
    esac
}
pinned() {
    [ "$(grep -c "^$1=" "$PIN")" = 1 ] || die "components/wezterm/version has no single $1= line"
    sed -n "s/^$1=//p" "$PIN"
}
case "${1:-}" in
    moved)
        [ "$#" -eq 2 ] || { echo 'usage: pins-bot.sh moved <base-ref>' >&2; exit 2; }
        base=$(git -C "$HERE" merge-base "$2" HEAD) || { echo "pins-bot: no merge base with $2" >&2; exit 2; }
        d=$(git -C "$HERE" diff "$base" HEAD -- components/wezterm/version) ||
            { echo "pins-bot: git diff $base HEAD -- components/wezterm/version failed" >&2; exit 2; }
        lines=$(printf '%s\n' "$d" | grep '^[-+]DIGEST=' || :)
        [ -n "$lines" ] || exit 1
        printf '%s\n' "$lines"
        ;;
    values)
        [ "$#" -eq 1 ] || { echo 'usage: pins-bot.sh values' >&2; exit 2; }
        out=
        for k in $KEYS; do
            v=$(pinned "$k")
            valid "$k" "$v" || die "components/wezterm/version's $k is '$v', not a checked value"
            out="$out${out:+ }$k=$v"
        done
        echo "$out"
        ;;
    apply)
        shift
        [ "$#" -gt 0 ] || { echo 'usage: pins-bot.sh apply <KEY=VALUE>...' >&2; exit 2; }
        seen=' '
        for kv in "$@"; do
            k=${kv%%=*}; v=${kv#*=}
            case " $KEYS " in *" $k "*) ;; *) die "'$k' is not a pin this bot writes ($KEYS)" ;; esac
            case "$seen" in *" $k "*) die "$k given twice" ;; esac
            valid "$k" "$v" || die "$k's value '$v' is malformed"
            seen="$seen$k "
            eval "new_$k=\$v"
        done
        for k in $KEYS; do
            case "$seen" in *" $k "*) ;; *) die "$k not given: apply writes all of $KEYS or nothing" ;; esac
            pinned "$k" > /dev/null
        done
        [ "$(pinned DIGEST)" = "$new_DIGEST" ] ||
            die "the values were checked for $new_DIGEST, but components/wezterm/version's DIGEST is $(pinned DIGEST)"
        tmp_pin=$PIN.pins-bot.$$; tmp_gitlinks=$GITLINKS.pins-bot.$$
        trap 'rm -f "$tmp_pin" "$tmp_gitlinks"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        awk -v kvs="$*" 'BEGIN { n = split(kvs, a, " "); for (i = 1; i <= n; i++) { j = index(a[i], "="); v[substr(a[i], 1, j - 1)] = substr(a[i], j + 1) } }
            { j = index($0, "="); k = (j > 1) ? substr($0, 1, j - 1) : "" }
            (k in v) { $0 = k "=" v[k] }
            { print }' "$PIN" > "$tmp_pin"
        {
            printf '{\n  "commit": "%s",\n  "gitlinks": {\n' "$new_DIGEST"
            printf '    "deps/freetype/freetype2": "%s",\n    "deps/freetype/libpng": "%s",\n' "$new_FREETYPE2_DIGEST" "$new_LIBPNG_DIGEST"
            printf '    "deps/freetype/zlib": "%s",\n    "deps/harfbuzz/harfbuzz": "%s"\n  }\n}\n' "$new_ZLIB_DIGEST" "$new_HARFBUZZ_DIGEST"
        } > "$tmp_gitlinks"
        if cmp -s "$tmp_pin" "$PIN" && cmp -s "$tmp_gitlinks" "$GITLINKS"; then echo unchanged; exit 0; fi
        trap '' INT TERM
        mv "$tmp_gitlinks" "$GITLINKS"
        mv "$tmp_pin" "$PIN"
        echo changed
        ;;
    fill)
        [ "$#" -eq 2 ] || { echo 'usage: pins-bot.sh fill <base-ref>' >&2; exit 2; }
        rc=0; sh "$HERE/scripts/pins-bot.sh" moved "$2" >&2 || rc=$?
        case "$rc" in
            0) ;;
            1) echo 'pins-bot: DIGEST did not move: nothing to do' >&2; exit 0 ;;
            *) die "could not tell whether DIGEST moved (moved exited $rc)" ;;
        esac
        rc=0; sh "$HERE/scripts/pin-source-tarballs.sh" --fill >&2 || rc=$?
        case "$rc" in
            0) echo 'pins-bot: the pins are current: nothing to do' >&2; exit 0 ;;
            3) echo 'pins-bot: the pins were stale and are written' >&2 ;;
            *) die "pin-source-tarballs.sh --fill exited $rc, an error rather than a stale pin: handing on nothing" ;;
        esac
        sh "$HERE/scripts/pins-bot.sh" values
        ;;
    *)
        echo 'usage: pins-bot.sh moved <base-ref> | values | apply <KEY=VALUE>... | fill <base-ref>' >&2
        exit 2
        ;;
esac
