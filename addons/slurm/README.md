# slurm: jobs on an HPC cluster

`server/claude-slurm-gateway` lets the sandbox submit Slurm jobs without having a shell
on the cluster. The SSH key is pinned to the gateway in `authorized_keys` (forced
command). Claude can only `sync` a project, `instantiate` its Julia deps, `submit` a
script with capped resources, and `status`/`log`/`cancel` **its own** jobs. Your other
jobs are invisible to it.

- Claude's script is never submitted directly. The gateway writes a wrapper job.
  Resources come only from checked `key=value` options (`#SBATCH` lines are ignored).
  Each job runs on a snapshot of the code (`runs/`), so a later `sync` can't change it.
- Limits (time, GPUs, CPUs, memory, partitions, concurrent jobs) live in
  `~/.config/claude-slurm/config` on the cluster, out of Claude's reach.
- **Set `APPTAINER_IMAGE`.** Without it, the job code runs with your account's full
  rights on the compute node (home directory, network, even further `sbatch`).
  With it, the job only sees the project and the depot.

## Setup

Paths are for the Quadlet setup with instance name `agent`; for Compose, put the same
files next to `deploy/compose/compose.yaml` (`slurm-ssh/`, `slurm.env`).

1. Key + pinned host key (as the sandbox user):
   ```bash
   d=~/.config/agent-sandbox/agent/slurm-ssh; mkdir -p "$d"
   ssh-keygen -t ed25519 -N "" -C agent-sandbox -f "$d/id_ed25519"
   ssh-keyscan -t ed25519 login.cluster.example.org > "$d/known_hosts"
   ```
2. On the cluster login node: copy `server/` there and run
   `./install-slurm.sh "<contents of id_ed25519.pub>"`, then add the printed line to
   `~/.ssh/authorized_keys`.
3. Enable the add-on: `setup.sh … --addon slurm` or, for an existing instance, `setup.sh add-addon <name> slurm` (Quadlet) or
   `-f ../../addons/slurm/compose.yaml` (Compose). Fill in `slurm.env` (`SLURM_HOST`,
   `SLURM_USER`) and restart. The gateway allowlists `SLURM_HOST` by itself (set
   `SLURM_PRIVATE_IP` too if the login node has a private address).

## Use (inside the sandbox)

```bash
cd /workspace/MyProject.jl
slurm instantiate
slurm run scripts/gpu-test.sh time=30 gpus=1 cpus=8 mem=16
slurm run scripts/gpu-test.sh time=30 gpus=1 gputype=a100   # specific GPU model (GPU_TYPES in config)
slurm status ; slurm log <jobid>
slurm fetch <jobid>                  # *.jld2 from the job's run folder -> data/<jobid>/
```

`example-project-CLAUDE.md` is a project `CLAUDE.md` for a "run simulations and check
results" workspace that decides between local runs and the cluster.
