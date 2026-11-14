# Add-ons

Specific add-ons are switched on per instance. Each mounts its commands and notes into the
agent container and allowlists its own hosts in the gateway; see
[how add-ons work](../concepts/addons.md).

## Coding agents

At least one is needed; without one the sandbox has no coding agent and can't reach any
model provider.

| Add-on | What | Quadlet | Compose |
|---|---|---|---|
| [claude-code](claude-code.md) | Claude Code: CLI installed at start, `~/.claude` mounted, Anthropic hosts allowed | default, or `--addon claude-code` | `addons/claude-code/compose.yaml` (default) |
| [codex](codex.md) | OpenAI Codex: CLI installed at start, `~/.codex` mounted, OpenAI hosts allowed, Codex's own sandbox off | `--addon codex` | `addons/codex/compose.yaml` |

## Git hosting

No credentials are in the container by default: commit inside and push from the host, or
enable one of these.

| Add-on | What | Quadlet | Compose |
|---|---|---|---|
| [github-app](github-app.md) | GitHub as your organization's GitHub App: the private key stays in the gateway, which hands the agent 1-hour installation tokens for git and `gh`. Recommended for GitHub. | `--addon github-app` | `addons/github-app/compose.yaml` |
| [git-remote](git-remote.md) | One GitHub / Forgejo / GitLab account with a personal access token: git push/pull over HTTPS and API calls | `--addon git-remote` | `addons/git-remote/compose.yaml` |

## Notifications

| Add-on | What | Quadlet | Compose |
|---|---|---|---|
| [notify](notify.md) | Push notifications (ntfy, Gotify, Discord, Slack, webhook) when Claude needs you, plus a `notify` command | `--addon notify` | `addons/notify/compose.yaml` |

## Compute

| Add-on | What | Quadlet | Compose |
|---|---|---|---|
| [gpu-local](gpu-local.md) | AMD (ROCm) or NVIDIA (CDI) GPU of this machine | `--gpu amd\|nvidia` | `addons/gpu-local/compose.gpu-*.yaml` |
| [gpu-remote](gpu-remote.md) | Julia tests on a remote GPU server, via a forced-command SSH gateway + bubblewrap | `--addon gpu-remote` | `addons/gpu-remote/compose.yaml` |
| [slurm](slurm.md) | Jobs on an HPC cluster with capped resources, via a forced-command SSH gateway | `--addon slurm` | `addons/slurm/compose.yaml` |

On an existing Quadlet instance: `./setup.sh add-addon <name> <addon>` /
`remove-addon`. In Compose, add the file to `COMPOSE_FILE` in `.env` or remove it.
