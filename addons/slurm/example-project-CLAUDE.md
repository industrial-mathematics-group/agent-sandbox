# Simulation runner & checker

Your job in this workspace: **run the Julia simulations in `/workspace`, check their
results, and report.** Decide per run whether it executes locally (in this container)
or on the HPC cluster (via `slurm`). Fix problems in the *runner* tooling, but don't
change the science (see "Rules").

## Layout

- Every subfolder of `/workspace` is one simulation, normally a Julia project
  (`Project.toml`). If it has its own `CLAUDE.md` or `README.md`, read it first: it overrides this file.
- TODO: entry point convention, e.g. `scripts/run.jl <config>`; configs in `configs/*.toml`
- TODO: where outputs go, e.g. `output/<config-name>/` (HDF5/JLD2/CSV)
- Reports go to `<simulation>/reports/YYYY-MM-DD-<config>.md` (create the folder if needed).

## Local or HPC?

Local resources (this container): 8 CPUs, 16 GB RAM (hard container limits; exceeding the
memory kills the run). Network is allowlisted: Julia package server, GitHub, PyPI.
TODO: GPU here? (e.g. "AMD RX 9070 XT via AMDGPU.jl" on the desktop, or "none")

Run **locally** when all of these hold:
- expected runtime < ~10 min, memory < ~12 GB;
- no NVIDIA GPU needed;
- it's a smoke test, a small/reduced configuration, or a check of existing output.

Run on the **HPC cluster** for everything else: long runs, parameter sweeps, NVIDIA/CUDA
code, production-size configurations.

If you can't estimate the cost, first run a reduced version locally (smaller grid, fewer
steps) and extrapolate. Never start a long local run just to find out.

## Running locally

```bash
cd /workspace/<Simulation>
julia --project -e 'using Pkg; Pkg.instantiate()'     # after dependency changes
julia --project -t auto scripts/run.jl <config>       # TODO: real entry point
```
- Use `-t auto`; don't start more than one heavy run at a time.
- Plots: no screen. Save figures to files (`save("fig.png", fig)`), never `display()`.
  GLMakie and CairoMakie work headless; use them for saved figures, not WGLMakie.
- Python helpers (`pyproject.toml`): `uv sync`, then `uv run python …`. Never `pip install`
  into the system Python.

## Running on the HPC cluster (`slurm`)

You only have access through a restricted gateway. Available commands (run inside the simulation folder):

```bash
slurm info                          # current limits (time, GPUs, CPUs, mem, max parallel jobs): check before submitting
slurm instantiate                   # install deps on the cluster; needed after Project/Manifest changes
slurm run hpc/job.sh time=60 gpus=1 cpus=8 mem=16 -- <args>   # sync code + submit
slurm status                        # your jobs
slurm log <jobid> 200               # last 200 lines of a job's output
slurm fetch <jobid> [<jobid>...]    # copy the job's *.jld2 files to data/<jobid>/
slurm cancel <jobid>
```

- Resources are set **only** through `time=` (minutes), `gpus=`, `gputype=`, `cpus=`,
  `mem=` (GB), `partition=`. `#SBATCH` lines in scripts are ignored.
- GPU models are mixed (A100 down to GTX 1070), and without `gputype=` you get whatever is free.
  Set `gputype=` (allowed values in `slurm info`) for benchmarks, memory-hungry runs or anything
  where results or timings must be comparable. `slurm status` shows which GPU a job got.
- GPU jobs: leave out `partition=` → regular GPU queue (reliable, but can wait days).
  `partition=gpuidle` usually starts within the hour but can be **preempted and requeued**:
  use it for short tests, and make long runs restartable. The log then contains every attempt.
  CPU jobs use the default CPU partition. `slurm info` lists what's allowed.
- The job script is a bash script inside the project. It runs with the project as working
  directory, **offline**: everything must be installed with `slurm instantiate` first.
  Template (`hpc/job.sh`):
  ```bash
  #!/bin/bash
  set -euo pipefail
  julia --project=. -t "${JULIA_NUM_THREADS:-1}" scripts/run.jl "$@"   # TODO: real entry point
  ```
- Each job runs in its own snapshot of the project on the cluster. Files it writes there
  (e.g. `results/*.jld2`) stay on the cluster until you **`slurm fetch <jobid>`**: that copies
  them to `data/<jobid>/` (same relative paths, plus `job-info.txt` with job ID, resources,
  node and GPU). Other file types: `slurm fetch <jobid> --pattern '*.csv'`. Snapshots are
  **deleted after 14 days**, so fetch every finished job you want to keep or plot.
  `data/` is output, not source: don't commit it.
- Jobs should also print a compact, machine-readable summary at the end, one line per
  quantity, prefixed with `RESULT`, so a quick check needs no download:
  ```
  RESULT config=base steps=10000 runtime_s=812.4 energy_drift=3.1e-9 status=ok
  ```
  Then evaluate with `slurm log <jobid> 1000 | grep '^RESULT'`.
- Respect the limits from `slurm info`. Prefer few, well-sized jobs over many tiny ones.
  Check `slurm status` instead of polling `log` in a tight loop (wait ≥ 1 min between checks).
- A job that fails within the first minute is almost always a missing `slurm instantiate`,
  a wrong path, or a typo. Read the log before resubmitting, and don't resubmit blindly.

## Checking results

For every run, check at least:
1. **It finished**: exit status ok, no exceptions/warnings in the log, expected output present.
2. **Sanity**: no `NaN`/`Inf`, values in physically plausible ranges.
3. TODO: **simulation-specific invariants**, e.g. energy/mass conservation within `1e-6`,
   convergence order when refining the grid, symmetry.
4. TODO: **reference comparison**, e.g. against `reference/<config>.csv` with
   relative tolerance `1e-8`.

A check fails → report it as failed, with the numbers. Never adjust tolerances, reference
data or checks to make a run pass.

## Reporting

Write `<simulation>/reports/YYYY-MM-DD-<config>.md` with:
- what ran (config, commit hash, local or job ID + resources), runtime;
- each check: pass/fail + the actual values vs. expected;
- anything suspicious, plus your best guess at the cause (clearly marked as a guess);
- a final one-line verdict: `PASS`, `FAIL` or `INCONCLUSIVE`.

End your turn with a short summary table of all runs and verdicts.

## Rules

- **Don't change the science** (model code, physical parameters, reference data, tolerances)
  unless I ask. You may fix runner scripts, job scripts, paths and obvious crashes in tooling;
  say what you changed.
- Work on a git branch `claude/<topic>`, small commits with clear messages. Never push
  (there are no credentials here anyway).
- Don't add dependencies or change `[compat]` without asking.
- Network is allowlisted. If something needs another host, tell me which instead of working around it.
