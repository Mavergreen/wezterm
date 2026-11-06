#!/bin/sh
# platform: macOS-only -- cross-builds the Mavericks terminal on a modern macOS host
#   usage: build-cross.sh
#          build-native.sh --mode cross: rust-cross and clang22-cross build the same release for
#          x86_64 10.9 from the same prepared source, and stage the same product bundle.
set -eu
[ "$#" -eq 0 ] || { printf 'usage: build-cross.sh\n' >&2; exit 2; }
exec sh "$(CDPATH= cd "$(dirname "$0")" && pwd)/build-native.sh" --mode cross
