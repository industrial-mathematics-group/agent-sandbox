# Compose .env

`deploy/compose/.env`, read by Compose itself. Copy it from `.env.example`, or keep one per
project and pass it with `--env-file`.

| Key | Default | |
|---|---|---|
| `SANDBOX_NAME` | `agent` | Compose project name; one per sandbox. |
| `REGISTRY` | `ghcr.io/OWNER` | Image registry; `localhost` for images built with `./build.sh`. |
| `FLAVOR` | `full-utils` | Image flavor, see [Images](../concepts/images.md). |
| `GATEWAY_TAG` | `latest` | Gateway image tag (`compose.tailscale.yaml` uses `tailscale`). |
| `COMPOSE_FILE` | `compose.yaml:../../addons/claude-code/compose.yaml` | Compose files to use, `:`-separated, see [Overlays](../deployment/compose.md#overlays). |
| `WORKSPACE` | `./workspace` | Host folder mounted as `/workspace`. |
| `PORT_1` | `3000` | Dev-server port published on `127.0.0.1` of the host. |
| `PORTS` | `3000` | Ports opened in the gateway firewall (`GATEWAY_INBOUND_PORTS`); list the published ports here. |
| `MEMORY` | `16g` | Memory limit of the agent container. |
| `CPUS` | `0` (no limit) | CPU limit; at most the host's CPU count (`nproc`). |
| `CLAUDE_CONFIG` | volume `agent-sandbox-claude` | claude-code add-on: `~/.claude`, the shared named volume or a host folder. |
| `CODEX_CONFIG` | `./codex` | codex add-on: `~/.codex`, a host folder or `codex-home` for a named volume. |
