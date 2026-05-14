#!/bin/bash
# NVMe Driver Tester — run a single blktests case under QEMU and report PASS/FAIL.
#
# Usage:
#   ./ndt.sh 68         -> nvme/068
#   ./ndt.sh nvme/068   -> nvme/068
#
# Exit codes:
#   0   test passed
#   1   test failed (or did not run cleanly)
#   2   bad arguments / setup error

set -euo pipefail

NDT=$(cd "$(dirname "$0")" && pwd)

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <test_number_or_id>" >&2
    exit 2
fi

case "$1" in
    */*) TEST_ID="$1" ;;
    *)   TEST_ID="nvme/$(printf '%03d' "$((10#$1))")" ;;
esac

CONSOLE=/tmp/ndt-console.log
SERIAL_SOCK=/tmp/qemu-serial.sock
MONITOR_SOCK=/tmp/qemu-monitor.sock
QEMU_LOG=/tmp/ndt-qemu.log

rm -f "$CONSOLE" "$SERIAL_SOCK" "$MONITOR_SOCK" "$QEMU_LOG"

echo "[ndt] test:    $TEST_ID"
echo "[ndt] console: $CONSOLE"

# Boot QEMU in background.  APPEND injects ndt_test=... so the guest's init
# runs the test and powers off (which makes QEMU exit because of -no-reboot).
APPEND="console=ttyS0 panic=-1 ndt_test=$TEST_ID" \
    "$NDT/scripts/run-qemu.sh" > "$QEMU_LOG" 2>&1 &
QEMU_PID=$!

cleanup() {
    [[ -n "${SOCAT_PID:-}" ]] && kill "$SOCAT_PID" 2>/dev/null || true
    [[ -n "${QEMU_PID:-}"  ]] && kill "$QEMU_PID"  2>/dev/null || true
}
trap cleanup EXIT

# Wait for the serial socket to appear (QEMU sets it up before booting).
for _ in $(seq 1 50); do
    [[ -S "$SERIAL_SOCK" ]] && break
    sleep 0.1
done
if [[ ! -S "$SERIAL_SOCK" ]]; then
    echo "[ndt] FAIL: serial socket never appeared" >&2
    echo "      see $QEMU_LOG" >&2
    exit 1
fi

# Tap the serial console.  socat exits when QEMU disconnects (poweroff -f).
socat -u "UNIX-CONNECT:$SERIAL_SOCK" "OPEN:$CONSOLE,creat,append" &
SOCAT_PID=$!

# Wait for QEMU itself to finish.  -no-reboot makes 'poweroff -f' inside the
# guest end the qemu-system process cleanly.
wait "$QEMU_PID" 2>/dev/null || true
SOCAT_PID=""  # socat self-exits when QEMU drops the socket
QEMU_PID=""

# Parse status from the console.  init.sh prints a single 'NDT_STATUS ...' line.
if ! status_line=$(grep -m 1 '=== NDT_STATUS ' "$CONSOLE"); then
    echo "[ndt] FAIL: NDT_STATUS sentinel not found (boot/init never reached test mode?)" >&2
    echo "      last lines of console:" >&2
    tail -20 "$CONSOLE" >&2 || true
    exit 1
fi

# Line looks like: "=== NDT_STATUS status=pass reason= ==="
status=$(sed -nE 's/.*status=([a-z]+).*/\1/p' <<<"$status_line")

case "$status" in
    pass)
        echo "[ndt] PASS: $TEST_ID"
        exit 0
        ;;
    fail|notrun|*)
        echo "[ndt] FAIL: $TEST_ID ($status_line)"
        # Dump dmesg fragment between sentinel markers for quick triage.
        if grep -q 'NDT_DMESG_BEGIN' "$CONSOLE"; then
            echo "--- guest dmesg ---"
            sed -n '/NDT_DMESG_BEGIN/,/NDT_DMESG_END/p' "$CONSOLE" \
                | sed -e '1d;$d' \
                | tail -40
            echo "--- (full console at $CONSOLE) ---"
        fi
        exit 1
        ;;
esac
