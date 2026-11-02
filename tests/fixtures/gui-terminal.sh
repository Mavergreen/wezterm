#!/bin/sh
# platform: macOS-only -- runs inside the acceptance app's real PTY
set -eu
run=$1
nonce=$2
mode=$3
stty size > "$run/initial-size.txt"
render() {
    printf '\033[2J\033[H'
    printf 'MAVERGREEN_NATIVE_GUI_OUTPUT_OK\n'
    printf '\033[31mRED\033[0m \033[32mGREEN\033[0m \033[34mBLUE\033[0m\n'
    printf 'Glyphs: ABC abc 123 | é λ Ω | ┌────┐ │ │ └────┘\n'
    printf 'Initial rows/columns: '; cat "$run/initial-size.txt"
    if [ -f "$run/resize-size.txt" ]; then
        printf 'Current rows/columns: '; cat "$run/resize-size.txt"
    fi
    if [ -f "$run/keyboard.txt" ]; then
        printf 'KEYBOARD_OK %s\n' "$nonce"
        printf 'Commands: notify / expire / exit\n'
    else
        printf 'Type (do not paste): %s + Return\n' "$nonce"
        printf 'Resize the window; leave it open for a snapshot.\n'
        printf 'notify: click its banner. expire: observe three-second expiry.\n'
        printf 'Wait for the observer before exit.\n'
    fi
}
on_resize() {
    interrupted=1
    stty size > "$run/resize-size.tmp"
    mv "$run/resize-size.tmp" "$run/resize-size.txt"
    render
}
if [ "$mode" = replay ]; then
    render
    sleep 10
    printf '0\n' > "$run/shell-exit.txt"
    exit 0
fi
trap on_resize WINCH
render
while :; do
    interrupted=0
    if IFS= read -r line; then
        case "$line" in
            "$nonce") printf '%s\n' "$line" > "$run/keyboard.txt"; render ;;
            notify|expire) printf '%s\n' "$line" > "$run/command" ;;
            exit)
                if [ -f "$run/keyboard.txt" ] && [ -f "$run/resize-size.txt" ] && [ -f "$run/window-after-resize.json" ] && ! cmp -s "$run/initial-size.txt" "$run/resize-size.txt"; then
                    printf '0\n' > "$run/shell-exit.txt"
                    exit 0
                fi
                printf 'Wait for observer snapshot; verify nonce and changed rows/columns before exit.\n'
                ;;
            *) printf 'Expected nonce, notify, expire, or exit.\n' ;;
        esac
    elif [ "$interrupted" -ne 1 ]; then
        printf '1\n' > "$run/shell-exit.txt"
        exit 1
    fi
done
