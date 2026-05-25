#!/bin/bash
# NVMe Driver Tester — runs a single blktests case under QEMU, or drops
# the user into an interactive QEMU session when no test is requested.
#
# Usage:
#   ./ndt.sh                            interactive shell in QEMU (no test)
#   ./ndt.sh --test=68                  run nvme/068 once
#   ./ndt.sh --test=68 --iteration=10   run nvme/068 ten times in one boot
#   ./ndt.sh --kunit                    run the bundled KUnit suites
#
# In test mode, the guest init parses ndt.test=NNN ndt.iter=K from
# /proc/cmdline, runs ./check nvme/NNN K times, and emits one NDT_RESULT
# sentinel on ttyS0 before poweroff -f.  This host wrapper sets up the run
# dir, boots QEMU, captures the serial console, scrapes the sentinel, and
# exits 0/1.
#
# In interactive mode (no --test), QEMU runs in the foreground with serial
# on stdio.  Init does the same modprobe chain, then execs /bin/bash on
# the console.  Type `poweroff -f` (or Ctrl-A x) to exit.
#
# Artifacts per run live under /tmp/ndt/<run-id>/:
#   args.txt        invocation + submodule rev info
#   console.log     ttyS0 capture (kernel + init + NDT_RESULT line)
#   qemu.log        QEMU process stdout/stderr
#   summary.txt     final tally + verdict
#
# Symlink /tmp/ndt/latest points at the newest run-id.
#
# Exit codes:
#   0   pass == K and fail == 0
#   1   any fail, skip, error, or sentinel missing
#   2   bad arguments / setup error

set -uo pipefail

NDT=$(cd "$(dirname "$0")" && pwd)
export NDT

usage() {
    local rc=${1:-2} dest=${2:-2}
    awk 'NR==1{next} /^#/{sub(/^#[ \t]?/,""); print; next} {exit}' "$0" >&"$dest"
    exit "$rc"
}

# --- arg parsing ------------------------------------------------------------

test_num=""
iters=1
kunit_mode=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)        usage 0 1 ;;
        --kunit)          kunit_mode=1 ;;
        --test=*)         test_num="${arg#--test=}" ;;
        --iteration=*)    iters="${arg#--iteration=}" ;;
        -t|-i)            echo "[ndt] use --test=N / --iteration=N (= form)" >&2; usage ;;
        *)                echo "[ndt] unknown arg: $arg" >&2; usage ;;
    esac
done

if (( kunit_mode )); then
    # KUnit mode -> init insmods the bundled nps-*-test.ko and emits a
    # pass/fail/skip sentinel.  Single boot, no blktests device setup.
    iters=1
    blktest="kunit"
elif [[ -z "$test_num" ]]; then
    # No test requested -> hand the user a plain QEMU session.  Init sees
    # the missing ndt.test on cmdline and execs /bin/bash on the console.
    APPEND="console=ttyS0 panic=-1 memmap=64K\$0x100000000 nvme.poll_queues=4 nvme_core.multipath=0" \
    NDT_INTERACTIVE=1 \
        exec "$NDT/scripts/run-qemu.sh"
else
    if ! [[ "$test_num" =~ ^[0-9]+$ ]]; then
        echo "[ndt] bad --test: $test_num" >&2; usage
    fi
    if ! [[ "$iters" =~ ^[0-9]+$ ]] || (( iters < 1 )); then
        echo "[ndt] bad --iteration: $iters" >&2; usage
    fi
    nn=$(printf '%03d' "$((10#$test_num))")
    blktest="nvme/$nn"
fi

# --- run-id + dir layout ----------------------------------------------------

run_id=$(date +%Y%m%d-%H%M%S)-$$
RUN_DIR=/tmp/ndt/$run_id
mkdir -p "$RUN_DIR"
ln -snf "$run_id" /tmp/ndt/latest

console=$RUN_DIR/console.log
qlog=$RUN_DIR/qemu.log
summary=$RUN_DIR/summary.txt
: > "$console"; : > "$qlog"

{
    echo "ndt run $run_id"
    echo "args: $*"
    echo "test: $blktest"
    echo "iter: $iters"
    if [[ -d "$NDT/third_party/linux-fork/.git" ]]; then
        echo "linux-fork: $(git -C "$NDT/third_party/linux-fork" rev-parse --short HEAD 2>/dev/null)"
    fi
    if [[ -d "$NDT/third_party/blktests-fork/.git" ]]; then
        echo "blktests-fork: $(git -C "$NDT/third_party/blktests-fork" rev-parse --short HEAD 2>/dev/null)"
    fi
} > "$RUN_DIR/args.txt"

# --- boot QEMU --------------------------------------------------------------

rm -f /tmp/qemu-serial.sock /tmp/qemu-ctrl.sock

# Per-iter wallclock budget plus a generous boot/shutdown headroom.
# 600 s per iter matches the blktests cap; bump via $NDT_PER_ITER_SEC if needed.
per_iter=${NDT_PER_ITER_SEC:-600}
budget=$(( iters * per_iter + 120 ))

if (( kunit_mode )); then
    cmd_test="ndt.kunit=1"
else
    cmd_test="ndt.test=$nn ndt.iter=$iters"
fi
APPEND="console=ttyS0 panic=-1 memmap=64K\$0x100000000 nvme.poll_queues=4 nvme_core.multipath=0 $cmd_test" \
    "$NDT/scripts/run-qemu.sh" > "$qlog" 2>&1 &
qemu_pid=$!

# Wait for QEMU to publish the serial socket.
for _w in $(seq 1 100); do
    [[ -S /tmp/qemu-serial.sock ]] && break
    sleep 0.1
done
if [[ ! -S /tmp/qemu-serial.sock ]]; then
    echo "[ndt] FAIL: qemu never created serial socket" | tee "$summary"
    kill "$qemu_pid" 2>/dev/null
    wait "$qemu_pid" 2>/dev/null
    exit 1
fi

socat -u "UNIX-CONNECT:/tmp/qemu-serial.sock" "OPEN:$console,creat,append" &
socat_pid=$!

# --- wait for sentinel or timeout / QEMU exit -------------------------------

t0=$EPOCHSECONDS
result_line=""
cause=""

while :; do
    if grep -m1 -E '^=== NDT_RESULT ' "$console" >/dev/null 2>&1; then
        result_line=$(grep -m1 -E '^=== NDT_RESULT ' "$console")
        cause="sentinel"
        break
    fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        # QEMU exited; one last look at console before giving up.
        result_line=$(grep -m1 -E '^=== NDT_RESULT ' "$console" 2>/dev/null || true)
        if [[ -n "$result_line" ]]; then
            cause="sentinel"
        else
            cause="qemu-exited-without-sentinel"
        fi
        break
    fi
    dt=$((EPOCHSECONDS - t0))
    if (( dt > budget )); then
        cause="timeout"
        break
    fi
    sleep 1
done

dt=$((EPOCHSECONDS - t0))

# --- clean shutdown ---------------------------------------------------------

if kill -0 "$qemu_pid" 2>/dev/null; then
    # Sentinel was emitted before poweroff -f flushed; give it a sec, then nuke.
    for _w in $(seq 1 50); do
        kill -0 "$qemu_pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -9 "$qemu_pid" 2>/dev/null
fi
wait "$qemu_pid" 2>/dev/null
kill "$socat_pid" 2>/dev/null
wait "$socat_pid" 2>/dev/null

# --- parse sentinel ---------------------------------------------------------

verdict="FAIL"
pass=0; fail=0; skip=0
error_reason=""

if [[ -n "$result_line" ]]; then
    # Strip "=== NDT_RESULT " prefix and trailing " ===".
    payload=${result_line#=== NDT_RESULT }
    payload=${payload% ===}
    if [[ "$payload" == error=* ]]; then
        error_reason=${payload#error=}
        error_reason=${error_reason#\'}
        error_reason=${error_reason%\'}
    else
        for kv in $payload; do
            case "$kv" in
                pass=*) pass=${kv#pass=} ;;
                fail=*) fail=${kv#fail=} ;;
                skip=*) skip=${kv#skip=} ;;
            esac
        done
        if (( kunit_mode )); then
            # KUnit reports total tests passed, not per-iteration.
            (( pass > 0 && fail == 0 && skip == 0 )) && verdict="PASS"
        elif (( pass == iters && fail == 0 && skip == 0 )); then
            verdict="PASS"
        fi
    fi
fi

# --- summary ---------------------------------------------------------------

{
    cat "$RUN_DIR/args.txt"
    printf 'duration: %ds\n' "$dt"
    printf 'cause: %s\n' "$cause"
    if [[ -n "$error_reason" ]]; then
        printf 'verdict: FAIL (init error: %s)\n' "$error_reason"
    elif [[ -z "$result_line" ]]; then
        printf 'verdict: FAIL (no NDT_RESULT sentinel; cause=%s)\n' "$cause"
    else
        printf 'pass=%d fail=%d skip=%d (of %d iter)\n' "$pass" "$fail" "$skip" "$iters"
        printf 'verdict: %s\n' "$verdict"
    fi
} | tee "$summary"

echo
echo "[ndt] artifacts: $RUN_DIR/"
echo "[ndt] symlink:   /tmp/ndt/latest"

[[ "$verdict" == "PASS" ]]
