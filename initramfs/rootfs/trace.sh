#!/bin/bash
  # Convenience runner: pick a trace mode, run a fixed fio workload under it.
  #
  #   ./trace.sh io          -> :mod:vnvme (per-pass housekeeping of the poll loop)
  #   ./trace.sh raise       -> graph-root endpoint_raise_msix (host ISR inline)
  #   ./trace.sh period [fn] -> poll-loop period via an anchor + abstime [sm_process]
  #   ./trace.sh sleeps      -> every usleep_range (does the poll loop sleep?)
  #
  # Host side: sed -n '/VNVME_FG_BEGIN/,/VNVME_FG_END/p' "$RUN_DIR/console.log"

  FIO="fio --name=p --filename=/dev/nvme0n1 --rw=read --bs=64k --size=4m --direct=1"

  mode=${1:-io}
  case "$mode" in
      io)     vnvme-trace run $FIO ;;
      raise)  GRAPH_FN=endpoint_raise_msix vnvme-trace run $FIO ;;
      period) PERIOD=${2:-sm_process} vnvme-trace run $FIO ;;
      sleeps) SLEEPS=1 vnvme-trace run $FIO ;;
      *)      echo "usage: $0 {io|raise|period [fn]|sleeps}" >&2; exit 1 ;;
  esac

