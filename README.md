# llamacpp-cuda-profiling

Benchmarking and Nsight profiling of llama.cpp LLM inference — prefill vs decode
bottlenecks, roofline analysis, and CUDA kernel deep-dives on an RTX 3080 Ti
(Ampere).

> **Status:** In progress. Baseline established; profiling and analysis
> landing milestone by milestone (see [Roadmap](#roadmap)).

## What this is

A systematic study of *where the time actually goes* when running an 8B LLM on
consumer hardware, and *why*. The work tests one core idea against real
measurements:

- **Prefill (prompt processing) is compute-bound** — large GEMMs, high
  arithmetic intensity.
- **Decode (token generation) is memory-bandwidth-bound** — effectively a GEMV
  at batch size 1, where every token must stream the full weight set from VRAM.
  Decode throughput is roughly `memory_bandwidth / model_bytes_per_token`.

The goal is to *predict* throughput from first principles, *measure* it, *profile
the responsible kernels*, and *explain the gap*.

## Hardware

| Component   | Spec |
|-------------|------|
| GPU         | NVIDIA RTX 3080 Ti — Ampere, compute capability 8.6 |
| VRAM / b/w  | 12 GB GDDR6X, ~912 GB/s (the number that bounds decode) |
| CPU / RAM   | Intel i9 / 64 GB |
| OS / CUDA   | Ubuntu 26.04 LTS / CUDA toolkit 12.4, `nvcc` |
| Engine      | llama.cpp built with `-DGGML_CUDA=ON` |
| Model       | Llama 3.1 8B Instruct (GGUF, multiple quantizations) |

## Results

| Config | Prefill (t/s) | Decode (t/s) | Decode % of bandwidth ceiling |
|--------|---------------|--------------|-------------------------------|
| Q4_K_M, full offload | _TBD_ | _TBD_ | _TBD_ |
| Q5_K_M | 4496.89 | 119.54 | _TBD_ |
| Q8_0   | _TBD_ | _TBD_ | _TBD_ |

*Headline chart and per-kernel profiling results land here as the analysis
progresses.*

## Reproduce

All scripts take `--help` and accept either CLI args or environment variables
(args win). No hidden setup — run `--help` to see every option.

Reproducibility is split by lifetime: `env.sh` records the **machine/build
state once** (it's constant across models), while `bench.sh` records each
**model's sha256 fingerprint next to its own result CSV**. So a full
quantization sweep is one `env.sh` run plus one `bench.sh` run per model — and
every CSV is self-documenting about which exact GGUF produced it.

```bash
# 1. Capture the machine/build environment — run ONCE per session
./scripts/env.sh --llama-cpp-dir ~/src/llama.cpp

# 2. Benchmark each model — run once per GGUF. Writes:
#      results/bench_<model>_<timestamp>.csv
#      results/bench_<model>_<timestamp>.provenance.txt   (sha256 + config)
./scripts/bench.sh \
  --model ~/models/Llama-3.1-8B-Instruct-Q5_K_M.gguf \
  --llama-bench ~/src/llama.cpp/build/bin/llama-bench

# Optional: pin GPU clocks for lower run-to-run variance (needs sudo)
./scripts/bench.sh --model ...Q5_K_M.gguf --llama-bench .../llama-bench \
                   --lock-clock --lock-freq 1695

# 3. Verify profiling tools (resolves the ncu permission gotcha below)
./scripts/check-profiling.sh
```

See [`docs/profiling.md`](docs/profiling.md) for the Nsight Systems (`nsys`) and
Nsight Compute (`ncu`) capture commands.

> **Note (consumer GPUs):** `ncu` may fail with `ERR_NVGPUCTRPERM` because GPU
> performance counters are admin-locked. Run under `sudo`, or set
> `NVreg_RestrictProfilingToAdminUsers=0` and reboot.

## Repo layout

```
scripts/      # env capture + benchmark drivers
results/      # benchmark CSVs (committed)
docs/         # profiling notes, WRITEUP.md (the roofline analysis)
charts/       # generated plots
```

## Roadmap

Milestones M0–M6 are tracked in the project's milestones file: baseline harness →
quantization sweep → knob sweep → `nsys` timeline → `ncu` per-kernel → roofline
writeup. This README's results tables fill in as each completes.

## License

MIT
