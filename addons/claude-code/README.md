# claude-code: Claude Code in the sandbox

Installs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) when the container
starts and mounts its config folder, `~/.claude`. Without this add-on (or
[codex](../codex/README.md)) the sandbox has no coding agent, and the gateway doesn't let
it reach Anthropic at all. `setup.sh` adds it unless you pick only `--addon codex`.

- **The CLI** is not in the image. At start, the add-on's hook runs
  `libexec/install-claude-code` as root (before the entrypoint drops to `agent`) and
  installs into the named volume `agent-sandbox-claude-cli` at `/opt/claude-code`:
  root-owned, so the agent can run but not replace it, and shared, so each version is
  downloaded once per machine. `claude` is linked into `/opt/agent-sandbox/bin` (on
  `PATH`, also for `podman exec`). Claude Code's own auto-updater is off.
- **`CLAUDE_CODE_VERSION`** in `claude-code.env`: `stable` (default) or `latest` are
  checked at most once a day (`CLAUDE_CODE_CHECK_MINUTES`), an exact version such as
  `2.1.30` pins it. If a download fails, the version already in the volume is kept. A
  `CLAUDE_CODE_VERSION` in `sandbox.env` (older setups) still works when `claude-code.env`
  leaves it empty.
- **`~/.claude`** (login, settings, memory): the named volume `agent-sandbox-claude`,
  shared by all instances, so you log in once. `setup.sh --claude-config /path` mounts a
  host folder instead (Compose: `CLAUDE_CONFIG=/path` in `.env`).
- **Managed CLAUDE.md:** the hook copies the sandbox's environment notes
  (`/etc/agent-sandbox/AGENTS.md`: image layers + every add-on's `claude.md`) to
  `/etc/claude-code/CLAUDE.md`, which Claude Code loads in every session. Root-owned and
  outside `~/.claude`, so it always matches the image and the active add-ons.
- **Firewall:** the gateway reads `claude-code.env` and allowlists its `*_HOST` values:
  `api.anthropic.com`, `claude.ai`, `console.anthropic.com`, `platform.claude.com` and
  `downloads.claude.ai`.

## Setup

Quadlet: part of every `setup.sh` run (or `--addon claude-code` next to `--addon codex`).
Log in once: `podman exec -it -u agent <name> claude`.

Compose: `cp ../../addons/claude-code/claude-code.env.example claude-code.env` in
`deploy/compose`, then add `-f ../../addons/claude-code/compose.yaml` (the default
`COMPOSE_FILE` in `.env.example` already does). The file must be readable by uid 1000 in
the agent.

## Instances set up before Claude Code was an add-on

Their `<name>.container` still mounts `~/.claude` and `/opt/claude-code` itself, and
after the image update `claude` is missing (the agent log says so). Rerun `setup.sh` with
the options you used before; it rewrites the units with the add-on and keeps your env
files. `setup.sh add-addon <name> claude-code` does that without retyping them (it reads
the options back from the units, a host folder for `~/.claude` included). By hand, if
`~/.claude` was a host folder, pass it as `--claude-config`, e.g.

```bash
./setup.sh --name claude-julia --flavor julia-chromium --net tailscale --workspace /srv/claude/projects \
           --memory 32g --cpus 16 --sandbox-user claude-sandbox --registry ghcr.io/OWNER \
           --claude-config /srv/claude/config
```

Rerunning `setup.sh` undoes hand edits to the unit files. To keep them instead: remove the
`Volume=…:/home/agent/.claude` and `Volume=agent-sandbox-claude-cli:/opt/claude-code`
lines from `<name>.container` (the drop-in brings both; duplicates fail), then install the
add-on by hand like [git-remote](../git-remote/README.md#setup), with `claude-code`,
`quadlet/20-claude-code.conf`, the `libexec/` folder and `@CLAUDE_CONFIG@` (your
`~/.claude` source) / `@CLAUDE_CONFIG_OPTS@` (`:z` for a host folder, empty for a volume).

Compose: add the overlay and `claude-code.env` as above; `compose.yaml` no longer mounts
`~/.claude` itself. The volumes keep their names (`agent-sandbox-claude`,
`agent-sandbox-claude-cli`), so the login and the installed CLI are still there.

Update the units first, then the image: an older image still installs Claude Code itself,
into the same volume, and the add-on's hook only finds it already there. The other way
round, the instance has no `claude` (and no Anthropic hosts in the gateway) until the units
are updated. With `podman-auto-update.timer` on, that can happen at the next pull.
