# Images

All agent images are `ghcr.io/OWNER/agent-sandbox:<flavor>` (also `<flavor>-YYYYMMDD`),
for `linux/amd64` and `linux/arm64`. The gateway is
`ghcr.io/OWNER/agent-sandbox-gateway:latest` (plain) and `:tailscale`.

## Two tiers: core and `-utils`

The headless **core** images are *base* (shell tools, build tools, Python 3 + uv) plus a
language. Each also comes as **`-utils`**, with the utilities layer on top: a virtual
display (Xvfb + Mesa software OpenGL) and headless Chromium.

Stay headless and you only pull the core. A `-utils` image adds one layer on top of the
same core, so a host running both stores the core once. New general tools go into the
utilities layer, not into another variant.

| Core flavor | Chain | For | `-utils` adds |
|---|---|---|---|
| `minimal` | base | Python projects, scripting, plain repo work | CAD (build123d), plotting, browser checks |
| `node` | base + node | Websites, JS/TS tooling | Playwright / browser checks |
| `julia` | base + julia | Julia packages, CairoMakie | GLMakie, WGLMakie tests (Electron.jl) |
| `octave` | base + octave | MATLAB-style code with GNU Octave (+ signal, statistics, control, optim, io, image, symbolic) | Plots through the virtual display |
| `full` | base + node + julia | Everything | Everything |

`full-rocm` is `full-utils` + ROCm (amd64 only), for AMDGPU.jl and PyTorch-ROCm. See
[gpu-local](../addons/gpu-local.md).

Every flavor allows PyPI by default (the `python` allowlist), since every image has
Python.

## What's in each part

| Part | Folder | Contents |
|---|---|---|
| base | `images/base` | Debian trixie, git, gh, delta, zsh, build tools, Python 3 + uv, entrypoint |
| language images | `images/node`, `images/julia`, `images/octave` | Node 26 LTS + corepack · Julia (checksum-verified) · GNU Octave |
| general layers | `layers/utils`, `layers/rocm` | Virtual X display + Mesa, headless Chromium · ROCm runtime |
| final step | `images/final` | Proxy settings, environment notes for the agent (last step of every image) |
| gateway | `gateway` | Firewall, proxy, allowlists (`gateway/lists/*.list`) |

No coding agent is part of any image: the [claude-code](../addons/claude-code.md) and
[codex](../addons/codex.md) add-ons install them at container start.

## Environment notes for the agent

The base and each layer add a fragment (`claude-md/*.md` in their folder) to the
environment notes in `/etc/agent-sandbox/AGENTS.md`, and so does each mounted add-on, so
the agent is told exactly which tools it has. The file is root-owned.

- The claude-code add-on hands it to Claude Code as the managed
  `/etc/claude-code/CLAUDE.md`, loaded in every session.
- The codex add-on hands it to Codex as `developer_instructions` in
  `/etc/codex/config.toml`.

A project's own `CLAUDE.md` / `AGENTS.md` adds to these notes and wins where they
conflict.

## Building locally

Every flavor is a chain of normal `podman build` / `docker build` steps:
`images/base` → its layers → `images/final`. To build instead of pulling:

```bash
./build.sh --list             # flavors and their chains
./build.sh node gateway       # images tagged localhost/...
```

Then use `--registry localhost` with `setup.sh` (or `REGISTRY=localhost` in Compose's
`.env`). Options and version pins are in the [build.sh reference](../reference/build-sh.md).

To add a language, add a folder under `images/` and one entry to `CHAIN` in `build.sh`:
the `-utils` variant is derived from it.
