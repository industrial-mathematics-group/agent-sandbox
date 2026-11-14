# agent-sandbox

Sandboxed containers for running Claude Code or OpenAI Codex (and similar coding agents)
with `--dangerously-skip-permissions` / `--yolo`, without handing them your machine or your
network.

<div class="grid cards" markdown>

-   **Get started**

    ---

    One sandbox running in a few minutes, with Podman Quadlet or Docker Compose.

    [:octicons-arrow-right-24: Getting started](getting-started/index.md)

-   **How it fits together**

    ---

    Images, the network gateway, add-ons, and what the sandbox does and doesn't isolate.

    [:octicons-arrow-right-24: Concepts](concepts/index.md)

-   **Add-ons**

    ---

    The coding agent itself, GitHub access, notifications, GPUs and HPC clusters.

    [:octicons-arrow-right-24: Add-ons](addons/index.md)

-   **Reference**

    ---

    Every `setup.sh` option, env file, allowlist and volume.

    [:octicons-arrow-right-24: Reference](reference/index.md)

</div>

## What you get

- **Small images per language:** `minimal`, `node`, `julia`, `octave`, or `full`, all with
  Python (uv). Each comes headless or as `-utils` with a virtual display and headless
  Chromium. See [Images](concepts/images.md).
- **Network through a gateway:** the agent container has no network of its own. It
  shares the namespace of a gateway sidecar that runs the firewall and a filtering
  proxy, so the agent can't change the rules. Only allowlisted hosts get through; LAN,
  cloud metadata and IPv6 are blocked. Optionally all traffic leaves only through a
  Tailscale exit node. See [Gateway and network](concepts/gateway.md).
- **The coding agent is an add-on:** [claude-code](addons/claude-code.md) and
  [codex](addons/codex.md) install their CLI at container start and mount its config
  folder (`~/.claude`, `~/.codex`). Use either or both; the gateway only lets the sandbox
  reach the providers of the agents it runs.
- **More add-ons** for local GPUs, for running jobs on a remote GPU server or a Slurm
  cluster through restricted SSH gateways, for GitHub (as a GitHub App) or another Git
  hosting account, and for push notifications. Enabling one allowlists its hosts. See
  [Add-ons](addons/index.md).
- **Runs on** rootless Podman with Quadlet (systemd user services, recommended on Linux)
  or Docker / Podman Compose. See [Deployment](deployment/index.md).

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

The design is inspired by Anthropic's reference devcontainer (no files copied). Not an
Anthropic or OpenAI product. Neither Claude Code nor Codex is part of the images: the
add-ons download them when a container starts.

## License

The files in the repository are MIT licensed
([LICENSE](https://github.com/industrial-mathematics-group/agent-sandbox/blob/main/LICENSE)).
The images contain third-party software under its own licenses, and Claude Code and Codex
are downloaded at runtime under their vendors' terms; see
[NOTICE](https://github.com/industrial-mathematics-group/agent-sandbox/blob/main/NOTICE).
