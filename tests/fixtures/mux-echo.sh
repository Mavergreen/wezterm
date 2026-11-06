#!/bin/sh
# platform: host-agnostic -- the shell build/check-release-on-10.9.sh spawns in the mux
#   usage: sh mux-echo.sh
#          Answers each line with "answer:" and the line in rot13, so the terminal's own echo of what
#          was sent can never pass for the answer.
printf 'mux-echo ready\n'
while IFS= read -r line; do
    printf 'answer:%s\n' "$(printf '%s' "$line" | tr 'A-Za-z' 'N-ZA-Mn-za-m')"
done
