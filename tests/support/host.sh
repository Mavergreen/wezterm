#!/bin/sh
# platform: host-agnostic
#   usage: . tests/support/host.sh; x86_64_or_skip WHAT
#          Exits 77 naming WHAT unless this host is a Mac that runs x86_64 code natively. Shipped code
#          runs on the 10.9 box and in the on-target VM, never translated on an arm64 host, and never on
#          Linux, which cannot run a Mach-O at all.
runs_x86_64() {
    [ "$(uname -s):$(uname -m)" = Darwin:x86_64 ] || return 1
    # platform: under Rosetta uname -m says x86_64; sysctl.proc_translated is 1 there, and absent
    #           before macOS 11, where nothing is translated
    [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" != 1 ]
}
x86_64_or_skip() {
    runs_x86_64 || { echo "skipping $1: it runs x86_64 code, which this $(uname -s) $(uname -m) host does not run natively"; exit 77; }
}
