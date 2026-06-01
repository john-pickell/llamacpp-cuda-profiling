#!/usr/bin/env bash
# env.sh — capture the MACHINE/BUILD environment for reproducible benchmarks.
# Writes a markdown report (default: env.md at repo root).
#
# Scope: OS, CPU, GPU, CUDA toolkit, llama.cpp commit — everything that is
# constant across models. Run ONCE per benchmarking session.
# Per-model fingerprints (sha256) are recorded by bench.sh next to each CSV.
#
# All inputs accepted as CLI args OR environment variables (args win).
# Run with --help for the full list.

set -euo pipefail

# Resolve the repo root from this script's location, so output lands at the
# repo root regardless of the current working directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- defaults (env var if set, else empty/default) ----
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-}"
OUT="${OUT:-$REPO_ROOT/env.md}"

print_usage() {
  cat <<'USAGE'
env.sh — capture hardware/software environment to a markdown report.

USAGE:
  ./scripts/env.sh [options]

OPTIONS:
  --llama-cpp-dir PATH   Path to your llama.cpp git checkout (records the build
                         commit hash).            [env: LLAMA_CPP_DIR]
  --out PATH             Output markdown file.     [env: OUT] (default: env.md)
  -h, --help             Show this help and exit.

NOTES:
  - Captures MACHINE/BUILD state only (OS, CPU, GPU, CUDA, llama.cpp commit).
    Run this ONCE per benchmarking session — it is constant across models.
  - Per-model fingerprints (sha256) are recorded by bench.sh, next to each
    result CSV, since they differ per model. That keeps each result
    self-documenting and avoids re-running env.sh per quant.
  - All options are optional; CLI args override environment variables.

EXAMPLES:
  ./scripts/env.sh --llama-cpp-dir ~/src/llama.cpp

  # or via env var:
  LLAMA_CPP_DIR=~/src/llama.cpp ./scripts/env.sh
USAGE
}

# ---- parse args (override env) ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --llama-cpp-dir) LLAMA_CPP_DIR="$2"; shift 2 ;;
    --out)           OUT="$2"; shift 2 ;;
    -h|--help)       print_usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; echo; print_usage; exit 1 ;;
  esac
done

section()   { printf '\n## %s\n\n' "$1" >> "$OUT"; }
codeblock() { printf '```\n%s\n```\n' "$1" >> "$OUT"; }

# Fresh file
{
  echo "# Benchmark Environment"
  echo
  echo "_Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')_"
} > "$OUT"

section "Operating system"
command -v lsb_release >/dev/null 2>&1 && codeblock "$(lsb_release -d | cut -f2-)"
codeblock "$(uname -srmo)"

section "CPU"
codeblock "$(lscpu | grep -E 'Model name|^CPU\(s\)' | sed 's/  */ /g')"

section "Memory"
codeblock "$(free -h | awk 'NR==1 || /^Mem:/')"

section "GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
  codeblock "$(nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv)"
else
  codeblock "nvidia-smi not found"
fi

section "CUDA toolkit"
if command -v nvcc >/dev/null 2>&1; then
  codeblock "$(nvcc --version)"
else
  codeblock "nvcc not found"
fi

section "llama.cpp"
if [[ -n "$LLAMA_CPP_DIR" && -d "$LLAMA_CPP_DIR/.git" ]]; then
  commit="$(git -C "$LLAMA_CPP_DIR" rev-parse HEAD)"
  desc="$(git -C "$LLAMA_CPP_DIR" describe --tags --always 2>/dev/null || echo n/a)"
  codeblock "commit:   $commit
describe: $desc"
else
  codeblock "(not recorded — pass --llama-cpp-dir PATH to your llama.cpp checkout)"
fi

echo "Wrote $OUT"
