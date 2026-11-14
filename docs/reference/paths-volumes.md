# Paths and volumes

## On the host (Quadlet)

Under the sandbox user's home (`~agent-sandbox`):

| Path | |
|---|---|
| `.config/containers/systemd/` | Units and drop-ins written by `setup.sh` |
| `.config/agent-sandbox/<name>/` | Per-instance config: `gateway.env`, `sandbox.env`, `extra.list`, `<addon>.env`, `setup.conf`, SSH keys of gpu-remote/slurm (`gpu-ssh/`, `slurm-ssh/`), `github-app.pem` |
| `.config/agent-sandbox/addons/<addon>/` | Add-on files mounted into the agent |
| `.config/agent-sandbox/codex/` | `~/.codex` of the codex add-on (shared by instances) |
| `/var/srv/agent-sandbox/<name>` | Default workspace |

With Compose, the config files live in `deploy/compose/`.

## Volumes

All named volumes have fixed names and are shared by every instance on the machine.

| Volume | Mounted at | Contents |
|---|---|---|
| `agent-sandbox-claude` | `/home/agent/.claude` | Claude login, settings, memory (claude-code) |
| `agent-sandbox-claude-cli` | `/opt/claude-code` | Claude Code binaries, root-owned (claude-code) |
| `agent-sandbox-codex-cli` | `/opt/codex` | Codex binaries, root-owned (codex) |
| `agent-sandbox-history` | `/commandhistory` | Shell history |
| `agent-sandbox-cache` | `/home/agent/.cache` | uv, npm, Playwright caches |
| `agent-sandbox-npm` | `/home/agent/.npm` | npm (node, full) |
| `agent-sandbox-uv-python` | `/home/agent/.local/share/uv` | uv-managed Python interpreters |
| `agent-sandbox-julia-depot` | `/home/agent/.julia` | Julia depot (julia, full) |
| `agent-sandbox-octave` | `/home/agent/.local/share/octave` | Octave Forge packages (octave) |
| `<name>-tailscale-state` | `/var/lib/tailscale` (gateway) | Tailscale node state |

Stop the sandbox before removing one to reset it.

## Inside the agent container

| Path | |
|---|---|
| `/workspace` | Your project folder |
| `/etc/agent-sandbox/AGENTS.md` | Environment notes (image layers + add-ons), root-owned |
| `/etc/claude-code/CLAUDE.md` | The same notes as Claude Code's managed memory (claude-code) |
| `/etc/claude-code/managed-settings.json` | Managed Claude Code settings, e.g. notify's hooks |
| `/etc/codex/config.toml` | Codex system config (codex) |
| `/opt/agent-sandbox/addons/<addon>/` | Mounted add-on files |
| `/opt/agent-sandbox/bin` | Add-on commands, on `PATH` |
| `/run/agent-sandbox/addons/<addon>.env` | Add-on settings, read-only |
| `/etc/gitconfig` | Credential helpers of git-remote / github-app, root-owned |

## Inside the gateway

| Path | |
|---|---|
| `/etc/agent-sandbox/extra.list` | Your allowlist |
| `/etc/agent-sandbox/addons/<addon>.env` | Add-on settings, parsed for hosts and private addresses |
| `127.0.0.1:3128` | Filtering proxy |
| `127.0.0.1:3129` | github-app token broker |
