#!/bin/bash
# NVMe Driver Tester — run blktests cases under QEMU and report PASS/FAIL.
#
# Usage:
#   ./ndt.sh 32                    # single test
#   ./ndt.sh nvme/032              # full id form
#   ./ndt.sh t=32,50               # multiple tests in one iteration
#   ./ndt.sh t=32,50 i=4           # 32 then 50, repeated 4 iterations (8 runs)
#   ./ndt.sh 32 50 i=2             # positional + named, equivalent to t=32,50 i=2
#
# Exit codes:
#   0   all runs passed
#   1   at least one run failed (or did not run cleanly)
#   2   bad arguments / setup error
#
# Per-run logs land in /tmp/ndt-console-<iter>-<sanitized-id>.log.

set -euo pipefail

NDT=$(cd "$(dirname "$0")" && pwd)

usage() {
    sed -n '2,15p' "$0" >&2
    exit 2
}

[[ $# -lt 1 ]] && usage

tests=()
iter=1

for arg in "$@"; do
    case "$arg" in
        i=*) iter="${arg#i=}" ;;
        t=*) IFS=',' read -ra _add <<< "${arg#t=}"; tests+=("${_add[@]}") ;;
        *=*) echo "[ndt] unknown arg: $arg" >&2; usage ;;
        *)   tests+=("$arg") ;;
    esac
done

if [[ ${#tests[@]} -eq 0 ]]; then
    echo "[ndt] no tests given" >&2; usage
fi
if ! [[ "$iter" =~ ^[0-9]+$ ]] || (( iter < 1 )); then
    echo "[ndt] bad iteration count: $iter" >&2; usage
fi

# Normalize each id: bare number -> nvme/NNN, path stays.
for k in "${!tests[@]}"; do
    case "${tests[$k]}" in
        */*) ;;
        *)   tests[$k]="nvme/$(printf '%03d' "$((10#${tests[$k]}))")" ;;
    esac
done

SERIAL_SOCK=/tmp/qemu-serial.sock
MONITOR_SOCK=/tmp/qemu-monitor.sock
QEMU_LOG=/tmp/ndt-qemu.log

cleanup() {
    [[ -n "${SOCAT_PID:-}" ]] && kill "$SOCAT_PID" 2>/dev/null || true
    [[ -n "${QEMU_PID:-}"  ]] && kill "$QEMU_PID"  2>/dev/null || true
}
trap cleanup EXIT

# run_test <test_id> <console_log_path> -> 0 on PASS, 1 otherwise.
# Sets $LAST_STATUS_LINE so caller can print it.
LAST_STATUS_LINE=""
run_test() {
    local test_id=$1
    local console=$2

    rm -f "$console" "$SERIAL_SOCK" "$MONITOR_SOCK" "$QEMU_LOG"

    APPEND="console=ttyS0 panic=-1 ndt_test=$test_id" \
        "$NDT/scripts/run-qemu.sh" > "$QEMU_LOG" 2>&1 &
    QEMU_PID=$!

    local _w
    for _w in $(seq 1 50); do
        [[ -S "$SERIAL_SOCK" ]] && break
        sleep 0.1
    done
    if [[ ! -S "$SERIAL_SOCK" ]]; then
        LAST_STATUS_LINE="serial socket never appeared"
        kill "$QEMU_PID" 2>/dev/null || true
        QEMU_PID=""
        return 1
    fi

    socat -u "UNIX-CONNECT:$SERIAL_SOCK" "OPEN:$console,creat,append" &
    SOCAT_PID=$!

    wait "$QEMU_PID" 2>/dev/null || true
    QEMU_PID=""
    SOCAT_PID=""  # socat self-exits when QEMU drops the socket

    if ! LAST_STATUS_LINE=$(grep -m 1 '=== NDT_STATUS ' "$console"); then
        LAST_STATUS_LINE="NDT_STATUS sentinel not found"
        return 1
    fi

    local status
    status=$(sed -nE "s/.*status='([^']*)'.*/\1/p" <<<"$LAST_STATUS_LINE")
    [[ "$status" == "pass" ]]
}

pass=0
fail=0
total=$(( ${#tests[@]} * iter ))
current=0

for ((it=1; it<=iter; it++)); do
    for test_id in "${tests[@]}"; do
        current=$((current + 1))
        log=/tmp/ndt-console-${it}-${test_id//\//_}.log
        printf '[ndt] %d/%d  iter %d/%d  %-12s ... ' \
            "$current" "$total" "$it" "$iter" "$test_id"
        if run_test "$test_id" "$log"; then
            pass=$((pass + 1))
            echo "PASS"
        else
            fail=$((fail + 1))
            echo "FAIL  ($LAST_STATUS_LINE)"
            echo "       log: $log"
            if grep -q 'NDT_DMESG_BEGIN' "$log" 2>/dev/null; then
                sed -n '/NDT_DMESG_BEGIN/,/NDT_DMESG_END/p' "$log" \
                    | sed -e '1d;$d' | tail -20 | sed 's/^/         | /'
            fi
        fi
    done
done

echo "---"
echo "[ndt] summary: ${pass}/${total} passed (fail=${fail})"
(( fail == 0 ))
