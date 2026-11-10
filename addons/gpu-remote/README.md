# gpu-remote: tests on a remote GPU server

Lets the sandbox run Julia tests on a remote GPU machine through a narrow channel. Its
SSH key is pinned server-side to `claude-gpu-gateway` (forced command, no shell, no
forwarding). The gateway runs every Julia process in a bubblewrap sandbox that sees
`/usr` read-only, a copy of the project, a separate Julia depot and the GPUs. It can't
see your home directory or `~/.ssh` there, and has no network except during
`instantiate`. No root or containers are needed on the server, only unprivileged user
namespaces (`unshare -rn true` must work).

```
sandbox ── gpu sync/test ──▶ gateway proxy ──▶ ssh (key limited to gateway) ──▶ bwrap: /work + /depot + GPUs, no net
```

Currently Julia only (`Pkg.test`, `Pkg.instantiate`, `julia script.jl`).

## Setup

Paths below are for the Quadlet setup with instance name `agent`
(`~/.config/agent-sandbox/agent/`); for Compose, put the same files next to
`deploy/compose/compose.yaml` (`gpu-ssh/`, `gpu-remote.env`).

1. Create a key and pin the server's host key (as the sandbox user):
   ```bash
   d=~/.config/agent-sandbox/agent/gpu-ssh; mkdir -p "$d"
   ssh-keygen -t ed25519 -N "" -C agent-sandbox -f "$d/id_ed25519"
   ssh-keyscan -t ed25519 gpu-server.example.org > "$d/known_hosts"
   ssh-keygen -lf "$d/known_hosts"     # compare with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the server
   ```
2. Copy `server/` to the GPU server and install (no sudo):
   ```bash
   scp -r server gpu-server.example.org:agent-gpu-install
   ssh gpu-server.example.org 'cd agent-gpu-install && ./install.sh "$(cat)" [EGRESS_IP]' < "$d/id_ed25519.pub"
   ```
   It unpacks bubblewrap from the Debian package into `~/.local/lib`, installs the
   gateway, runs a self-test (GPU visible, home hidden, no network) and prints a line
   for `~/.ssh/authorized_keys`. Add that line yourself. With `EGRESS_IP` (your VPN exit
   node's public IP, for example), the key only works from there (`from="…"`).
3. Enable the add-on: `setup.sh … --addon gpu-remote` (Quadlet) or add
   `-f ../../addons/gpu-remote/compose.yaml` (Compose). Fill in `gpu-remote.env`
   (`GPU_HOST`, `GPU_USER`, `GPU_PROJECT`), then restart. The gateway allowlists
   `GPU_HOST` by itself; if the server is on your LAN or tailnet, also set
   `GPU_PRIVATE_IP` to its address.

SSH goes through the gateway proxy (CONNECT to port 22), so the host must be on the
allowlist like any other; the add-on's gateway mount takes care of that.

## Use (inside the sandbox)

```bash
gpu sync            # upload the project (tracked + new files, respects .gitignore)
gpu instantiate     # first time / after dependency changes (with network)
gpu test            # Pkg.test() on the least busy GPU, no network
gpu check           # sync + test, the usual loop
gpu run bench/gpu.jl 1024
gpu --gpu 2 test    # pick a GPU
gpu status | gpu kill
```

The add-on's `claude.md` is merged into the managed CLAUDE.md, so Claude knows about
these commands without extra project instructions.

## Limits and notes

One run at a time, 1 h timeout and a memory cap (if `systemd-run --user` works). All
adjustable in `~/.config/claude-gpu/config` on the server. Project copies and the depot
live in `/tmp/$USER-claude-gpu` (local disk, mode 0700) and may vanish on reboot. Run
`gpu sync && gpu instantiate` again then. `instantiate` is the one step with network
access, and it runs package build scripts. Claude can edit `Project.toml`/`Manifest.toml`
(including git URLs of unregistered packages), so check dependency changes in your
review before running it. Every request is logged to `/tmp/$USER-claude-gpu/gateway.log`
on the server.
