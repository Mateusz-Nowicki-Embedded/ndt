#!/bin/bash
# NVMe Driver Tester — run blktests cases under QEMU and report PASS/FAIL.
#
# Usage:
#   ./ndt.sh 32                       # single test
#   ./ndt.sh nvme/032                 # full id form
#   ./ndt.sh t=32,50                  # multiple tests in one iteration
#   ./ndt.sh t=32,50 i=4              # 32 then 50, repeated 4 iterations (8 runs)
#   ./ndt.sh 32 50 i=2                # positional + named, equivalent to t=32,50 i=2
#   ./ndt.sh t=32,50 i=4 --stop-at-fail   # abort the whole run on the first FAIL
#
# Per-SQ artificial completion delay (forked QEMU only):
#   ./ndt.sh 32 cq-delay=1:35000          # delay SQ 1 by 35 s before the test
#   ./ndt.sh 32 cq-delay=1:1000 cq-delay=2:500   # multiple SQs
# The delay is applied via HMP `nvme_completion_delay` after the driver has
# created its I/O queues and before ./check runs the test, so the test sees
# the configured delay from the first command.
#
# Inner iterations within ONE QEMU session (test-side cooperative):
#   ./ndt.sh 68 inner-iter=3 cq-delay=0:5000
# Requires the test to emit NDT_INNER_ITER sentinels and read /dev/ttyS1
# (currently: nvme/068).  On every iter's 'ready' the host re-applies the
# cq-delay (admin SQ is rebuilt by the previous reset with delay=0) and
# releases the gate; on 'done|fail' the host moves on to the next iter.
# Use this to check whether a reset affects subsequent ones in the same
# controller lifetime.
#
# By default a FAIL does NOT abort the remaining runs — the loop continues so
# you can see flake rates over multiple iterations.  --stop-at-fail flips that.
#
# Exit codes:
#   0   all runs passed
#   1   at least one run failed (or did not run cleanly)
#   2   bad arguments / setup error
#
# Per-run logs land in /tmp/ndt-console-<iter>-<sanitized-id>.log.

set -euo pipefail

NDT=$(cd "$(dirname "$0")" && pwd)

# Print the leading comment block (everything from line 2 down to the first
# non-comment line) on the requested stream, then exit with the given code.
usage() {
    local rc=${1:-2} dest=${2:-2}
    awk 'NR==1{next} /^#/{sub(/^#[ \t]?/,""); print; next} {exit}' "$0" >&"$dest"
    exit "$rc"
}

[[ $# -lt 1 ]] && usage

tests=()
iter=1
inner_iter=1
stop_at_fail=0
cq_delays=()

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage 0 1 ;;
        --stop-at-fail) stop_at_fail=1 ;;
        i=*) iter="${arg#i=}" ;;
        inner-iter=*) inner_iter="${arg#inner-iter=}" ;;
        t=*) IFS=',' read -ra _add <<< "${arg#t=}"; tests+=("${_add[@]}") ;;
        cq-delay=*)
            spec="${arg#cq-delay=}"
            if [[ ! "$spec" =~ ^[0-9]+:[0-9]+$ ]]; then
                echo "[ndt] bad cq-delay spec: $spec (want <sqid>:<ms>)" >&2; usage
            fi
            cq_delays+=("$spec")
            ;;
        --*|*=*) echo "[ndt] unknown arg: $arg" >&2; usage ;;
        *)   tests+=("$arg") ;;
    esac
done

if [[ ${#tests[@]} -eq 0 ]]; then
    echo "[ndt] no tests given" >&2; usage
fi
if ! [[ "$iter" =~ ^[0-9]+$ ]] || (( iter < 1 )); then
    echo "[ndt] bad iteration count: $iter" >&2; usage
fi
if ! [[ "$inner_iter" =~ ^[0-9]+$ ]] || (( inner_iter < 1 )); then
    echo "[ndt] bad inner-iter: $inner_iter" >&2; usage
fi

# Normalize each id: bare number -> nvme/NNN, path stays.
for k in "${!tests[@]}"; do
    case "${tests[$k]}" in
        */*) ;;
        *)   tests[$k]="nvme/$(printf '%03d' "$((10#${tests[$k]}))")" ;;
    esac
done

SERIAL_SOCK=/tmp/qemu-serial.sock
CTRL_SOCK=/tmp/qemu-ctrl.sock
MONITOR_SOCK=/tmp/qemu-monitor.sock
QEMU_LOG=/tmp/ndt-qemu.log

cleanup() {
    [[ -n "${SOCAT_PID:-}" ]] && kill "$SOCAT_PID" 2>/dev/null || true
    [[ -n "${QEMU_PID:-}"  ]] && kill "$QEMU_PID"  2>/dev/null || true
}
trap cleanup EXIT

# Block until an ERE pattern appears in $1, or $2 seconds pass.  Returns
# 0 on hit.  Polls the file because socat appends as the guest emits —
# no inotify needed.  Uses -E so callers can write '(done|fail)' etc.
wait_for_line() {
    local file=$1 pattern=$2 timeout=${3:-30}
    local deadline=$(( $(date +%s) + timeout ))
    while (( $(date +%s) < deadline )); do
        if [[ -f "$file" ]] && grep -Eq -- "$pattern" "$file"; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# Apply every cq-delay in $cq_delays via HMP, appending the chatter to
# $hmp_log.  Safe to call multiple times (admin SQ delay is gone after
# reset, so re-application is the standard idiom in inner-iter mode).
apply_cq_delays() {
    local hmp_log=$1 d sqid ms
    for d in "${cq_delays[@]}"; do
        sqid=${d%%:*}
        ms=${d##*:}
        echo "+ nvme_completion_delay $sqid $ms" >> "$hmp_log"
        MONITOR_SOCK="$MONITOR_SOCK" \
            "$NDT/scripts/qemu-hmp.sh" "nvme_completion_delay $sqid $ms" \
            >> "$hmp_log" 2>&1 || true
    done
}

# run_test <test_id> <console_log_path> -> 0 on PASS, 1 otherwise.
# Sets $LAST_STATUS_LINE so caller can print it.
LAST_STATUS_LINE=""
run_test() {
    local test_id=$1
    local console=$2

    rm -f "$console" "$SERIAL_SOCK" "$CTRL_SOCK" "$MONITOR_SOCK" "$QEMU_LOG"

    local append="console=ttyS0 panic=-1 ndt_test=$test_id"
    if (( inner_iter > 1 )); then
        append="$append ndt_inner_iter=$inner_iter"
    fi
    APPEND="$append" \
        "$NDT/scripts/run-qemu.sh" > "$QEMU_LOG" 2>&1 &
    QEMU_PID=$!

    # Wait for the console socket — drives all subsequent connect attempts.
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

    # Mirror console output to a log file we can grep for sentinels.
    socat -u "UNIX-CONNECT:$SERIAL_SOCK" "OPEN:$console,creat,append" &
    SOCAT_PID=$!

    # Guest blocks on ttyS1 after announcing ready-for-cmd.  Wait for that.
    if ! wait_for_line "$console" "NDT_PHASE phase='ready-for-cmd'" 60; then
        LAST_STATUS_LINE="guest never reached ready-for-cmd (boot/modprobe failure?)"
        return 1
    fi

    # HMP traffic stays in a sibling log — readline echoes a lot of noise
    # and we don't want it polluting the console log we grep for sentinels.
    local hmp_log="${console%.log}.hmp.log"
    : > "$hmp_log"

    # Single-iter mode: apply cq-delay once before kicking the test.
    # Multi-iter mode: skip here, the test will hand control back per iter.
    if (( inner_iter <= 1 )); then
        apply_cq_delays "$hmp_log"
    fi

    CTRL_SOCK="$CTRL_SOCK" "$NDT/scripts/qemu-ctrl.sh" GO

    # Multi-iter loop: for each round, wait for the test to announce
    # 'ready', re-apply cq-delay (admin SQ was rebuilt by the previous
    # reset with delay=0), release the gate with GO, wait for done|fail.
    local ix inner_pass=0 inner_fail=0
    if (( inner_iter > 1 )); then
        for (( ix = 1; ix <= inner_iter; ix++ )); do
            if ! wait_for_line "$console" \
                "NDT_INNER_ITER iter=$ix phase='ready'" 120; then
                LAST_STATUS_LINE="inner iter $ix never reached ready"
                return 1
            fi
            apply_cq_delays "$hmp_log"
            CTRL_SOCK="$CTRL_SOCK" "$NDT/scripts/qemu-ctrl.sh" GO
            # 'done' or 'fail' — give the iter generous time
            # (fio runtime 30s + reset overhead with cq-delay).
            if ! wait_for_line "$console" \
                "NDT_INNER_ITER iter=$ix phase='(done|fail)'" 300; then
                LAST_STATUS_LINE="inner iter $ix never finished"
                return 1
            fi
            if grep -q "NDT_INNER_ITER iter=$ix phase='fail'" "$console"; then
                inner_fail=$((inner_fail + 1))
            else
                inner_pass=$((inner_pass + 1))
            fi
        done
    fi

    wait "$QEMU_PID" 2>/dev/null || true
    QEMU_PID=""
    SOCAT_PID=""  # socat self-exits when QEMU drops the socket

    if ! LAST_STATUS_LINE=$(grep -m 1 '=== NDT_STATUS ' "$console"); then
        LAST_STATUS_LINE="NDT_STATUS sentinel not found"
        return 1
    fi
    if (( inner_iter > 1 )); then
        LAST_STATUS_LINE="$LAST_STATUS_LINE [inner: pass=$inner_pass fail=$inner_fail]"
    fi

    local status
    status=$(sed -nE "s/.*status='([^']*)'.*/\1/p" <<<"$LAST_STATUS_LINE")
    [[ "$status" == "pass" ]]
}

pass=0
fail=0
total=$(( ${#tests[@]} * iter ))
current=0

if (( ${#cq_delays[@]} > 0 )); then
    echo "[ndt] cq-delay: ${cq_delays[*]}"
fi

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
            # blktests stdout between markers, with kernel timestamps filtered
            # out — this is what shows skip reasons and .out diffs.
            sed -n '/=== NDT_BEGIN/,/=== NDT_STATUS/p' "$log" \
                | sed -e '1d;$d' \
                | grep -v '^\[[ ]*[0-9]\+\.[0-9]\+\]' \
                | tail -20 \
                | sed 's/^/         | /'
            # dmesg only when blktests itself flagged it (reason=dmesg).
            if grep -q "reason='dmesg'" <<<"$LAST_STATUS_LINE" \
               && grep -q 'NDT_DMESG_BEGIN' "$log" 2>/dev/null; then
                echo "       dmesg:"
                sed -n '/NDT_DMESG_BEGIN/,/NDT_DMESG_END/p' "$log" \
                    | sed -e '1d;$d' | tail -20 | sed 's/^/         | /'
            fi
            if (( stop_at_fail )); then
                echo "[ndt] --stop-at-fail set, aborting remaining runs"
                break 2
            fi
        fi
    done
done

echo "---"
echo "[ndt] summary: ${pass}/${total} passed (fail=${fail})"
(( fail == 0 ))
