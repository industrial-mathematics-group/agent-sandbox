# agent-sandbox

[![AI generation](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-generation.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#g-generation)
[![Human review](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-human-review.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#h-human-review)
[![AI review](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-review.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#a-ai-review)

Sandboxed containers for running Claude Code or OpenAI Codex (and similar coding agents)
with `--dangerously-skip-permissions` / `--yolo`, without handing them your machine or your
network.

- **Small images per language:** node, python, julia, or all of them, each optionally
  with a virtual display, headless Chromium or ROCm.
- **Network through a gateway:** the agent container has no network of its own. It
  shares the namespace of a gateway sidecar that runs the firewall and a filtering
  proxy, so the agent can't change the rules. Only allowlisted hosts get through; LAN,
  cloud metadata and IPv6 are blocked. Optionally all traffic leaves only through a
  Tailscale exit node.
- **The coding agent is an add-on:** [claude-code](addons/claude-code/README.md) and
  [codex](addons/codex/README.md) install their CLI at container start and mount its
  config folder (`~/.claude`, `~/.codex`). Either, both, and the gateway only lets the
  sandbox reach the providers of the agents it runs.
- **More add-ons** for local GPUs, for running jobs on a remote GPU server or a Slurm
  cluster through restricted SSH gateways, for a Git hosting account (push, pull, API
  with a token) and for push notifications. Enabling one allowlists its hosts.
- **Runs on** rootless Podman with Quadlet (systemd user services, recommended on
  Linux) or Docker / Podman Compose.

The design is inspired by Anthropic's reference devcontainer (no files copied). Not an
Anthropic or OpenAI product. Neither Claude Code nor Codex is part of the images: the
add-ons download them when a container starts (see [What's isolated](#whats-isolated)).

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

## Images

All images: `ghcr.io/OWNER/agent-sandbox:<flavor>` (also `<flavor>-YYYYMMDD`),
`linux/amd64` and `linux/arm64`. The packages can stay private to your organization, see
[Private registry](#private-registry).

| Flavor | Chain | For |
|---|---|---|
| `minimal` | base | Plain repo work, scripting |
| `node` | base + node | Websites, JS/TS tooling |
| `node-chromium` | base + node + chromium | Web dev with Playwright / browser checks |
| `python` | base + python | Python projects |
| `python-gui` | base + python + xvfb + chromium | CAD (build123d), plotting, browser checks |
| `julia` | base + julia | Julia packages |
| `julia-gui` | base + julia + xvfb + chromium | GLMakie, WGLMakie tests |
| `octave` | base + octave | MATLAB-style code with GNU Octave (+ signal, statistics, control, optim, io, image, symbolic) |
| `octave-gui` | base + octave + xvfb | Octave with plots rendered through the virtual display |
| `full` | base + node + python + julia + xvfb + chromium | Everything |
| `full-rocm` | full + rocm (amd64) | AMDGPU.jl, PyTorch-ROCm |

Gateway: `ghcr.io/OWNER/agent-sandbox-gateway:latest` (plain) and `:tailscale`.

| Part | Folder | Contents |
|---|---|---|
| base | `images/base` | Debian trixie, git, gh, delta, zsh, build tools, entrypoint |
| language images | `images/node`, `images/python`, `images/julia`, `images/octave` | Node 26 LTS + corepack · uv · Julia (checksum-verified) · GNU Octave |
| general add-ons (image layers) | `layers/xvfb`, `layers/chromium`, `layers/rocm` | Virtual X display + Mesa · headless Chromium · ROCm runtime |
| final step | `images/final` | Proxy settings, environment notes for the agent (last step of every image) |
| gateway | `gateway` | Firewall, proxy, allowlists (`gateway/lists/*.list`) |
| specific add-ons | `addons/claude-code`, `addons/codex`, `addons/gpu-local`, `addons/gpu-remote`, `addons/slurm`, `addons/git-remote`, `addons/github-app`, `addons/notify` | Claude Code · Codex · local GPU drop-ins · remote GPU gateway · Slurm gateway · Git hosting account · GitHub as a GitHub App · notifications |
| deployment | `deploy/quadlet`, `deploy/compose` | Quadlet templates + `setup.sh` · Compose files |

Each layer adds a fragment to the environment notes (`/etc/agent-sandbox/AGENTS.md`), and
so does each mounted add-on, so the agent is told exactly which tools it has. The file is
root-owned; the claude-code add-on hands it to Claude Code as the managed
`/etc/claude-code/CLAUDE.md` (loaded in every session), the codex add-on to Codex as
`developer_instructions` in `/etc/codex/config.toml`.

Build locally instead of pulling: `./build.sh --list`, then e.g. `./build.sh node gateway`
(Podman or Docker, images tagged `localhost/…`; use `--registry localhost` below).

## Quick start: Docker / Podman Compose

```bash
cd deploy/compose
cp .env.example .env                      # REGISTRY, FLAVOR, WORKSPACE, ports
cp gateway.env.example gateway.env        # mode, allowlist profiles
cp sandbox.env.example sandbox.env        # visible to the agent: no secrets
cp ../../addons/claude-code/claude-code.env.example claude-code.env   # Claude Code version
touch extra.list                          # your own allowed hosts
docker compose up -d
docker compose logs -f agent              # wait for "Sandbox ready"
docker compose exec -u agent agent claude # first time: log in
```

`COMPOSE_FILE` in `.env` lists the Compose files, by default `compose.yaml` and the
claude-code add-on. For Codex add `../../addons/codex/compose.yaml` (or use it instead of
claude-code) and see [its README](addons/codex/README.md) for the login. Rootless Podman: add
`compose.podman.yaml` (maps your user to `agent`). Tailscale exit
node: add `compose.tailscale.yaml` and set `TS_*` in `gateway.env`. Files given with `-f`
replace `COMPOSE_FILE` instead of adding to it. One Compose
project is one sandbox; for several projects, keep one env file per project
(`docker compose --env-file web.env up -d`) with its own `SANDBOX_NAME` and `WORKSPACE`.

With rootful Docker, root inside a container is close to root on the host. Prefer
rootless Docker or Podman, or the Quadlet setup below.

## Quick start: Podman Quadlet (Linux, recommended)

Two containers per instance run as systemd user services under a dedicated Linux user,
so a container escape lands in an empty account. Needs Podman >= 5.0.

1. Create the sandbox user once: `sudo useradd -m agent-sandbox`.
2. As your normal user:
   ```bash
   cd deploy/quadlet
   ./setup.sh --registry ghcr.io/OWNER --flavor node-chromium --name web \
              --workspace /var/srv/agent-sandbox/web --port 5173
   ```
   It sets up subuids, linger, the workspace (shared with your user via ACLs,
   SELinux-labelled), and writes the units and config for that combination
   (`--help` lists everything: `--net tailscale`, `--mode`, `--gpu`, `--addon`, limits).
   Claude Code is included unless you choose agents yourself: `--addon codex` for Codex
   only, `--addon claude-code --addon codex` for both.
3. As the sandbox user (`sudo machinectl shell agent-sandbox@`):
   ```bash
   nano ~/.config/agent-sandbox/web/gateway.env
   systemctl --user daemon-reload
   systemctl --user start web-gateway web
   systemctl --user enable --now podman-auto-update.timer
   podman exec -it -u agent web claude      # or codex (log in first: addons/codex/README.md)
   ```

Day to day: `podman exec -it -u agent web claude --dangerously-skip-permissions` (Codex:
`codex --dangerously-bypass-approvals-and-sandbox`). An alias
from your own account saves the user switch:

```bash
alias claude-web='sudo machinectl shell agent-sandbox@ /usr/bin/podman exec -it -u agent web claude --dangerously-skip-permissions'
```

Always pass `-u agent` to `exec`. Run `setup.sh` again with another `--name` for another
project; Claude's login (`~/.claude`), Codex's (`~/.config/agent-sandbox/codex/` of the
sandbox user) and the language caches are shared between instances.

**Restarts:** the agent unit is bound to its gateway (`BindsTo=`/`PartOf=`), so
`systemctl --user restart web-gateway` restarts both. A restarted gateway has a new
network namespace; the agent always follows it and fails closed, never open.

## Network

The gateway loads `base.list` plus the profiles in `GATEWAY_PROFILES`, your `extra.list`
and `GATEWAY_EXTRA_DOMAINS`. Entries are host names; `*.example.com` matches
`example.com` and all its subdomains.

| List | Hosts |
|---|---|
| `base` | GitHub (incl. `*.githubusercontent.com`) |
| add-on `claude-code` | Anthropic API and login, Claude Code downloads (`downloads.claude.ai`) |
| add-on `codex` | OpenAI API, ChatGPT login and backend (`auth.openai.com`, `chatgpt.com`), `registry.npmjs.org` (Codex downloads) |
| `node` | npm, yarn, JSR, nodejs.org, Playwright downloads, Prisma engines, Google Fonts |
| `python` | PyPI, PyTorch wheels |
| `julia` | Pkg servers, Julia storage and binaries |
| `octave` | Octave Forge index and SourceForge downloads (`pkg install -forge`) |

| `GATEWAY_MODE` | What gets out |
|---|---|
| `standard` (default) | Only allowlisted hosts, checked by name in the proxy. No IP lists to go stale, wildcards work. |
| `strict` | `standard`, plus direct connections to the IPv4 addresses the allowlist resolves to at startup (plus networks in `GATEWAY_STRICT_CIDRS`), for tools that ignore proxy settings. IP-based, so coarse. |
| `open` | Any public host through the proxy. LAN, metadata and IPv6 stay blocked. |

Always: the agent can only reach the proxy; the proxy only connects to public IPs on
ports 80, 443 and 22 (SSH goes through it via `ProxyCommand`). In `standard` and `open`
the agent can't use DNS either, which closes the DNS side channel. Inbound is closed
except the ports you publish (`--port`, `PORTS`), which the gateway opens
(`GATEWAY_INBOUND_PORTS`).

**Find out what a project needs:** the proxy logs every request, including refused
ones (`Proxying refused on filtered domain "…"`). Run once in `open` mode and read the
gateway log, then copy the hosts you trust into `extra.list`:

```bash
journalctl --user -u web-gateway | grep -o 'CONNECT [^ ]*' | sort -u    # Quadlet
docker compose logs gateway | grep -o 'CONNECT [^ ]*' | sort -u         # Compose
```

**Tailscale exit node** (`--net tailscale` / `compose.tailscale.yaml`): the gateway also
runs tailscaled, and everything may only leave via `tailscale0`. If the tunnel is down,
nothing gets out. Setup: on the exit node `tailscale set --advertise-exit-node` and
approve it; create a tagged auth key (e.g. `tag:agent-sandbox`) to restrict the sandbox
with ACLs; set `TS_AUTHKEY`, `TS_EXIT_NODE` (its `100.x.y.z` IP) and `TS_HOSTNAME`.
Published ports are then reachable from your tailnet instead of localhost; allow them in
your ACLs and keep everything else towards the sandbox denied.

**Your own private services** (LAN, or tailnet hosts on `100.x`): private ranges are
blocked even for allowlisted names. To reach one, allowlist its name and add its address to
`GATEWAY_PRIVATE_ALLOW` in `gateway.env`, e.g. `GATEWAY_PRIVATE_ALLOW=100.85.46.4` (ports
80/443/22, via `tailscale0` with Tailscale). Prefer single addresses over ranges. LAN hosts
behind a subnet router also need `TS_EXTRA_ARGS=--accept-routes`. Add-ons do both for their
own hosts (`*_PRIVATE_IP` in their env file, see [Add-ons](#add-ons)).

**Corporate proxy:** `GATEWAY_UPSTREAM_PROXY=host:port` chains the gateway's proxy to it.

## What's isolated

| | |
|---|---|
| Files | Only the workspace (as `/workspace`). Your `$HOME`, SSH keys and browser profiles are not visible; with Quadlet the containers run under a separate Linux user. |
| Network | See above. The rules live in the gateway; the agent has no network capabilities. Secrets for the gateway (Tailscale auth key) are only in `gateway.env`. |
| Privileges | No sudo, `no-new-privileges`, all capabilities dropped (the entrypoint keeps SETUID/SETGID only to switch to `agent`). |
| Resources | Memory, CPU and process limits per container, so a runaway test can't freeze the machine. |
| Agent CLIs | Installed at container start by the [claude-code](addons/claude-code/README.md) and [codex](addons/codex/README.md) add-ons (as root, before the switch to `agent`) into the root-owned volumes `agent-sandbox-claude-cli` and `agent-sandbox-codex-cli`, so the agent can run but not replace them; their own updaters are off. Versions: `CLAUDE_CODE_VERSION` in `claude-code.env` (`stable`, `latest`, or exact), `CODEX_VERSION` in `codex.env` (`latest` or exact); channels are checked at most once a day, and a failed download keeps the installed version. |
| Persistence | Named volumes: `agent-sandbox-claude` (Claude login, settings), `-claude-cli`, `-codex-cli` (agent binaries), `-history`, `-cache` (uv, npm, Playwright), `-npm`, `-uv-python`, `-julia-depot`, `-octave` (Forge packages). Codex's home is a host folder by default. |

## Graphics, browsers, dev servers

- **Dev servers** must listen on `0.0.0.0` inside the agent and use a published port
  (`--port 5173` / `PORTS`). Open `http://localhost:5173` (plain) or
  `http://<TS_HOSTNAME>:5173` (Tailscale).
- **GLMakie** (`xvfb` layer): a virtual display (`DISPLAY=:99`) with Mesa software
  OpenGL starts with the container. Save figures to files. `VIRTUAL_DISPLAY=0` turns it
  off, `XVFB_RESOLUTION` changes the size.
- **WGLMakie / Bonito**: publish port 9384, then
  `Bonito.configure_server!(listen_url="0.0.0.0", listen_port=9384, proxy_url="http://<host>:9384")`
  and open `/browser-display`.
- **Headless Chromium** (`chromium` layer): no GPU, so WebGL runs on SwiftShader, and
  rootless containers can't provide Chromium's sandbox. Debian's `chromium` picks up the
  flags from `/etc/chromium.d/container`; pass the same flags to Playwright or Electron:
  `--no-sandbox --use-angle=swiftshader --enable-unsafe-swiftshader`. Without them,
  WebGL canvases render blank.
- **Python CAD**: `uv add build123d ocp_vscode`, viewer with
  `uv run python -m ocp_vscode --host 0.0.0.0 --port 3939` (publish 3939).

## Add-ons

General add-ons are image layers (`layers/`): pick a flavor that has them, or build your
own chain in `build.sh`. Specific add-ons (`addons/`) are switched on per instance:

| Add-on | What | Enable |
|---|---|---|
| [claude-code](addons/claude-code/README.md) | Claude Code: CLI installed at start, `~/.claude` mounted, Anthropic hosts allowed | default / `--addon claude-code` / `addons/claude-code/compose.yaml` |
| [codex](addons/codex/README.md) | OpenAI Codex: CLI installed at start, `~/.codex` mounted, OpenAI hosts allowed, Codex's own sandbox off | `--addon codex` / `addons/codex/compose.yaml` |
| [gpu-local](addons/gpu-local/README.md) | AMD (ROCm) or NVIDIA (CDI) GPU of this machine | `--gpu amd\|nvidia` / `compose.gpu-*.yaml` |
| [gpu-remote](addons/gpu-remote/README.md) | Julia tests on a remote GPU server, via a forced-command SSH gateway + bubblewrap | `--addon gpu-remote` / `addons/gpu-remote/compose.yaml` |
| [slurm](addons/slurm/README.md) | Jobs on an HPC cluster with capped resources, via a forced-command SSH gateway | `--addon slurm` / `addons/slurm/compose.yaml` |
| [git-remote](addons/git-remote/README.md) | One GitHub / Forgejo / GitLab account: host, service and token; git push/pull over HTTPS and API calls | `--addon git-remote` / `addons/git-remote/compose.yaml` |
| [github-app](addons/github-app/README.md) | GitHub as your organization's GitHub App: the private key stays in the gateway, which hands the agent 1-hour installation tokens for git (credential helper) and `gh` | `--addon github-app` / `addons/github-app/compose.yaml` |
| [notify](addons/notify/README.md) | Push notifications (ntfy, Gotify, Discord, Slack, webhook) when Claude needs you, plus a `notify` command | `--addon notify` / `addons/notify/compose.yaml` |

A specific add-on mounts its client (`bin/`), helpers for its hooks (`libexec/`), its
`claude.md` and optional start-up hooks (`entrypoint.d/`) read-only into
`/opt/agent-sandbox/addons/<name>/`; the entrypoint links its commands into
`/opt/agent-sandbox/bin` (on `PATH`, also for `podman exec`), adds its `claude.md` to the
agent's environment notes and runs the hooks (as root, before dropping to `agent`). Its settings live in
`<name>.env` next to `gateway.env`.

**Firewall:** the add-on's env file is also mounted into the gateway
(`/etc/agent-sandbox/addons/<addon>.env`). At start the gateway allowlists the host of
every `*_HOST` and `*_URL` value in it and lets every `*_PRIVATE_IP` address through the
private-range block, like `GATEWAY_PRIVATE_ALLOW`. The file is parsed, not executed, and
other keys (tokens) are ignored. The gateway log lists what each add-on added.

Remove the drop-ins (Quadlet: `<name>.container.d/3x-<addon>.conf` and
`<name>-gateway.container.d/50-addon-<addon>.conf`) or the `-f` file (Compose) to turn an
add-on off.

## Common tasks

- **Add hosts:** `extra.list` (one per line) or `GATEWAY_EXTRA_DOMAINS`, then restart the
  gateway.
- **Git push:** no credentials are in the container by default. Commit inside, push from
  the host, or enable an add-on: [github-app](addons/github-app/README.md) for GitHub
  (recommended: an org-owned App, short-lived tokens, the key stays in the gateway) or
  [git-remote](addons/git-remote/README.md) with a fine-grained token scoped to the
  repositories the agent should push to (Forgejo, GitLab, or GitHub).
- **Update:** images: Quadlet automatically via `podman-auto-update.timer` (`podman
  auto-update` by hand), Compose `docker compose pull && docker compose up -d`. Claude
  Code and Codex: restart the container (a channel is re-checked after a day; delete
  `/opt/claude-code/.checked-*` or `/opt/codex/.checked-latest` as root to force it).
- **Reset state:** stop the sandbox, then `podman volume rm agent-sandbox-julia-depot`
  (or another volume).

## Troubleshooting

Start with the gateway log (`journalctl --user -u <name>-gateway -e` or
`docker compose logs gateway`).

- **`no gateway proxy on 127.0.0.1:3128`** in the agent log: the gateway didn't start or
  the agent doesn't share its namespace. Check the gateway log first.
- **A download fails with 403 / `CONNECT tunnel failed`:** the host isn't allowlisted.
  The gateway log names it.
- **A tool ignores the proxy** (custom HTTP clients, some language package managers):
  set its proxy option, or use `GATEWAY_MODE=strict` for direct access to the
  allowlisted IPs.
- **`ipset`/`iptables` errors** (rootless containers can't load kernel modules). Load
  them on the host once:
  ```bash
  sudo modprobe -a ip_set ip_set_hash_net xt_set xt_mark xt_owner xt_multiport tun
  printf '%s\n' ip_set ip_set_hash_net xt_set xt_mark xt_owner xt_multiport tun | sudo tee /etc/modules-load.d/agent-sandbox.conf
  ```
- **`claude: command not found`** (or `codex`): the add-on isn't mounted, or the start-up
  install failed. The agent log says which; usually `claude-code.env` / `codex.env` isn't
  mounted into the gateway, so `downloads.claude.ai` / `registry.npmjs.org` is refused. An
  instance set up before Claude Code became an add-on needs `setup.sh` once more, see
  [claude-code](addons/claude-code/README.md#instances-set-up-before-claude-code-was-an-add-on).
- **Units don't exist after `daemon-reload`:** run `/usr/libexec/podman/quadlet -dryrun -user`;
  it prints the parsing error. Drop-ins and `Network=<name>.container` need Podman >= 5.0.
- **Services stop when you log out:** linger is off. `sudo loginctl enable-linger agent-sandbox`.
- **`TS_EXIT_NODE must be the exit node's Tailscale IPv4`:** use its `100.x.y.z`
  address, not its hostname. If status doesn't show `active; exit node`, approve the exit
  node and check your ACLs (`autogroup:internet`).
- **`tstun.New("tailscale0"): permission denied`:** SELinux blocking the TUN device. The
  Tailscale drop-in sets `SecurityLabelDisable=true`; the host-wide alternative is
  `sudo setsebool -P container_use_devices on`.
- **Dev server page doesn't load:** the port must be published (`--port`), the server
  must listen on `0.0.0.0`, and with Tailscale your ACLs must allow it.
- **GLMakie `GLFW initialization failed`:** check `/tmp/xvfb.log` and `glxinfo -B` in the
  container (OpenGL core profile >= 3.3).

## Known limits

- Containers share the host kernel. For a hard boundary use a VM.
- `strict` mode's direct access is IP-based. CDN IPs are shared with other sites, so it
  is coarse, and IPs that rotate after startup need a gateway restart.
- An allowed host is allowed entirely: anything the agent can upload to it (a GitHub
  gist, an npm package) can leave. Keep the allowlist short.
- Opened inbound ports are reachable by every device your ACLs (or localhost users)
  allow. Dev servers, Bonito and ocp_vscode have no authentication.
- Anything in the agent's environment (`sandbox.env`, e.g. `ANTHROPIC_API_KEY`) is
  readable by the agent, and so are its own logins (`~/.claude`, `~/.codex/auth.json`) and
  the tokens of the git-remote and notify add-ons. The github-app add-on keeps its key in
  the gateway, but the agent can get (and use) its one-hour tokens while it runs.

## License

The files in this repository are MIT licensed ([LICENSE](LICENSE)). The images contain
third-party software under its own licenses, and Claude Code and Codex are downloaded at
runtime under their vendors' terms; see [NOTICE](NOTICE).
