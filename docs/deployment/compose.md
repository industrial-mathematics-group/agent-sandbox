# Docker / Podman Compose

`deploy/compose` holds a Compose setup for one sandbox per Compose project. The first run
is covered in the [quick start](../getting-started/compose.md).

## Files

| File | Read by | Contents |
|---|---|---|
| `.env` | Compose | Name, registry, flavor, workspace, ports, limits, `COMPOSE_FILE` ([reference](../reference/compose-env.md)) |
| `gateway.env` | gateway | Mode, profiles, Tailscale ([reference](../reference/gateway-env.md)) |
| `sandbox.env` | agent | Agent environment, **visible to the agent** ([reference](../reference/sandbox-env.md)) |
| `extra.list` | gateway | Your own allowed hosts, one per line |
| `<addon>.env` | gateway (+ agent for most add-ons) | Add-on settings, see [Add-ons](../addons/index.md) |

All of these are git-ignored.

## Overlays

Add files to `COMPOSE_FILE` in `.env` (`:`-separated, paths relative to `deploy/compose`).
Files given with `-f` on the command line replace `COMPOSE_FILE` instead of adding to it.

| File | Adds |
|---|---|
| `../../addons/claude-code/compose.yaml` | Claude Code (CLI + `~/.claude`), in the default `COMPOSE_FILE` |
| `../../addons/codex/compose.yaml` | OpenAI Codex (CLI + `~/.codex`) |
| `compose.podman.yaml` | Rootless Podman: maps your user to `agent` (uid 1000) |
| `compose.tailscale.yaml` | Egress only via a [Tailscale exit node](tailscale.md) |
| `../../addons/gpu-local/compose.gpu-amd.yaml` | Local AMD GPU (`FLAVOR=full-rocm`) |
| `../../addons/gpu-local/compose.gpu-nvidia.yaml` | Local NVIDIA GPU (CDI) |
| `../../addons/gpu-remote/compose.yaml` | Remote GPU server gateway |
| `../../addons/slurm/compose.yaml` | Slurm cluster gateway |
| `../../addons/git-remote/compose.yaml` | Push/pull/API for one Git hosting account |
| `../../addons/github-app/compose.yaml` | GitHub as a GitHub App |
| `../../addons/notify/compose.yaml` | Push notifications |

Example: Claude Code and Codex on rootless Podman, with GitHub access:

```ini
COMPOSE_FILE=compose.yaml:compose.podman.yaml:../../addons/claude-code/compose.yaml:../../addons/codex/compose.yaml:../../addons/github-app/compose.yaml
```

## Several projects

One Compose project is one sandbox. For several projects, keep one env file per project
with its own `SANDBOX_NAME` and `WORKSPACE`:

```bash
docker compose --env-file web.env up -d
docker compose --env-file web.env exec -u agent agent claude
```

Named volumes (`agent-sandbox-history`, `-cache`, `-npm`, `-uv-python`, `-julia-depot`,
`-octave`, and the add-ons' volumes) have fixed names and are shared by all sandboxes on
the machine.

## Ports

Dev servers inside the agent listen on the gateway's network namespace. Publish a port on
the host's loopback with `PORT_1` and open it in the gateway with `PORTS` (list the same
ports in both). With `compose.tailscale.yaml`, ports are opened on the tailnet instead.

## Logs

```bash
docker compose logs gateway         # allowlist, refused hosts
docker compose logs agent           # add-on hooks, "Sandbox ready"
```

## Ownership

Env files the agent reads (`claude-code.env`, `git-remote.env`, ...) and folders it
writes (`codex/`) must be accessible to uid 1000 inside. With `compose.podman.yaml` that
is your own user; otherwise `chown -R 1000`.
