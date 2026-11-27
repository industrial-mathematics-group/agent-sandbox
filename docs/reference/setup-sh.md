# setup.sh

`deploy/quadlet/setup.sh` installs an agent-sandbox instance as rootless Podman Quadlet
units (systemd user services), by default under a dedicated sandbox user. Run it as
**your normal user**; it uses sudo where needed. `./setup.sh --help` prints the same
summary.

## Commands

```bash
./setup.sh [options]                   # set up (or rewrite) an instance
./setup.sh -i [options]                # the same, guided: asks for each setting
./setup.sh show NAME                   # an instance's settings and add-ons
./setup.sh add-addon NAME ADDON...     # add add-ons to an instance
./setup.sh remove-addon NAME ADDON...  # remove add-ons from an instance
```

`show`, `add-addon` and `remove-addon` read the instance's settings (saved by `setup.sh`
in `~SANDBOX_USER/.config/agent-sandbox/NAME/setup.conf`) and keep every env file. Pass
`--sandbox-user` if it is not `agent-sandbox`; other options change that setting too. Host
setup is skipped for them unless you pass `--host-setup`.

## Options

| Option | Default | |
|---|---|---|
| `--name NAME` | `agent` | Instance name. One instance = one gateway + one agent container; run several for several projects. |
| `--flavor FLAVOR` | `full-utils` | Image flavor: `minimal`, `node`, `julia`, `octave`, `full`, each also as `FLAVOR-utils`, or `full-rocm`. See [Images](../concepts/images.md). |
| `--workspace DIR` | `/var/srv/agent-sandbox/<name>` | Host folder mounted as `/workspace`. |
| `--net plain\|tailscale` | `plain` | Egress directly, or only via a [Tailscale exit node](../deployment/tailscale.md). |
| `--mode standard\|strict\|open` | `standard` | Gateway filter mode, see [Modes](../concepts/gateway.md#modes). |
| `--profiles LIST` | `python` + the flavor's language | Allowlists besides base, e.g. `julia,python`. |
| `--port N` | | Publish/open a TCP port for dev servers (repeatable). Plain: on `127.0.0.1:N` of the host; Tailscale: open on the tailnet. |
| `--gpu amd\|nvidia` | | Local GPU (`amd` switches to the `-rocm` image), see [gpu-local](../addons/gpu-local.md). |
| `--addon NAME` | `claude-code` | Add-on: `claude-code`, `codex`, `gpu-remote`, `slurm`, `git-remote`, `notify`, `github-app` (repeatable). `claude-code` is added unless `claude-code` or `codex` is given. |
| `--claude-config SRC` | volume `agent-sandbox-claude` | `~/.claude` of the claude-code add-on: a named volume or an absolute host folder. |
| `--codex-config SRC` | `~SANDBOX_USER/.config/agent-sandbox/codex` | `~/.codex` of the codex add-on: an absolute host folder or a named volume. |
| `--memory SIZE` | `16g` | Memory limit of the agent container. |
| `--cpus N` | `min(8, nproc)` | CPU limit of the agent container. |
| `--registry REG` | `$AGENT_SANDBOX_REGISTRY` | Image registry, e.g. `ghcr.io/OWNER`; `localhost` for images built with `./build.sh`. Required. |
| `--sandbox-user USER` | `agent-sandbox` | Run the containers as this user. `"$USER"` = your own account, no isolation between you and it. |
| `--no-host-setup` | | Skip the subuid/linger/groups/ACL/SELinux steps. |
| `--host-setup` | | Do them (for `show`/`add-addon`/`remove-addon`). |
| `--dry-run` | | Print what would be written, change nothing. |
| `-i`, `--interactive` | | [Guided setup](#guided-setup) in the terminal. Other options given with it are the defaults of the questions. |

## Guided setup

`./setup.sh -i` (or `--interactive`) asks for the settings one step at a time instead of
taking them as options:

1. **Sandbox user** and **instance name**. If the instance exists, it offers to start
   from its saved settings (its env files are kept either way).
2. **Image**: registry, language (`minimal`, `node`, `julia`, `octave`, `full`) and
   variant (headless, `-utils`, or `-rocm` for `full`), then the workspace folder.
3. **Add-ons**: a checklist of `claude-code`, `codex`, `github-app`, `git-remote`,
   `notify`, `slurm` and `gpu-remote`, with at least one coding agent. Then where
   `~/.claude` / `~/.codex` live for the agents you picked.
4. **Hardware**: memory and CPU limits of the agent container (it shows what the host
   has) and a local GPU (none, AMD, NVIDIA).
5. **Network**: plain or Tailscale, gateway mode, allowlist profiles (preselected for the
   image) and dev-server ports.
6. **Host setup**: yes the first time for a sandbox user and workspace.

At the end it shows a summary and the equivalent command line, and asks whether to write
the instance, only do a dry run, or cancel. Nothing is written before that, and Esc or
Ctrl-C at any question cancels.

The answers set exactly what the options set, and `setup.sh` then runs as it would with
those options, so a guided run writes the same files as the printed command line. Keep
that line to recreate the instance in a script, or see it again later with
`./setup.sh show NAME`.

It uses `whiptail` or `dialog` when one is installed, and plain numbered prompts
otherwise. `AGENT_SANDBOX_UI=plain` (or `whiptail`, `dialog`) picks one. It needs a
terminal; scripts keep using the options.

```bash
./setup.sh -i                                  # everything asked
./setup.sh -i --registry localhost --name sims # these as the defaults
AGENT_SANDBOX_UI=plain ./setup.sh -i           # plain prompts even with whiptail installed
```

## Example

A web project with a Vite dev server, then GitHub access for it:

```bash
./setup.sh --registry ghcr.io/OWNER --name web --flavor node-utils \
           --workspace ~/code/site --port 5173
./setup.sh add-addon web github-app
./setup.sh show web
```

## Files written

Under the sandbox user's home:

| Path | |
|---|---|
| `.config/containers/systemd/<name>.network`, `<name>-gateway.container`, `<name>.container` | Units |
| `.config/containers/systemd/<name>.container.d/`, `<name>-gateway.container.d/` | Drop-ins: network variant, GPU, add-ons |
| `.config/agent-sandbox/<name>/` | `gateway.env`, `sandbox.env`, `extra.list`, `<addon>.env`, `setup.conf` (kept when they exist) |
| `.config/agent-sandbox/addons/<addon>/` | Add-on files mounted into the containers |
