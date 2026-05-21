#!/bin/bash
# Scenario helper library — sourced by tests/<NN>-name.sh.
#
# Runtime contract (env vars set by ndt.sh runner before exec):
#   NDT_CONSOLE_LOG   path to ttyS0 capture file (grep target for wait_for)
#   NDT_SCENARIO_LOG  scenario stdout/stderr already routed here by runner
#   NDT_VERDICT       path to verdict.txt (written by scenario_pass/_fail)
#   NDT_ITER_DIR      iter-NNN directory (for dmesg.txt etc.)
#   NDT_CTRL_SOCK     /tmp/qemu-ctrl.sock
#   NDT_QEMU_PID      QEMU process PID
#   NDT               NDT repo root (so we can call scripts/qemu-*.sh)

set -u

# --- internals --------------------------------------------------------------

_ndt_require_qemu() {
    if ! kill -0 "${NDT_QEMU_PID:-0}" 2>/dev/null; then
        scenario_fail "qemu process gone (pid=${NDT_QEMU_PID:-?})"
    fi
}

_ndt_log() { printf '[scenario] %s\n' "$*"; }

# --- verdict ----------------------------------------------------------------

scenario_pass() {
    printf 'PASS\n' > "$NDT_VERDICT"
    _ndt_log "PASS"
    exit 0
}

scenario_fail() {
    local reason=${1:-no reason given}
    printf 'FAIL: %s\n' "$reason" > "$NDT_VERDICT"
    _ndt_log "FAIL: $reason"
    # If invoked from a subshell (background run_blktest etc.), $$ stays at
    # the top-level scenario PID; signal it so the whole scenario aborts,
    # not just the subshell.
    if (( BASH_SUBSHELL > 0 )); then
        kill -TERM "$$" 2>/dev/null
    fi
    exit 1
}

# --- raw channel access -----------------------------------------------------

# ctrl <line> — push raw line to ttyS1.
ctrl() {
    _ndt_require_qemu
    CTRL_SOCK="$NDT_CTRL_SOCK" "$NDT/scripts/qemu-ctrl.sh" "$*"
}

# --- console grep -----------------------------------------------------------

# wait_for <ERE-pattern> [timeout-sec]
# Polls $NDT_CONSOLE_LOG for the pattern.  Returns 0 on hit, 1 on timeout.
# Default timeout 30 s.
wait_for() {
    local pattern=$1 timeout=${2:-30}
    local deadline=$(( $(date +%s) + timeout ))
    while (( $(date +%s) < deadline )); do
        _ndt_require_qemu
        if [[ -f "$NDT_CONSOLE_LOG" ]] && grep -Eq -- "$pattern" "$NDT_CONSOLE_LOG"; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# wait_for_cmd_done <cmd> [timeout]
# Convenience: waits for NDT_CMD_DONE for the named cmd, returns its rc.
# Echoes the rc captured.  Caller uses: rc=$(wait_for_cmd_done RUN 600) || ...
_ndt_last_cmd_done_rc() {
    local cmd=$1
    grep -E "NDT_CMD_DONE cmd='$cmd' rc=[0-9]+" "$NDT_CONSOLE_LOG" \
        | tail -1 \
        | sed -E "s/.*rc=([0-9]+).*/\1/"
}

# --- high-level commands ----------------------------------------------------

# run_blktest <id> [k=v ...]
# Sends RUN, waits for CMD_DONE, returns the rc reported by initramfs.
# Default timeout 600 s, override with NDT_RUN_TIMEOUT=<sec>.
run_blktest() {
    local timeout=${NDT_RUN_TIMEOUT:-600}
    local before
    before=$(grep -cE "NDT_CMD_DONE cmd='RUN'" "$NDT_CONSOLE_LOG" 2>/dev/null; true)
    : "${before:=0}"
    ctrl "RUN $*"
    if ! wait_for "NDT_CMD_DONE cmd='RUN' rc=[0-9]+" "$timeout"; then
        scenario_fail "run_blktest $1 timeout (${timeout}s)"
    fi
    local after rc
    after=$(grep -cE "NDT_CMD_DONE cmd='RUN'" "$NDT_CONSOLE_LOG" 2>/dev/null; true)
    : "${after:=0}"
    if (( after <= before )); then
        scenario_fail "run_blktest $1: CMD_DONE counter did not advance"
    fi
    rc=$(_ndt_last_cmd_done_rc RUN)
    return "$rc"
}

# exec_in_guest <shell...>
# Sends EXEC, waits for a NEW CMD_DONE (counter advance, not just pattern
# presence — without that, repeat calls match the prior EXEC's CMD_DONE
# immediately and the rc we echo back is stale).  Returns rc.
exec_in_guest() {
    local timeout=${NDT_EXEC_TIMEOUT:-300}
    local before after
    before=$(grep -cE "NDT_CMD_DONE cmd='EXEC'" "$NDT_CONSOLE_LOG" 2>/dev/null; true)
    : "${before:=0}"
    ctrl "EXEC $*"
    local deadline=$(( $(date +%s) + timeout ))
    while (( $(date +%s) < deadline )); do
        _ndt_require_qemu
        after=$(grep -cE "NDT_CMD_DONE cmd='EXEC'" "$NDT_CONSOLE_LOG" 2>/dev/null; true)
        : "${after:=0}"
        (( after > before )) && break
        sleep 0.1
    done
    if (( after <= before )); then
        scenario_fail "exec_in_guest timeout (${timeout}s): $*"
    fi
    _ndt_last_cmd_done_rc EXEC
}

# go [label]
# Releases the inner-iter gate (consumed by a blktest's own read on ttyS1,
# not by the initramfs main loop).
go() {
    ctrl "GO${1:+ $1}"
}

# dmesg_dump
# Triggers DMESG in guest, waits for done, extracts the captured block
# from console.log into $NDT_ITER_DIR/dmesg.txt.
dmesg_dump() {
    local timeout=${NDT_DMESG_TIMEOUT:-30}
    ctrl "DMESG"
    if ! wait_for "NDT_CMD_DONE cmd='DMESG' rc=[0-9]+" "$timeout"; then
        _ndt_log "dmesg_dump: timeout (${timeout}s)"
        return 1
    fi
    awk '/NDT_DMESG_BEGIN/{flag=1; next} /NDT_DMESG_END/{flag=0} flag' \
        "$NDT_CONSOLE_LOG" > "$NDT_ITER_DIR/dmesg.txt"
    _ndt_log "dmesg_dump: wrote $NDT_ITER_DIR/dmesg.txt"
}

# last_blktest_reason
# Echoes the reason from the most recent NDT_STATUS line (set by RUN handler
# in initramfs).  Useful for building scenario_fail messages.
last_blktest_reason() {
    grep -E "NDT_STATUS status=" "$NDT_CONSOLE_LOG" \
        | tail -1 \
        | sed -E "s/.*reason='([^']*)'.*/\1/"
}

# --- sanity check on source -------------------------------------------------

for _v in NDT NDT_CONSOLE_LOG NDT_VERDICT NDT_ITER_DIR \
          NDT_CTRL_SOCK NDT_QEMU_PID; do
    if [[ -z "${!_v:-}" ]]; then
        echo "[scenario] missing required env: $_v" >&2
        exit 2
    fi
done
unset _v
