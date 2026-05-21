#!/bin/bash
# Push a line into the guest's ttyS1 control channel.
#
# The guest's init script blocks on `read -r < /dev/ttyS1` after announcing
# `NDT_PHASE phase='ready-for-cmd'`; sending "GO" here unblocks it and the
# test proceeds.  Future commands (e.g. "delay 1 1000") can be parsed by the
# guest from the same line.
#
# Usage:
#   ./qemu-ctrl.sh GO
#
# Override the socket path via $CTRL_SOCK (default: /tmp/qemu-ctrl.sock).

set -euo pipefail

SOCK=${CTRL_SOCK:-/tmp/qemu-ctrl.sock}

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <line>" >&2
    exit 2
fi

if [[ ! -S "$SOCK" ]]; then
    echo "[qemu-ctrl] control socket not found: $SOCK" >&2
    echo "[qemu-ctrl] hint: is QEMU running?" >&2
    exit 1
fi

# Bidirectional with a 1-second linger after EOF so QEMU has time to deliver
# the buffered data to the guest tty before the socket closes.  Plain "-u"
# closes too aggressively and the line can be discarded by QEMU's chardev.
printf '%s\n' "$*" | socat -t 1 - "UNIX-CONNECT:$SOCK" > /dev/null
