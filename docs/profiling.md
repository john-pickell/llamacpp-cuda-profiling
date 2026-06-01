# Profiling: setup and capture commands

Reference for the Nsight tools used in milestones M3 (timeline) and M4
(per-kernel). Verify your setup first with:

```bash
./scripts/check-profiling.sh --profile-cmd "<a short CUDA command>"
```

That script only *checks* that the tools work. The actual setup, the
permission fix, and the capture commands live here.

---

## Tools

- **Nsight Systems (`nsys`)** — system-level timeline. Where wall-time goes:
  kernel compute vs host↔device copies vs sync/idle. Used in **M3**.
- **Nsight Compute (`ncu`)** — per-kernel deep profiling: occupancy, achieved
  memory throughput, memory-vs-compute bound verdict. Used in **M4**.

`nsys` usually ships with the CUDA toolkit; `ncu` (Nsight Compute) sometimes
needs a separate install. Confirm both resolve on your `PATH`.

---

## The ERR_NVGPUCTRPERM permission fix (consumer GPUs)

On GeForce cards, `ncu` typically fails to read GPU performance counters
because they're locked to admin by default, surfacing as `ERR_NVGPUCTRPERM`.
Fix it with **one** of the following.

**Quick (per-invocation):** run `ncu` under sudo.

```bash
sudo ncu ...
```

**Permanent (recommended):** allow non-admin counter access, then reboot.

```bash
echo 'options nvidia NVreg_RestrictProfilingToAdminUsers=0' \
  | sudo tee /etc/modprobe.d/nvidia-profiler.conf
sudo update-initramfs -u
sudo reboot
```

> Record which option you used in this repo (e.g. a note here or in the commit
> message) so the profiling setup is reproducible by someone else.

`nsys` does **not** require this — it doesn't read the restricted counters.

---

## M3 — timeline capture with nsys

Capture a representative prefill + decode run:

```bash
nsys profile \
  --output results/nsys_<model-tag> \
  --force-overwrite true \
  ~/src/llama.cpp/build/bin/llama-cli \
    -m <MODEL>.gguf -ngl 99 -p "<a few hundred tokens of prompt>" -n 128
```

This writes `results/nsys_<model-tag>.nsys-rep` (gitignored — it's large).
Open it in the Nsight Systems GUI, or get a CLI stats summary:

```bash
nsys stats results/nsys_<model-tag>.nsys-rep
```

For M3's Definition of Done, pull out the top kernels by total time and the
split between compute / memcpy / idle. Expect a quantized matmul (MMQ) kernel
and attention to dominate.

---

## M4 — per-kernel deep dive with ncu

Profile the top 1–2 kernels identified in M3. `ncu` is slow, so target a
specific kernel and a few launches rather than the whole run:

```bash
ncu \
  --set full \
  --launch-count 5 \
  --kernel-name-base demangled \
  --kernel-name "regex:<kernel name fragment>" \
  --export results/ncu_<model-tag> \
  ~/src/llama.cpp/build/bin/llama-cli \
    -m <MODEL>.gguf -ngl 99 -p "hello" -n 16
```

Writes `results/ncu_<model-tag>.ncu-rep` (gitignored). Open in the Nsight
Compute GUI. For each kernel record: achieved occupancy, achieved DRAM
throughput (GB/s) vs the ~912 GB/s peak, and the memory-vs-compute verdict.

The decode-dominant kernel should come out **memory-bound**, near a meaningful
fraction of peak bandwidth — the measurement that anchors the roofline writeup
in M5.

---

## Notes

- `.nsys-rep` and `.ncu-rep` files are large and are gitignored. Commit the
  *summaries* (tables, key numbers) into the writeup, not the raw captures.
- Lock GPU clocks (`bench.sh --lock-clock`, or `nvidia-smi -lgc`) while
  profiling too, so runs are comparable.
