#!/bin/bash
# Installs the Claude Slurm gateway for the current user on the cluster. No root needed.
#
#   ./install-slurm.sh "ssh-ed25519 AAAA... claude-sandbox"
#
# - gateway: ~/.local/bin/claude-slurm-gateway
# - config:  ~/.config/claude-slurm/config  (limits, partitions, account, Apptainer image)
# - prints the authorized_keys line to add (does NOT edit the file for you)
set -euo pipefail

PUBKEY=${1:?usage: $0 \"<sandbox public key>\"}
HERE=$(cd "$(dirname "$0")" && pwd)
CONF_DIR=$HOME/.config/claude-slurm

[[ "$PUBKEY" =~ ^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa)\ [A-Za-z0-9+/=]+ ]] \
    || { echo "That doesn't look like a public key: $PUBKEY" >&2; exit 1; }
command -v sbatch >/dev/null || { echo "sbatch not found: is this a Slurm login node?" >&2; exit 1; }

mkdir -p "$HOME/.local/bin" "$CONF_DIR"
install -m 0755 "$HERE/claude-slurm-gateway" "$HOME/.local/bin/claude-slurm-gateway"

if [ ! -f "$CONF_DIR/config" ]; then
    parts=$(sinfo -h -o %P 2>/dev/null | tr -d '*' | paste -sd' ' -)
    default=$(sinfo -h -o %P 2>/dev/null | grep '\*' | tr -d '*' | head -1)
    have_apptainer=$(command -v apptainer || command -v singularity || true)
    cat > "$CONF_DIR/config" <<EOF
# Claude Slurm gateway settings (sourced by ~/.local/bin/claude-slurm-gateway)
# Everything here is trusted configuration; Claude can't change it.

BASE=\$HOME/claude-jobs            # projects/, runs/, depot/, logs/ (use \$WORK/\$SCRATCH if your cluster has one)
ACCOUNT=                          # --account, if required
# Partitions Claude may use (cluster has: $parts)
PARTITIONS="${default}"            # CPU jobs
DEFAULT_PARTITION=${default}
# GPU jobs. "auto" = no --partition, the cluster routes the job (needed when
# job_submit rules reject --partition=gpu). Add preemptible queues like gpuidle if wanted.
GPU_PARTITIONS="auto"
DEFAULT_GPU_PARTITION=auto
JOB_TMP_BASE=                     # private job /tmp under this dir; empty = node \$TMPDIR or /tmp

MAX_TIME_MIN=60
MAX_GPUS=1
GPU_ARG=--gres=gpu:%d             # or --gpus=%d, depending on the cluster
# GPU models Claude may request with gputype= (empty = option disabled).
# The cluster has: $(sinfo -h -o %G 2>/dev/null | tr ',' '\n' | sed -n 's/^gpu:\([^:(]*\):.*/\1/p' | sort -u | paste -sd' ' -)
GPU_TYPES=""
GPU_TYPE_ARG=--gres=gpu:%s:%d     # %s = type, %d = count
MAX_CPUS=16
MAX_MEM_GB=64
MAX_ACTIVE=2                      # pending + running at the same time

# Run first in every job / instantiate (login shell), e.g. modules:
JOB_SETUP="module load julia"

# Strongly recommended: run jobs inside Apptainer, so they only see the project
# and the depot (no home, no Slurm commands -> no follow-up jobs).
# Build once:  apptainer build \$HOME/claude-jobs/julia.sif docker://julia:1.12
# ($( [ -n "$have_apptainer" ] && echo "found: $have_apptainer" || echo "apptainer not found on this node"))
APPTAINER_IMAGE=
APPTAINER_FLAGS=--nv              # NVIDIA GPUs; --rocm for AMD

JULIA=julia                       # plain mode only
PKG_SERVER=https://pkg.julialang.org
TIMEOUT_SETUP=1800
RUNS_KEEP_DAYS=14                 # job snapshots incl. results/ are deleted after this

# "slurm fetch <jobid>": copies matching files from the job's run folder back
FETCH_PATTERN='*.jld2'
MAX_FETCH_BYTES=\$((5 * 1024**3))  # per fetch
EOF
    echo "Wrote $CONF_DIR/config. Review partitions, limits and JOB_SETUP there."
else
    echo "Keeping existing $CONF_DIR/config"
fi

echo
echo "Add this ONE line to ~/.ssh/authorized_keys on the cluster:"
echo
echo "restrict,command=\"$HOME/.local/bin/claude-slurm-gateway\" $PUBKEY"
echo
echo "The key can then only run the gateway: no shell, no forwarding, no scp/sftp."
