# llamacpp-cuda-profiling

Benchmarking and Nsight profiling of llama.cpp LLM inference — prefill vs decode
bottlenecks, roofline analysis, and CUDA kernel deep-dives on an RTX 3080 Ti
(Ampere).

> **Status:** 🚧 In progress. Baseline established; profiling and analysis
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

<!-- Fill in as milestones complete. Keep the headline numbers here at the top. -->

| Config | Prefill (t/s) | Decode (t/s) | Decode % of bandwidth ceiling |
|--------|---------------|--------------|-------------------------------|
| Q4_K_M, full offload | _TBD_ | _TBD_ | _TBD_ |
| Q5_K_M | 1511.5 | 109.3 | _TBD_ |
| Q8_0   | _TBD_ | _TBD_ | _TBD_ |

*Headline chart and per-kernel profiling results land here as the analysis
progresses.*

## Reproduce

```bash
# 1. Capture environment (GPU, driver, toolkit, llama.cpp commit, model sha256)
./scripts/env.sh

# 2. Run the baseline benchmark
./scripts/bench.sh          # emits CSV to results/
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
