#!/bin/bash
# Send one HMP command to the running QEMU monitor and print its reply.
#
# Usage:
#   ./qemu-hmp.sh "info nvme"
#   ./qemu-hmp.sh "nvme_completion_delay 1 35000"
#
# Override the socket path via $MONITOR_SOCK (default: /tmp/qemu-monitor.sock).
# Do NOT pass "quit" — it terminates the VM.  The script disconnects on its
# own, leaving QEMU running.
#
# Exit codes:
#   0  command sent
#   1  socket not found / send failed
#   2  bad usage

set -euo pipefail

SOCK=${MONITOR_SOCK:-/tmp/qemu-monitor.sock}

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <hmp-command>" >&2
    exit 2
fi

if [[ ! -S "$SOCK" ]]; then
    echo "[qemu-hmp] monitor socket not found: $SOCK" >&2
    echo "[qemu-hmp] hint: is QEMU running?" >&2
    exit 1
fi

# socat reads our stdin, writes to the monitor, then half-closes when stdin
# ends — QEMU prints the reply, then we read until the next prompt.  -t 1
# bounds how long socat lingers after EOF for the response to come back.
#
# HMP runs through readline, which re-echoes the whole edit buffer after
# every keystroke — that lands here as a wall of backspaces + clear-EOL
# sequences.  Strip them so the log stays readable.
printf '%s\n' "$@" | socat -t 1 - "UNIX-CONNECT:$SOCK" \
    | sed -E 's/\x08//g; s/\x1b\[[0-9;]*[A-Za-z]//g; s/\r//g'
