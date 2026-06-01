#!/usr/bin/env bash
# check-profiling.sh — verify the Nsight profiling tools are installed and can
# actually collect counters on this machine. Pure check: exits 0 if profiling
# is ready, 1 if something needs attention. No instructions here — see
# docs/profiling.md for setup, the ERR_NVGPUCTRPERM fix, and capture commands.

set -uo pipefail

# Optional smoke test: a short CUDA command to profile one kernel launch.
PROFILE_CMD="${PROFILE_CMD:-}"

print_usage() {
  cat <<'USAGE'
check-profiling.sh — verify nsys + ncu are installed and can collect counters.

USAGE:
  ./scripts/check-profiling.sh [--profile-cmd "CMD"]

OPTIONS:
  --profile-cmd "CMD"  A short CUDA command to actually profile one kernel
                       launch (real counter-access test).  [env: PROFILE_CMD]
  -h, --help           Show this help and exit.

EXIT STATUS:
  0  nsys and ncu found (and smoke test passed, if a command was given)
  1  a tool is missing, or the smoke test could not collect counters

If the smoke test fails with ERR_NVGPUCTRPERM (common on GeForce cards),
see docs/profiling.md for the one-time permission fix.

EXAMPLE:
  ./scripts/check-profiling.sh \
    --profile-cmd "$HOME/src/llama.cpp/build/bin/llama-cli -m MODEL.gguf -p hi -n 1 -ngl 99"
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-cmd) PROFILE_CMD="$2"; shift 2 ;;
    -h|--help)     print_usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; echo; print_usage; exit 1 ;;
  esac
done

status=0

echo "== Nsight Systems (nsys) =="
if command -v nsys >/dev/null 2>&1; then
  nsys --version | head -n1
else
  echo "  MISSING — install Nsight Systems (see docs/profiling.md)."
  status=1
fi

echo
echo "== Nsight Compute (ncu) =="
if command -v ncu >/dev/null 2>&1; then
  ncu --version | head -n1
else
  echo "  MISSING — install Nsight Compute (see docs/profiling.md)."
  status=1
fi

echo
if [[ -n "$PROFILE_CMD" ]]; then
  if command -v ncu >/dev/null 2>&1; then
    echo "== Smoke test: profiling one kernel launch =="
    if ncu --launch-count 1 --target-processes all $PROFILE_CMD >/tmp/ncu_smoke.log 2>&1; then
      echo "  OK — ncu collected counters successfully."
    else
      echo "  FAILED — ncu could not collect counters. Tail of log:"
      tail -n 5 /tmp/ncu_smoke.log | sed 's/^/    /'
      if grep -q "ERR_NVGPUCTRPERM" /tmp/ncu_smoke.log; then
        echo "  -> ERR_NVGPUCTRPERM: apply the permission fix in docs/profiling.md."
      fi
      status=1
    fi
  else
    echo "(Skipping smoke test — ncu not installed.)"
  fi
else
  echo "(No --profile-cmd given; skipped the counter-access smoke test.)"
  echo " Run with --profile-cmd to fully verify counter access before M3/M4."
fi

echo
if [[ "$status" -eq 0 ]]; then
  echo "Profiling tooling looks ready."
else
  echo "Profiling setup needs attention — see docs/profiling.md."
fi
exit "$status"
