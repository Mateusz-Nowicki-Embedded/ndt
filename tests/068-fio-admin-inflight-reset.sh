#!/bin/bash
# Scenario wrapper: run blktests nvme/068 with a 5 s admin-queue
# completion delay, N times, and print a per-iteration summary.
#
# The pre-test cq-delay holds admin CQEs for 5 s, so the burst of
# `nvme id-ctrl` commands fired by 068 is still in flight on the
# admin SQ when reset_controller is kicked.  That stresses the
# in-flight cancel path (nvme_cancel_tagset on the admin tagset).
#
# Usage:
#   tests/068-fio-admin-inflight-reset.sh            # default 3 iterations
#   tests/068-fio-admin-inflight-reset.sh 10         # 10 iterations
#   tests/068-fio-admin-inflight-reset.sh -h         # show this help
#
# Exit codes:
#   0   all iterations passed
#   1   at least one iteration failed
#   2   bad arguments / setup error

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NDT=$(cd "$HERE/.." && pwd)

usage() {
	awk 'NR==1{next} /^#/{sub(/^#[ \t]?/,""); print; next} {exit}' "$0" >&2
	exit "${1:-2}"
}

case "${1:-}" in
	-h|--help) usage 0 ;;
esac

iter=${1:-3}
if ! [[ "$iter" =~ ^[0-9]+$ ]] || (( iter < 1 )); then
	echo "[068-scenario] bad iteration count: $iter" >&2
	usage
fi

if [[ ! -x "$NDT/ndt.sh" ]]; then
	echo "[068-scenario] $NDT/ndt.sh missing or not executable" >&2
	exit 2
fi

# Per-iter log lives next to ndt.sh's per-run console logs so the
# scenario log and the underlying QEMU console can be cross-referenced.
log_dir=/tmp
declare -a row_status=() row_time=()
pass=0
fail=0

scenario_t0=$EPOCHSECONDS

for (( i = 1; i <= iter; i++ )); do
	printf '[068-scenario] iter %d/%d ... ' "$i" "$iter"
	t0=$EPOCHSECONDS
	log="$log_dir/ndt-068-scenario-iter${i}.log"
	if "$NDT/ndt.sh" 68 cq-delay=0:5000 > "$log" 2>&1; then
		st=PASS
		pass=$((pass + 1))
	else
		st=FAIL
		fail=$((fail + 1))
	fi
	dt=$((EPOCHSECONDS - t0))
	row_status+=("$st")
	row_time+=("$dt")
	echo "$st  (${dt}s)  log: $log"
done

scenario_dt=$((EPOCHSECONDS - scenario_t0))

echo "---"
printf '%-6s %-6s %-8s\n' iter status time
for (( i = 0; i < iter; i++ )); do
	printf '%-6d %-6s %-7ss\n' "$((i + 1))" "${row_status[i]}" "${row_time[i]}"
done
echo "---"
echo "[068-scenario] summary: ${pass}/${iter} passed (fail=${fail}, total=${scenario_dt}s)"

(( fail == 0 ))
