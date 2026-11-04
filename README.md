# agent-sandbox

[![AI generation](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-generation.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#g-generation)
[![Human review](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-human-review.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#h-human-review)
[![AI review](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/industrial-mathematics-group/agent-sandbox/badges/ai-review.json)](https://github.com/industrial-mathematics-group/.github/blob/main/.github/CONTRIBUTING.md#a-ai-review)

Sandboxed containers for running Claude Code (and similar coding agents) with
`--dangerously-skip-permissions`, without handing them your machine or your network.

- **Small images per language:** node, python, julia, or all of them, each optionally
  with a virtual display, headless Chromium or ROCm.
- **Network through a gateway:** the agent container has no network of its own. It
  shares the namespace of a gateway sidecar that runs the firewall and a filtering
  proxy, so the agent can't change the rules. Only allowlisted hosts get through; LAN,
  cloud metadata and IPv6 are blocked. Optionally all traffic leaves only through a
  Tailscale exit node.
- **Add-ons** for local GPUs and for running jobs on a remote GPU server or a Slurm
  cluster through restricted SSH gateways.
- **Runs on** rootless Podman with Quadlet (systemd user services, recommended on
  Linux) or Docker / Podman Compose.

The design is inspired by Anthropic's reference devcontainer (no files copied). Not an
Anthropic product. Claude Code itself is not part of the images: it is downloaded from
Anthropic when a container starts (see [What's isolated](#whats-isolated)).

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
| final step | `images/final` | Proxy settings, managed CLAUDE.md, mount point for Claude Code (last step of every image) |
| gateway | `gateway` | Firewall, proxy, allowlists (`gateway/lists/*.list`) |
| specific add-ons | `addons/gpu-local`, `addons/gpu-remote`, `addons/slurm` | Local GPU drop-ins · remote GPU gateway · Slurm gateway |
| deployment | `deploy/quadlet`, `deploy/compose` | Quadlet templates + `setup.sh` · Compose files |

Each layer adds a fragment to the managed `/etc/claude-code/CLAUDE.md`, and so does each
mounted add-on, so Claude is told exactly which tools it has. The file is root-owned
and loaded in every session.

Build locally instead of pulling: `./build.sh --list`, then e.g. `./build.sh node gateway`
(Podman or Docker, images tagged `localhost/…`; use `--registry localhost` below).

## Quick start: Docker / Podman Compose

```bash
cd deploy/compose
cp .env.example .env                      # REGISTRY, FLAVOR, WORKSPACE, ports
cp gateway.env.example gateway.env        # mode, allowlist profiles
cp sandbox.env.example sandbox.env        # visible to the agent: no secrets
touch extra.list                          # your own allowed hosts
docker compose up -d
docker compose logs -f agent              # wait for "Network ready"
docker compose exec -u agent agent claude # first time: log in
```

Rootless Podman: add `-f compose.podman.yaml` (maps your user to `agent`). Tailscale exit
node: add `-f compose.tailscale.yaml` and set `TS_*` in `gateway.env`. One Compose
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
3. As the sandbox user (`sudo machinectl shell agent-sandbox@`):
   ```bash
   nano ~/.config/agent-sandbox/web/gateway.env
   systemctl --user daemon-reload
   systemctl --user start web-gateway web
   systemctl --user enable --now podman-auto-update.timer
   podman exec -it -u agent web claude
   ```

Day to day: `podman exec -it -u agent web claude --dangerously-skip-permissions`. An alias
from your own account saves the user switch:

```bash
alias claude-web='sudo machinectl shell agent-sandbox@ /usr/bin/podman exec -it -u agent web claude --dangerously-skip-permissions'
```

Always pass `-u agent` to `exec`. Run `setup.sh` again with another `--name` for another
project; Claude's login (`~/.claude`) and the language caches are shared volumes.

**Restarts:** the agent unit is bound to its gateway (`BindsTo=`/`PartOf=`), so
`systemctl --user restart web-gateway` restarts both. A restarted gateway has a new
network namespace; the agent always follows it and fails closed, never open.

## Network

The gateway loads `base.list` plus the profiles in `GATEWAY_PROFILES`, your `extra.list`
and `GATEWAY_EXTRA_DOMAINS`. Entries are host names; `*.example.com` matches
`example.com` and all its subdomains.

| List | Hosts |
|---|---|
| `base` | Anthropic API and login, Claude Code downloads (`downloads.claude.ai`), GitHub (incl. `*.githubusercontent.com`) |
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
80/443/22, via `tailscale0` with Tailscale). Prefer single addresses over ranges.

**Corporate proxy:** `GATEWAY_UPSTREAM_PROXY=host:port` chains the gateway's proxy to it.

## What's isolated

| | |
|---|---|
| Files | Only the workspace (as `/workspace`). Your `$HOME`, SSH keys and browser profiles are not visible; with Quadlet the containers run under a separate Linux user. |
| Network | See above. The rules live in the gateway; the agent has no network capabilities. Secrets for the gateway (Tailscale auth key) are only in `gateway.env`. |
| Privileges | No sudo, `no-new-privileges`, all capabilities dropped (the entrypoint keeps SETUID/SETGID only to switch to `agent`). |
| Resources | Memory, CPU and process limits per container, so a runaway test can't freeze the machine. |
| Claude Code | Installed at container start by `install-claude-code` (as root, before the switch to `agent`) into the root-owned volume `agent-sandbox-claude-cli`, so the agent can run but not replace it; its own auto-updater is off. `CLAUDE_CODE_VERSION` in `sandbox.env`: `stable` (default) or `latest` are checked at most once a day (`CLAUDE_CODE_CHECK_MINUTES`), an exact version such as `2.1.30` pins it. If the download fails, the version already in the volume is kept. Needs `claude.ai` and `downloads.claude.ai` (in `base.list`). |
| Persistence | Named volumes: `agent-sandbox-claude` (login, settings), `-claude-cli` (Claude Code binaries), `-history`, `-cache` (uv, npm, Playwright), `-npm`, `-uv-python`, `-julia-depot`, `-octave` (Forge packages). |

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
| [gpu-local](addons/gpu-local/README.md) | AMD (ROCm) or NVIDIA (CDI) GPU of this machine | `--gpu amd\|nvidia` / `compose.gpu-*.yaml` |
| [gpu-remote](addons/gpu-remote/README.md) | Julia tests on a remote GPU server, via a forced-command SSH gateway + bubblewrap | `--addon gpu-remote` / `addons/gpu-remote/compose.yaml` |
| [slurm](addons/slurm/README.md) | Jobs on an HPC cluster with capped resources, via a forced-command SSH gateway | `--addon slurm` / `addons/slurm/compose.yaml` |

A specific add-on mounts its client (`bin/`) and its `claude.md` read-only into
`/opt/agent-sandbox/addons/<name>/`; the entrypoint adds it to `PATH` and to the
managed CLAUDE.md. Remove the drop-in (Quadlet) or the `-f` file (Compose) to turn it
off.

## Common tasks

- **Add hosts:** `extra.list` (one per line) or `GATEWAY_EXTRA_DOMAINS`, then restart the
  gateway.
- **Git push:** no credentials are in the container on purpose. Commit inside, push from
  the host. If you want the agent to push, use a fine-grained token or deploy key scoped
  to that single repo.
- **Update:** images: Quadlet automatically via `podman-auto-update.timer` (`podman
  auto-update` by hand), Compose `docker compose pull && docker compose up -d`. Claude
  Code: restart the container (a channel is re-checked after a day; delete
  `/opt/claude-code/.checked-*` as root to force it).
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
- **`claude: command not found`:** the start-up install failed. The agent log says why;
  usually `downloads.claude.ai` is not reachable through the gateway.
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
  readable by the agent.

## License

The files in this repository are MIT licensed ([LICENSE](LICENSE)). The images contain
third-party software under its own licenses, and Claude Code is downloaded at runtime
under Anthropic's terms; see [NOTICE](NOTICE).
