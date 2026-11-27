# Podman Quadlet

`deploy/quadlet/setup.sh` turns a few options into Quadlet units (systemd user services)
for one **instance**: a gateway and an agent container. By default they run under the
dedicated user `agent-sandbox`, so a container escape lands in an empty account. Needs
Podman >= 5.0. The first run is covered in the [quick start](../getting-started/quadlet.md).

## What setup.sh does

Run as **your normal user**; it uses sudo where needed.

1. **Host setup** (skip with `--no-host-setup`): subuids/subgids for the sandbox user,
   linger (so the services run without a login), the workspace folder shared with your
   user via ACLs and labelled for SELinux.
2. **Units** in `~agent-sandbox/.config/containers/systemd/`:
   `<name>.network`, `<name>-gateway.container`, `<name>.container`, and drop-ins in
   `<name>.container.d/` and `<name>-gateway.container.d/` for the network variant, the
   GPU and each add-on.
3. **Config** in `~agent-sandbox/.config/agent-sandbox/<name>/`: `gateway.env`,
   `sandbox.env`, `extra.list`, one `<addon>.env` per add-on, and `setup.conf` with the
   options used. Existing env files are kept.

Run it again with the same `--name` to change an instance (it rewrites the units and
keeps the env files), or with another `--name` for another project. Every option is in
the [setup.sh reference](../reference/setup-sh.md); `--dry-run` prints what would be
written. `./setup.sh -i` asks for the settings instead, and can start from an existing
instance's settings: see [Guided setup](../reference/setup-sh.md#guided-setup).

## Several projects

One instance per project:

```bash
./setup.sh --name web  --flavor node-utils  --workspace ~/code/site --port 5173
./setup.sh --name sims --flavor julia-utils --workspace ~/code/Sims.jl
```

Shared between instances: Claude's login (`~/.claude` volume), Codex's
(`~/.config/agent-sandbox/codex/` of the sandbox user), the language caches and the
shell history. Each instance has its own gateway, allowlist and workspace.

## Inspecting and changing an instance

```bash
./setup.sh show web                       # settings, add-ons, and the line that recreates it
./setup.sh add-addon web github-app notify
./setup.sh remove-addon web notify        # its env file stays
```

Then, as the sandbox user, `systemctl --user daemon-reload` and
`systemctl --user restart web-gateway`. See [Add-ons](../concepts/addons.md#managing-add-ons).

## Working as the sandbox user

```bash
sudo machinectl shell agent-sandbox@
systemctl --user status web-gateway web
journalctl --user -u web-gateway -e       # gateway log: allowlist, refused hosts
journalctl --user -u web -e               # agent log: add-on hooks, "Sandbox ready"
podman exec -it -u agent web zsh          # a shell in the sandbox
```

Always pass `-u agent` to `podman exec`; without it you are root in the container.

From your own account, an alias saves the user switch:

```bash
alias claude-web='sudo machinectl shell agent-sandbox@ /usr/bin/podman exec -it -u agent web claude --dangerously-skip-permissions'
```

## Restarts

The agent unit is bound to its gateway (`BindsTo=`/`PartOf=`), so
`systemctl --user restart web-gateway` restarts both. A restarted gateway has a new
network namespace; the agent always follows it and fails closed, never open.

Env file changes (`gateway.env`, `extra.list`, add-on env files) take effect on a gateway
restart. Unit changes need `systemctl --user daemon-reload` first.

## Running under your own account

`--sandbox-user "$USER"` runs the containers as you. Simpler, but there is no isolation
between you and the containers beyond what the container itself provides.
