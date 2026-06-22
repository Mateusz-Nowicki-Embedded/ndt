#!/bin/bash
# NVMe Driver Tester — runs a single blktests case under QEMU, or drops
# the user into an interactive QEMU session when no test is requested.
#
# Usage:
#   ./ndt.sh                            interactive shell in QEMU (no test)
#   ./ndt.sh 68                         run nvme/068 once (positional)
#   ./ndt.sh 68 10                      run nvme/068 ten times in one boot
#   ./ndt.sh --test=68 --iteration=10   same, long form
#   ./ndt.sh 68 --follow                run + stream the guest console live
#   ./ndt.sh --kunit                    run the bundled KUnit suites
#   ./ndt.sh --last                     show the latest run's summary + tail
#
# Test selectors accept 68, 068 or nvme/068 interchangeably.
#
# Flags:
#   -f, --follow     stream console.log live instead of a progress line
#       --last       print the latest run's summary + console tail, then exit
#       --kunit      run KUnit suites instead of a blktests case
#   -h, --help       this help
#
# In test mode, the guest init parses ndt.test=NNN ndt.iter=K from
# /proc/cmdline, runs ./check nvme/NNN K times, and emits one NDT_RESULT
# sentinel on ttyS0 before poweroff -f.  This host wrapper sets up the run
# dir, boots QEMU, captures the serial console, scrapes the sentinel, and
# exits 0/1.
#
# In interactive mode (no test), QEMU runs in the foreground with serial
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
# Env overrides:
#   APPEND="..."        replace the entire kernel cmdline
#   QEMU_EXTRA="-s -S"  extra QEMU args (gdbstub + stop-at-start)
#   NDT_PER_ITER_SEC=N  per-iteration wallclock budget (default 600)
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

# --- colors (only when stdout is a terminal) --------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_BOLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_BOLD=""; C_RST=""
fi

# --- QEMU launch (folded in from the old scripts/run-qemu.sh) ---------------
# No QEMU-emulated NVMe device — the test target is vnvme, which lives
# entirely inside the guest kernel; null_blk backs its namespaces.  Q35 keeps
# the PCIe root complex (the module's virtual bridge lives under bus 0xfe).

# Use the system qemu by default; override with QEMU_BIN=/path/to/qemu-... .
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
BZIMAGE="$NDT/build/linux/arch/x86/boot/bzImage"
INITRAMFS="$NDT/initramfs/initramfs.cpio.gz"

# The one and only base kernel cmdline.  memmap=64K$0x100000000 carves 64 KiB
# out of high RAM to back the module's BAR0 (vnvme; the
# literal '$' is escaped so the shell doesn't expand $0).  Callers append only
# the test selector (ndt.test=/ndt.iter=/ndt.kunit=).  Full override: APPEND=.
base_cmdline="console=ttyS0 panic=-1 memmap=64K\$0x100000000 nvme_core.multipath=0"

assert_artifacts() {
    local f
    for f in "$BZIMAGE" "$INITRAMFS"; do
        [[ -f "$f" ]] && continue
        echo "[ndt] missing artifact: $f" >&2
        echo "[ndt] hint: run ./build-all.sh first" >&2
        exit 2
    done
}

# Cheap sanity checks so failures surface here, not deep inside qemu.log.
# $1 = also require socat (1 for test mode, 0 for interactive).
preflight() {
    if ! command -v "$QEMU_BIN" >/dev/null 2>&1 && [[ ! -x "$QEMU_BIN" ]]; then
        echo "[ndt] qemu not found: $QEMU_BIN" >&2
        echo "[ndt] hint: install qemu-system-x86 (apt install qemu-system-x86 / emerge app-emulation/qemu)," >&2
        echo "[ndt]       or point QEMU_BIN at a custom build." >&2
        exit 2
    fi
    if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        echo "[ndt] /dev/kvm not accessible — KVM acceleration unavailable." >&2
        echo "[ndt] hint: add yourself to the 'kvm' group (usermod -aG kvm \$USER), then re-login." >&2
        exit 2
    fi
    if (( ${1:-0} )) && ! command -v socat >/dev/null 2>&1; then
        echo "[ndt] socat not found — needed to capture the guest console." >&2
        echo "[ndt] hint: install socat (apt install socat / emerge net-misc/socat)." >&2
        exit 2
    fi
}

# boot_qemu <serial-mode> <cmdline-extra> [extra qemu args...]
#   stdio   -> -serial mon:stdio   foreground; user types into the guest shell
#                                  (Ctrl-A x exits, Ctrl-A c flips to monitor)
#   socket  -> -serial unix:...    ndt attaches via socat to scrape NDT_RESULT
boot_qemu() {
    local mode=$1 extra=$2; shift 2
    local append=${APPEND:-"$base_cmdline${extra:+ $extra}"}
    local serial
    case "$mode" in
        stdio)  serial=( -serial mon:stdio ) ;;
        socket) serial=( -serial unix:/tmp/qemu-serial.sock,server,nowait ) ;;
        *)      echo "[ndt] boot_qemu: bad serial mode '$mode'" >&2; exit 2 ;;
    esac
    "$QEMU_BIN" \
        -machine q35 \
        -kernel "$BZIMAGE" \
        -initrd "$INITRAMFS" \
        -append "$append" \
        -nographic \
        -m 8G \
        -smp 16 \
        "${serial[@]}" \
        -display none \
        -no-reboot \
        -cpu host -enable-kvm \
        ${QEMU_EXTRA:-} \
        "$@"
}

# --- arg parsing ------------------------------------------------------------

test_num=""
iters=""
kunit_mode=0
follow=0
show_last=0
positional=()
for arg in "$@"; do
    case "$arg" in
        -h|--help)        usage 0 1 ;;
        --kunit)          kunit_mode=1 ;;
        -f|--follow)      follow=1 ;;
        --last|--show)    show_last=1 ;;
        --test=*)         test_num="${arg#--test=}" ;;
        --iteration=*)    iters="${arg#--iteration=}" ;;
        -t|-i)            echo "[ndt] use --test=N / --iteration=N, or positional: ndt.sh N [iters]" >&2; usage ;;
        -*)               echo "[ndt] unknown option: $arg" >&2; usage ;;
        *)                positional+=("$arg") ;;
    esac
done

# Positional fallthrough: ndt.sh <test> [iters]
if [[ -z "$test_num" && ${#positional[@]} -ge 1 ]]; then
    test_num="${positional[0]}"
fi
if [[ -z "$iters" && ${#positional[@]} -ge 2 ]]; then
    iters="${positional[1]}"
fi
iters="${iters:-1}"
test_num="${test_num#nvme/}"   # accept nvme/068 as well as 068 / 68

# --- --last: show the most recent run, then exit ----------------------------

if (( show_last )); then
    if [[ ! -L /tmp/ndt/latest ]]; then
        echo "[ndt] no runs recorded under /tmp/ndt/" >&2; exit 2
    fi
    d=$(readlink -f /tmp/ndt/latest)
    if [[ ! -d "$d" ]]; then
        echo "[ndt] /tmp/ndt/latest is dangling -> $d" >&2; exit 2
    fi
    if [[ -f "$d/summary.txt" ]]; then
        cat "$d/summary.txt"
    else
        echo "[ndt] no summary.txt in $d (interactive run, or it crashed early)" >&2
    fi
    if [[ -f "$d/console.log" ]]; then
        echo
        echo "--- last 40 lines of console.log ($d) ---"
        tail -n 40 "$d/console.log"
    fi
    exit 0
fi

# --- mode dispatch ----------------------------------------------------------

if (( kunit_mode )); then
    # KUnit mode -> init insmods the bundled nps-*-test.ko and emits a
    # pass/fail/skip sentinel.  Single boot, no blktests device setup.
    iters=1
    blktest="kunit"
elif [[ -z "$test_num" ]]; then
    # No test requested -> hand the user a plain QEMU session.  Init sees
    # the missing ndt.test on cmdline and execs /bin/bash on the console.
    # Serial on stdio so the user can type straight into the guest shell.
    assert_artifacts
    preflight 0
    echo "[ndt] booting interactive QEMU — 'poweroff -f' or Ctrl-A x to exit"
    boot_qemu stdio ""
    exit $?
else
    if ! [[ "$test_num" =~ ^[0-9]+$ ]]; then
        echo "[ndt] bad test number: $test_num" >&2; usage
    fi
    if ! [[ "$iters" =~ ^[0-9]+$ ]] || (( iters < 1 )); then
        echo "[ndt] bad iteration count: $iters" >&2; usage
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

preflight 1
rm -f /tmp/qemu-serial.sock

# Kill QEMU / socat / tail on any exit (including Ctrl-C) so an aborted run
# never leaks an 8G QEMU or a stale serial socket.
qemu_pid=""
socat_pid=""
follow_pid=""
cleanup() {
    [[ -n "$follow_pid" ]] && kill "$follow_pid" 2>/dev/null
    [[ -n "$socat_pid" ]] && kill "$socat_pid" 2>/dev/null
    if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
        kill -9 "$qemu_pid" 2>/dev/null
    fi
}
trap cleanup EXIT INT TERM

# Per-iter wallclock budget plus a generous boot/shutdown headroom.
# 600 s per iter matches the blktests cap; bump via $NDT_PER_ITER_SEC if needed.
per_iter=${NDT_PER_ITER_SEC:-600}
budget=$(( iters * per_iter + 120 ))

if (( kunit_mode )); then
    cmd_test="ndt.kunit=1"
else
    cmd_test="ndt.test=$nn ndt.iter=$iters"
fi
assert_artifacts
boot_qemu socket "$cmd_test" > "$qlog" 2>&1 &
qemu_pid=$!

# Wait for QEMU to publish the serial socket.
for _w in $(seq 1 100); do
    [[ -S /tmp/qemu-serial.sock ]] && break
    sleep 0.1
done
if [[ ! -S /tmp/qemu-serial.sock ]]; then
    echo "[ndt] FAIL: qemu never created serial socket (see $qlog)" | tee "$summary"
    exit 1
fi

socat -u "UNIX-CONNECT:/tmp/qemu-serial.sock" "OPEN:$console,creat,append" &
socat_pid=$!

# Live view: stream the console (--follow) or print an in-place progress line.
progress=0
if (( follow )); then
    echo "[ndt] $blktest running — following console (Ctrl-C aborts):"
    tail -n +1 -f "$console" &
    follow_pid=$!
elif [[ -t 2 ]]; then
    progress=1
fi

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
    (( progress )) && printf '\r[ndt] %s running… %3ds / %ds budget ' "$blktest" "$dt" "$budget" >&2
    sleep 1
done

dt=$((EPOCHSECONDS - t0))
(( progress )) && printf '\r%*s\r' 60 '' >&2          # wipe the progress line
[[ -n "$follow_pid" ]] && { kill "$follow_pid" 2>/dev/null; follow_pid=""; }

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
} > "$summary"
cat "$summary"

# Colored verdict banner; on failure, show the tail of the console so the
# next thing a human wants to read is already on screen.
echo
if [[ "$verdict" == "PASS" ]]; then
    printf '%s%s✓ PASS%s  %s  (%ds)\n' "$C_BOLD" "$C_GRN" "$C_RST" "$blktest" "$dt"
else
    printf '%s%s✗ FAIL%s  %s  (%ds, cause=%s)\n' "$C_BOLD" "$C_RED" "$C_RST" "$blktest" "$dt" "$cause"
    if [[ -s "$console" ]]; then
        echo
        echo "--- last 30 lines of console.log ---"
        tail -n 30 "$console"
    fi
fi

echo
echo "[ndt] artifacts: $RUN_DIR/"
echo "[ndt] symlink:   /tmp/ndt/latest"
echo "[ndt] re-view:   ./ndt.sh --last"

[[ "$verdict" == "PASS" ]]
