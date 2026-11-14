# Quick start: Docker / Podman Compose

One Compose project is one sandbox. Everything happens in `deploy/compose` of a clone of
the repository.

## 1. Copy the example config

```bash
cd deploy/compose
cp .env.example .env                      # REGISTRY, FLAVOR, WORKSPACE, ports
cp gateway.env.example gateway.env        # mode, allowlist profiles
cp sandbox.env.example sandbox.env        # visible to the agent: no secrets
cp ../../addons/claude-code/claude-code.env.example claude-code.env   # Claude Code version
touch extra.list                          # your own allowed hosts
```

Set at least `REGISTRY`, `FLAVOR` and `WORKSPACE` in `.env`
([reference](../reference/compose-env.md)).

## 2. Start

```bash
docker compose up -d
docker compose logs -f agent              # wait for "Sandbox ready"
docker compose exec -u agent agent claude # first time: log in
```

`COMPOSE_FILE` in `.env` lists the Compose files to use, by default `compose.yaml` and the
claude-code add-on, so plain `docker compose up -d` works.

!!! tip "Rootless Podman"
    Add `compose.podman.yaml` to `COMPOSE_FILE`. It maps your user to `agent` inside, so
    files in the workspace keep your ownership.

!!! warning "Rootful Docker"
    With rootful Docker, root inside a container is close to root on the host. Prefer
    rootless Docker or Podman, or the [Quadlet setup](quadlet.md).

## Codex instead of (or next to) Claude Code

Add `../../addons/codex/compose.yaml` to `COMPOSE_FILE` (or replace the claude-code file
with it), copy `codex.env.example`, and see [codex](../addons/codex.md) for the login.

## Day to day

```bash
docker compose exec -u agent agent claude --dangerously-skip-permissions
```

## Next steps

- Let the agent reach the hosts your project needs: [Network allowlist](../guides/network-allowlist.md).
- Several projects, overlays and Tailscale: [Deployment with Compose](../deployment/compose.md).
- More add-ons: [Add-ons](../addons/index.md).
