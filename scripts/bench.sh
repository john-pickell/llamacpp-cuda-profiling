#!/usr/bin/env bash
# bench.sh — run a FIXED llama-bench config and emit a CSV to results/.
#
# The benchmark config (prompt size, gen size, etc.) is fixed by default so runs
# stay comparable over time. Paths and a few knobs are accepted as CLI args OR
# environment variables (args win). Run with --help for the full list.
#
# Each test runs REPS times; llama-bench reports average + standard deviation and
# does an internal warmup run (discarded) before the timed reps.

set -euo pipefail

# Resolve the repo root from this script's location, so outputs land at the
# repo root regardless of the current working directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- defaults (env var if set, else default) ----
LLAMA_BENCH="${LLAMA_BENCH:-}"
MODEL="${MODEL:-}"
PROMPT_TOKENS="${PROMPT_TOKENS:-512}"   # prefill size      -> "pp512"
GEN_TOKENS="${GEN_TOKENS:-128}"         # decode size       -> "tg128"
NGL="${NGL:-99}"                        # GPU layers (99 = all)
REPS="${REPS:-10}"                      # reps per test (avg + stddev)
FLASH_ATTN="${FLASH_ATTN:-0}"           # 0 = off, 1 = on
LOCK_CLOCK="${LOCK_CLOCK:-0}"           # 1 = pin GPU clocks during run
LOCK_FREQ="${LOCK_FREQ:-1695}"          # graphics clock MHz to pin to
OUTDIR="${OUTDIR:-$REPO_ROOT/results}"

print_usage() {
  cat <<'USAGE'
bench.sh — run a fixed llama-bench config and write a CSV to results/.

USAGE:
  ./scripts/bench.sh --model PATH --llama-bench PATH [options]

REQUIRED:
  --model PATH         Path to the GGUF model file.        [env: MODEL]
  --llama-bench PATH   Path to the llama-bench binary
                       (e.g. build/bin/llama-bench).        [env: LLAMA_BENCH]

OPTIONS (defaults keep runs comparable; change only deliberately):
  --prompt N           Prompt/prefill tokens (pp).   [env: PROMPT_TOKENS] (512)
  --gen N              Generation/decode tokens (tg).[env: GEN_TOKENS]    (128)
  --ngl N              GPU layers to offload.        [env: NGL]           (99)
  --reps N             Repetitions per test.         [env: REPS]          (10)
  --flash-attn 0|1     Flash attention on/off.       [env: FLASH_ATTN]    (0)
  --lock-clock         Pin GPU clocks during the run (needs sudo; restored
                       on exit).                     [env: LOCK_CLOCK=1]
  --lock-freq MHz      Graphics clock to pin to.     [env: LOCK_FREQ]     (1695)
  --outdir DIR         Output directory for CSVs.    [env: OUTDIR] (results)
  -h, --help           Show this help and exit.

NOTES:
  - CLI args override environment variables override defaults.
  - Output file is named after the model + timestamp so quants don't collide:
    results/bench_<model>_<UTC timestamp>.csv
  - Check valid clock values first:
    nvidia-smi --query-supported-clocks=graphics --format=csv | head

EXAMPLES:
  ./scripts/bench.sh \
    --model ~/models/Llama-3.1-8B-Instruct-Q5_K_M.gguf \
    --llama-bench ~/src/llama.cpp/build/bin/llama-bench

  # stable clocks:
  ./scripts/bench.sh --model ...Q5_K_M.gguf --llama-bench .../llama-bench \
                     --lock-clock --lock-freq 1695
USAGE
}

# ---- parse args (override env) ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)       MODEL="$2"; shift 2 ;;
    --llama-bench) LLAMA_BENCH="$2"; shift 2 ;;
    --prompt)      PROMPT_TOKENS="$2"; shift 2 ;;
    --gen)         GEN_TOKENS="$2"; shift 2 ;;
    --ngl)         NGL="$2"; shift 2 ;;
    --reps)        REPS="$2"; shift 2 ;;
    --flash-attn)  FLASH_ATTN="$2"; shift 2 ;;
    --lock-clock)  LOCK_CLOCK=1; shift ;;
    --lock-freq)   LOCK_FREQ="$2"; shift 2 ;;
    --outdir)      OUTDIR="$2"; shift 2 ;;
    -h|--help)     print_usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; echo; print_usage; exit 1 ;;
  esac
done

# ---- validate required inputs (clear, actionable errors) ----
err=0
if [[ -z "$LLAMA_BENCH" ]]; then
  echo "ERROR: missing --llama-bench (or LLAMA_BENCH env var)." >&2; err=1
elif [[ ! -x "$LLAMA_BENCH" ]]; then
  echo "ERROR: llama-bench not found or not executable: $LLAMA_BENCH" >&2; err=1
fi
if [[ -z "$MODEL" ]]; then
  echo "ERROR: missing --model (or MODEL env var)." >&2; err=1
elif [[ ! -f "$MODEL" ]]; then
  echo "ERROR: model file not found: $MODEL" >&2; err=1
fi
if [[ "$err" -ne 0 ]]; then echo; echo "Run './scripts/bench.sh --help' for usage." >&2; exit 1; fi

# ---- GPU clock control (optional, always restored on exit) ----
restore_clocks() {
  if [[ "$LOCK_CLOCK" == "1" ]]; then
    echo "Restoring default GPU clocks..."
    sudo nvidia-smi -rgc >/dev/null 2>&1 || true
  fi
}
trap restore_clocks EXIT

if [[ "$LOCK_CLOCK" == "1" ]]; then
  echo "Enabling persistence mode and locking graphics clock to ${LOCK_FREQ} MHz..."
  sudo nvidia-smi -pm 1 >/dev/null
  sudo nvidia-smi -lgc "${LOCK_FREQ}" >/dev/null
fi

# ---- derive output filename from the model (so quants don't collide) ----
model_base="$(basename "$MODEL")"
model_tag="${model_base%.gguf}"
mkdir -p "$OUTDIR"
TS="$(date -u '+%Y%m%dT%H%M%SZ')"
OUT="${OUTDIR}/bench_${model_tag}_${TS}.csv"

echo "llama-bench: pp${PROMPT_TOKENS} tg${GEN_TOKENS} ngl=${NGL} reps=${REPS} fa=${FLASH_ATTN} lock_clock=${LOCK_CLOCK}"
echo "model: $MODEL"
echo

"$LLAMA_BENCH" \
  -m "$MODEL" \
  -p "$PROMPT_TOKENS" \
  -n "$GEN_TOKENS" \
  -ngl "$NGL" \
  -fa "$FLASH_ATTN" \
  -r "$REPS" \
  -o csv | tee "$OUT"

echo
echo "Wrote $OUT"

# ---- record the model's fingerprint next to the CSV (provenance) ----
# Each result is self-documenting: which exact GGUF produced it. This is why
# env.sh runs once (machine state) but the model hash is captured per run.
SIDECAR="${OUT%.csv}.provenance.txt"
{
  echo "model_file:   $MODEL"
  echo "model_size:   $(du -h "$MODEL" | cut -f1)"
  echo "model_sha256: $(sha256sum "$MODEL" | cut -d' ' -f1)"
  echo "config:       pp=${PROMPT_TOKENS} tg=${GEN_TOKENS} ngl=${NGL} reps=${REPS} fa=${FLASH_ATTN} lock_clock=${LOCK_CLOCK}"
  echo "timestamp:    ${TS}"
} > "$SIDECAR"
echo "Wrote $SIDECAR (model fingerprint + config)"
echo
echo "Human-readable view of the same run: replace '-o csv' with '-o md'."
