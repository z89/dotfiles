#!/usr/bin/env bash
# wait-flag.sh <path> [max_seconds]: as soon as <path> exists (any size, including the zero-byte
# file `touch` makes) print "ready" and exit 0, checking every 50ms; after max_seconds
# (default 15) exit 1 without printing. shell.qml runs it through a Quickshell Process as the
# second, FileView-independent way of seeing desktop-ready. It never outlives max_seconds.

f=${1:?usage: wait-flag.sh <path> [max_seconds]}
max=${2:-15}
[[ $max =~ ^[0-9]+$ ]] || max=15
for (( i = 0; i <= max * 20; i++ )); do
    if [ -e "$f" ]; then
        echo ready
        exit 0
    fi
    (( i < max * 20 )) && sleep 0.05
done
exit 1
