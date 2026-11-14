# Getting started

A sandbox instance is two containers: a **gateway** that owns the network (firewall and
filtering proxy) and an **agent** container that joins the gateway's network namespace
and sees only your project folder. The coding agent (Claude Code, Codex) is installed into
the agent container at start by an [add-on](../addons/index.md).

## Pick a deployment

| | [Podman Quadlet](quadlet.md) | [Docker / Podman Compose](compose.md) |
|---|---|---|
| Runs as | systemd user services under a dedicated Linux user | your user (rootless Podman/Docker) or root (rootful Docker) |
| Platforms | Linux with Podman >= 5.0 | anything that runs Compose |
| Setup | `setup.sh` writes the units and config for you | copy a few example files |
| Updates | automatic (`podman-auto-update.timer`) | `docker compose pull` |
| Recommended for | Linux workstations and servers | macOS, Windows, quick trials |

Quadlet is recommended on Linux: a container escape lands in an empty account, and the
instance starts with the machine.

## Pick an image

Every image is `ghcr.io/OWNER/agent-sandbox:<flavor>`. Start with the language of your
project, and add `-utils` if the agent needs a display or a browser (plots, Playwright,
GLMakie):

| Project | Flavor |
|---|---|
| Python, scripting, plain repository work | `minimal` |
| Websites, JS/TS | `node` (or `node-utils` for Playwright) |
| Julia | `julia` (or `julia-utils` for GLMakie) |
| MATLAB-style code | `octave` |
| A bit of everything | `full` / `full-utils` (default) |

[Images](../concepts/images.md) explains the tiers and what each flavor contains.

## Pick a coding agent

Claude Code is included by default. Codex is one option away
(`--addon codex` with Quadlet, one more Compose file). Both can run in the same sandbox.
See [claude-code](../addons/claude-code.md) and [codex](../addons/codex.md).

## Before you start

- **Kernel modules:** rootless containers can't load the `ipset`/`iptables` modules the
  gateway needs. If the gateway log shows `ipset`/`iptables` errors, load them once on
  the host (see [Troubleshooting](../guides/troubleshooting.md#ipset-iptables-errors)).
- **Images built locally** instead of pulled: `./build.sh --list`, then e.g.
  `./build.sh node gateway` and use the registry `localhost`
  ([build.sh](../reference/build-sh.md)).

Then follow [Quadlet](quadlet.md) or [Compose](compose.md).
