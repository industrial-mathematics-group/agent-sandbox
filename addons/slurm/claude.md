## HPC cluster (`slurm`)

You can submit jobs to an HPC cluster through a restricted gateway (no shell there).
Run these inside the project folder:

```bash
slurm info                          # current limits: check before submitting
slurm instantiate                   # install Julia deps on the cluster (after Project/Manifest changes)
slurm run hpc/job.sh time=60 gpus=1 cpus=8 mem=16 -- <args>   # sync code + submit
slurm status                        # your jobs
slurm log <jobid> 200               # last 200 lines of a job's output
slurm fetch <jobid>                 # copy the job's *.jld2 files to data/<jobid>/
slurm cancel <jobid>
```

Resources are set only through `time=` (minutes), `gpus=`, `gputype=`, `cpus=`, `mem=`
(GB), `partition=`; `#SBATCH` lines are ignored. Jobs run offline: install everything with
`slurm instantiate` first. Respect the limits from `slurm info`, and wait at least a minute
between status checks. If a command fails with a missing configuration or SSH error,
report it instead of trying to fix it.
