# agent-sandbox

[![AI generation](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-generation.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#g-generation)
[![Human review](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-human-review.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#h-human-review)
[![AI review](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-review.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#a-ai-review)

Sandboxed containers for running Claude Code or OpenAI Codex (and similar coding agents)
with `--dangerously-skip-permissions` / `--yolo`, without handing them your machine or your
network.

**Documentation: https://industrial-mathematics-group.github.io/agent-sandbox/**

- **Small images per language:** `minimal`, `node`, `julia`, `octave` or `full`, all with
  Python (uv). Each comes headless or as `-utils` with a virtual display and headless
  Chromium.
- **Network through a gateway:** the agent container has no network of its own. It
  shares the namespace of a gateway sidecar that runs the firewall and a filtering
  proxy, so the agent can't change the rules. Only allowlisted hosts get through; LAN,
  cloud metadata and IPv6 are blocked. Optionally all traffic leaves only through a
  Tailscale exit node.
- **The coding agent is an add-on:** Claude Code and Codex are installed at container
  start, either or both. More add-ons for GitHub (as a GitHub App) or another Git host,
  push notifications, local GPUs, a remote GPU server and Slurm clusters.
- **Runs on** rootless Podman with Quadlet (systemd user services, recommended on Linux)
  or Docker / Podman Compose.

```
┌─ network namespace of the gateway ──────────────────────────────────────────┐
│  agent container (no network caps, joins this namespace)                    │
│        │ HTTPS_PROXY=127.0.0.1:3128                                         │
│        ▼                                                                    │
│  proxy (tinyproxy): allowlist by hostname ──▶ firewall: only the proxy may  │
│                                               connect out, public IPs only  │
│                                               (or only via tailscale0)      │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Quick start: Podman Quadlet (Linux, recommended)

Needs Podman >= 5.0. The containers run as systemd user services under a dedicated user.

```bash
sudo useradd -m agent-sandbox                     # once
cd deploy/quadlet
./setup.sh --registry ghcr.io/OWNER --flavor node-utils --name web \
           --workspace /var/srv/agent-sandbox/web --port 5173
# or let it ask for image, add-ons, limits and network:  ./setup.sh -i
```

Then, as the sandbox user (`sudo machinectl shell agent-sandbox@`):

```bash
systemctl --user daemon-reload
systemctl --user start web-gateway web
systemctl --user enable --now podman-auto-update.timer
podman exec -it -u agent web claude               # first time: log in
```

Details: [Quick start with Quadlet](https://industrial-mathematics-group.github.io/agent-sandbox/getting-started/quadlet/).

## Quick start: Docker / Podman Compose

```bash
cd deploy/compose
cp .env.example .env                      # REGISTRY, FLAVOR, WORKSPACE, ports
cp gateway.env.example gateway.env        # mode, allowlist profiles
cp sandbox.env.example sandbox.env        # visible to the agent: no secrets
cp ../../addons/claude-code/claude-code.env.example claude-code.env
touch extra.list                          # your own allowed hosts
docker compose up -d
docker compose exec -u agent agent claude # first time: log in
```

Details: [Quick start with Compose](https://industrial-mathematics-group.github.io/agent-sandbox/getting-started/compose/).

## Documentation

| | |
|---|---|
| [Getting started](https://industrial-mathematics-group.github.io/agent-sandbox/getting-started/) | Choosing a deployment, an image and a coding agent |
| [Concepts](https://industrial-mathematics-group.github.io/agent-sandbox/concepts/) | Images and layers, the gateway, add-ons, what's isolated |
| [Deployment](https://industrial-mathematics-group.github.io/agent-sandbox/deployment/) | Quadlet, Compose, Tailscale exit node, updates |
| [Add-ons](https://industrial-mathematics-group.github.io/agent-sandbox/addons/) | claude-code, codex, github-app, git-remote, notify, gpu-local, gpu-remote, slurm |
| [Reference](https://industrial-mathematics-group.github.io/agent-sandbox/reference/) | `setup.sh`, `build.sh`, env files, allowlists, paths and volumes |
| [Troubleshooting](https://industrial-mathematics-group.github.io/agent-sandbox/guides/troubleshooting/) | Common errors and their fixes |

The sources are in [`docs/`](docs/); `zensical serve` previews them locally.

The design is inspired by Anthropic's reference devcontainer (no files copied). Not an
Anthropic or OpenAI product. Neither Claude Code nor Codex is part of the images: the
add-ons download them when a container starts.

## License

The files in this repository are MIT licensed ([LICENSE](LICENSE)). The images contain
third-party software under its own licenses, and Claude Code and Codex are downloaded at
runtime under their vendors' terms; see [NOTICE](NOTICE).
