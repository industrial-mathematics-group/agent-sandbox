# Isolation and limits

## What's isolated

| | |
|---|---|
| **Files** | Only the workspace (as `/workspace`). Your `$HOME`, SSH keys and browser profiles are not visible; with Quadlet the containers run under a separate Linux user. |
| **Network** | The rules live in the [gateway](gateway.md); the agent has no network capabilities. Secrets for the gateway (Tailscale auth key, GitHub App key) are only in the gateway. |
| **Privileges** | No sudo, `no-new-privileges`, all capabilities dropped (the entrypoint keeps SETUID/SETGID only to switch to `agent`). |
| **Resources** | Memory, CPU and process limits per container, so a runaway test can't freeze the machine. |
| **Agent CLIs** | Installed at container start by the [claude-code](../addons/claude-code.md) and [codex](../addons/codex.md) add-ons, as root before the switch to `agent`, into root-owned volumes. The agent can run but not replace them; their own updaters are off. |
| **Persistence** | Named volumes for logins, caches and history, see [Paths and volumes](../reference/paths-volumes.md). |

## Known limits

- **Containers share the host kernel.** For a hard boundary use a VM.
- **`strict` mode's direct access is IP-based.** CDN IPs are shared with other sites, so
  it is coarse, and IPs that rotate after startup need a gateway restart.
- **An allowed host is allowed entirely.** Anything the agent can upload to it (a GitHub
  gist, an npm package) can leave. Keep the allowlist short.
- **Opened inbound ports** are reachable by every device your ACLs (or localhost users)
  allow. Dev servers, Bonito and ocp_vscode have no authentication.
- **The agent can read its own credentials.** Anything in its environment
  (`sandbox.env`, e.g. `ANTHROPIC_API_KEY`) is readable by the agent, and so are its own
  logins (`~/.claude`, `~/.codex/auth.json`) and the tokens of the git-remote and notify
  add-ons. The github-app add-on keeps its key in the gateway, but the agent can get (and
  use) its one-hour tokens while it runs.
- **Rootful Docker:** root inside a container is close to root on the host. Prefer
  rootless Docker or Podman, or Quadlet under a dedicated user.

Branch protection on your Git server is the real guard for anything the agent pushes:
let it push branches and open pull requests, and keep merging to the default branch for
people.
