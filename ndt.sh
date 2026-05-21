#!/bin/bash
# NVMe Driver Tester — runs scenario scripts from tests/NN-name.sh under QEMU.
#
# Usage:
#   ./ndt.sh --test=1                       single scenario, 1 iter
#   ./ndt.sh --test=1,2,71 --iteration=10   batched: each test 10× back-to-back
#   ./ndt.sh --test=1 -i 10 --stop-at-fail  abort whole run on first FAIL
#
# Each (test × iter) gets its own fresh QEMU session and a dedicated artifact
# directory under /tmp/ndt/<run-id>/test-NN-name/iter-NNN/:
#
#   console.log     ttyS0 capture (kernel + initramfs + scenario sentinels)
#   scenario.log    host-side scenario stdout/stderr
#   qemu.log        QEMU process stdout/stderr
#   verdict.txt     "PASS" or "FAIL: <reason>"
#   dmesg.txt       (on FAIL) cooperative DMESG via the ttyS1 channel
#
# Symlink /tmp/ndt/latest points at the newest run-id.
#
# Test resolution: --test=N matches tests/NN-*.sh (zero-padded to 2 digits).
#
# Exit codes:
#   0   all iterations passed
#   1   at least one FAIL
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

tests_csv=""
iters=1
stop_at_fail=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)        usage 0 1 ;;
        --stop-at-fail)   stop_at_fail=1 ;;
        --test=*)         tests_csv="${arg#--test=}" ;;
        -t)               echo "[ndt] use --test=N,M (= form)" >&2; usage ;;
        --iteration=*)    iters="${arg#--iteration=}" ;;
        -i)               echo "[ndt] use --iteration=N (= form)" >&2; usage ;;
        *)                echo "[ndt] unknown arg: $arg" >&2; usage ;;
    esac
done

[[ -z "$tests_csv" ]] && { echo "[ndt] --test=N required" >&2; usage; }
if ! [[ "$iters" =~ ^[0-9]+$ ]] || (( iters < 1 )); then
    echo "[ndt] bad --iteration: $iters" >&2; usage
fi

# --- test resolution --------------------------------------------------------

declare -a tests_paths tests_names
IFS=',' read -ra _nums <<< "$tests_csv"
for n in "${_nums[@]}"; do
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo "[ndt] bad test number: $n" >&2; usage
    fi
    nn=$(printf '%03d' "$((10#$n))")
    shopt -s nullglob
    matches=( "$NDT/tests/$nn"-*.sh )
    shopt -u nullglob
    if (( ${#matches[@]} == 0 )); then
        echo "[ndt] no test matches tests/$nn-*.sh" >&2; exit 2
    elif (( ${#matches[@]} > 1 )); then
        echo "[ndt] multiple matches for tests/$nn-*.sh: ${matches[*]}" >&2; exit 2
    fi
    tests_paths+=( "${matches[0]}" )
    name=$(basename "${matches[0]}" .sh)
    tests_names+=( "$name" )
done

# --- run-id + dir layout ----------------------------------------------------

run_id=$(date +%Y%m%d-%H%M%S)-$$
RUN_DIR=/tmp/ndt/$run_id
mkdir -p "$RUN_DIR"
ln -snf "$run_id" /tmp/ndt/latest

{
    echo "ndt run $run_id"
    echo "args: $*"
    if [[ -d "$NDT/third_party/linux-fork/.git" ]]; then
        echo "linux-fork: $(git -C "$NDT/third_party/linux-fork" rev-parse --short HEAD 2>/dev/null)"
    fi
    if [[ -d "$NDT/third_party/blktests-fork/.git" ]]; then
        echo "blktests-fork: $(git -C "$NDT/third_party/blktests-fork" rev-parse --short HEAD 2>/dev/null)"
    fi
} > "$RUN_DIR/args.txt"

PANIC_RE='Kernel panic|kernel BUG at|Oops:|Unable to handle kernel|general protection fault|stack segment'

# Parse the test file's `# ndt-expected:` header (pass|fail).  Defaults to
# "pass" when absent.  Used by the runner to invert the summary verdict for
# tests whose whole purpose is to produce a FAIL (e.g. 002-always-fail).
parse_test_expected() {
    local file=$1 val
    val=$(awk '
        NR > 1 && !/^#/ && !/^$/ { exit }
        /^# ndt-expected:/ {
            sub(/^# ndt-expected:[ \t]*/, "")
            sub(/[ \t]+$/, "")
            print; exit
        }
    ' "$file")
    case "$val" in
        pass|fail) printf '%s' "$val" ;;
        "")        printf 'pass' ;;
        *)
            echo "[ndt] bad ndt-expected value '$val' in $file (use pass|fail)" >&2
            return 1
            ;;
    esac
}

# --- watcher subshell -------------------------------------------------------
# Watches QEMU + console.log; if QEMU dies or kernel panic appears, kills the
# scenario (SIGTERM) and writes the cause into $cause_file.  Exits silently
# if the scenario completes first (happy path).

launch_watcher() {
    local console=$1 cause=$2 scenario_pid=$3 qemu_pid=$4
    (
        while kill -0 "$scenario_pid" 2>/dev/null; do
            if ! kill -0 "$qemu_pid" 2>/dev/null; then
                echo "qemu-died" > "$cause"
                kill -TERM "$scenario_pid" 2>/dev/null
                return 0
            fi
            if [[ -f "$console" ]] && grep -Eq -- "$PANIC_RE" "$console"; then
                echo "panic" > "$cause"
                kill -TERM "$scenario_pid" 2>/dev/null
                return 0
            fi
            sleep 1
        done
    ) &
}

# --- per-iter execution -----------------------------------------------------

# run_iter <test-name> <test-path> <iter-num>
# Returns: 0 PASS, 1 FAIL.  Writes $iter_dir/verdict.txt.
run_iter() {
    local name=$1 path=$2 iter=$3
    local iter_dir="$RUN_DIR/$name/iter-$(printf '%03d' "$iter")"
    mkdir -p "$iter_dir"

    local console=$iter_dir/console.log
    local slog=$iter_dir/scenario.log
    local qlog=$iter_dir/qemu.log
    local verdict=$iter_dir/verdict.txt
    local cause=$iter_dir/watcher-cause.txt

    : > "$console"; : > "$slog"; : > "$qlog"
    rm -f /tmp/qemu-serial.sock /tmp/qemu-ctrl.sock

    APPEND="console=ttyS0 panic=0 memmap=64K\$0x100000000" \
        "$NDT/scripts/run-qemu.sh" > "$qlog" 2>&1 &
    local qemu_pid=$!

    local _w
    for _w in $(seq 1 100); do
        [[ -S /tmp/qemu-serial.sock ]] && break
        sleep 0.1
    done
    if [[ ! -S /tmp/qemu-serial.sock ]]; then
        echo "FAIL: qemu never created serial socket" > "$verdict"
        kill "$qemu_pid" 2>/dev/null
        wait "$qemu_pid" 2>/dev/null
        return 1
    fi

    socat -u "UNIX-CONNECT:/tmp/qemu-serial.sock" "OPEN:$console,creat,append" &
    local socat_pid=$!

    NDT_CONSOLE_LOG=$console \
    NDT_VERDICT=$verdict \
    NDT_ITER_DIR=$iter_dir \
    NDT_CTRL_SOCK=/tmp/qemu-ctrl.sock \
    NDT_QEMU_PID=$qemu_pid \
    NDT=$NDT \
        bash "$path" > "$slog" 2>&1 &
    local scenario_pid=$!

    launch_watcher "$console" "$cause" "$scenario_pid" "$qemu_pid"
    local watcher_pid=$!

    wait "$scenario_pid"
    local scenario_rc=$?

    kill "$watcher_pid" 2>/dev/null
    wait "$watcher_pid" 2>/dev/null

    # Determine final verdict
    if [[ -s "$cause" ]]; then
        local watcher_cause
        watcher_cause=$(cat "$cause")
        local watcher_msg
        case "$watcher_cause" in
            panic)     watcher_msg="kernel panic" ;;
            qemu-died) watcher_msg="qemu died" ;;
            *)         watcher_msg="$watcher_cause" ;;
        esac
        if [[ -s "$verdict" ]]; then
            printf '; concurrent: %s\n' "$watcher_msg" >> "$verdict"
        else
            printf 'FAIL: %s\n' "$watcher_msg" > "$verdict"
        fi
    elif [[ ! -s "$verdict" ]]; then
        if (( scenario_rc != 0 )); then
            {
                printf 'FAIL: script error (rc=%d)\n' "$scenario_rc"
                printf -- '--- scenario.log tail ---\n'
                tail -20 "$slog"
            } > "$verdict"
        else
            printf 'FAIL: scenario exited 0 without verdict\n' > "$verdict"
        fi
    fi

    local actual=PASS
    head -1 "$verdict" | grep -q '^FAIL' && actual=FAIL

    # Cleanup: try clean EXIT, then kill.
    if kill -0 "$qemu_pid" 2>/dev/null; then
        printf 'EXIT\n' | socat -u - "UNIX-CONNECT:/tmp/qemu-ctrl.sock" 2>/dev/null || true
        for _w in $(seq 1 100); do
            kill -0 "$qemu_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -9 "$qemu_pid" 2>/dev/null
    fi
    wait "$qemu_pid" 2>/dev/null
    kill "$socat_pid" 2>/dev/null
    wait "$socat_pid" 2>/dev/null

    # Compare actual to expected (from `# ndt-expected:` header, default pass).
    local expected result
    if ! expected=$(parse_test_expected "$path"); then
        expected=pass   # parser already complained; treat as default
    fi
    if [[ ( "$actual" == "PASS" && "$expected" == "pass" ) \
       || ( "$actual" == "FAIL" && "$expected" == "fail" ) ]]; then
        result=OK
    else
        result=MISMATCH
    fi
    {
        printf 'actual=%s\nexpected=%s\nresult=%s\n' \
            "$actual" "$expected" "$result"
    } > "$iter_dir/result.txt"

    # Stash for caller summary (last-iter-wins is fine — caller reads files).
    LAST_ACTUAL=$actual
    LAST_EXPECTED=$expected
    LAST_RESULT=$result

    [[ "$result" == "OK" ]]
}

# --- main loop --------------------------------------------------------------

total=$(( ${#tests_paths[@]} * iters ))
current=0
passes=0
fails=0
declare -a summary_rows

run_t0=$EPOCHSECONDS

for k in "${!tests_paths[@]}"; do
    name="${tests_names[$k]}"
    path="${tests_paths[$k]}"
    mkdir -p "$RUN_DIR/$name"
    for (( it = 1; it <= iters; it++ )); do
        current=$((current + 1))
        printf '[ndt] %d/%d  %-30s iter %3d/%-3d ... ' \
            "$current" "$total" "$name" "$it" "$iters"
        t0=$EPOCHSECONDS
        LAST_ACTUAL=""; LAST_EXPECTED=""; LAST_RESULT=""
        run_iter "$name" "$path" "$it"
        rc=$?
        dt=$((EPOCHSECONDS - t0))
        iter_dir="$RUN_DIR/$name/iter-$(printf '%03d' "$it")"
        verdict_line=$(head -1 "$iter_dir/verdict.txt" 2>/dev/null || echo "(no verdict)")
        summary_rows+=( "$(printf '%-30s %03d   %-4s  %-4s  %-8s  %5ds  %s' \
            "$name" "$it" "$LAST_ACTUAL" "$LAST_EXPECTED" "$LAST_RESULT" "$dt" "$verdict_line")" )
        if (( rc == 0 )); then
            passes=$((passes + 1))
            echo "OK    (${dt}s)  actual=$LAST_ACTUAL expected=$LAST_EXPECTED"
        else
            fails=$((fails + 1))
            echo "MISMATCH  (${dt}s)  actual=$LAST_ACTUAL expected=$LAST_EXPECTED"
            echo "        $verdict_line"
            echo "        log: $iter_dir/"
            if (( stop_at_fail )); then
                echo "[ndt] --stop-at-fail, aborting"
                break 2
            fi
        fi
    done
done

run_dt=$((EPOCHSECONDS - run_t0))

# --- summary ----------------------------------------------------------------

{
    cat "$RUN_DIR/args.txt"
    printf 'duration: %ds\n' "$run_dt"
    echo
    printf '%-30s %5s   %-4s  %-4s  %-8s  %6s  %s\n' \
        test iter actual exp result time 'detail'
    for row in "${summary_rows[@]}"; do
        echo "$row"
    done
    echo
    printf 'summary: %d/%d OK (mismatch=%d)\n' "$passes" "$total" "$fails"
} | tee "$RUN_DIR/summary.txt"

echo
echo "[ndt] artifacts: $RUN_DIR/"
echo "[ndt] symlink:   /tmp/ndt/latest"

(( fails == 0 ))
