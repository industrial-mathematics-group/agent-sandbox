# Quick start: Podman Quadlet

Two containers per instance run as systemd user services under a dedicated Linux user,
so a container escape lands in an empty account. Needs Linux and Podman >= 5.0.

## 1. Create the sandbox user

Once per machine:

```bash
sudo useradd -m agent-sandbox
```

## 2. Set up an instance

As your normal user, from a clone of the repository:

```bash
cd deploy/quadlet
./setup.sh --registry ghcr.io/OWNER --flavor node-utils --name web \
           --workspace /var/srv/agent-sandbox/web --port 5173
```

`setup.sh` sets up subuids, linger, the workspace (shared with your user via ACLs,
SELinux-labelled), and writes the units and config for that combination. It prints the
next steps when it is done. Claude Code is included unless you choose agents yourself:
`--addon codex` for Codex only, `--addon claude-code --addon codex` for both. All options
are in the [setup.sh reference](../reference/setup-sh.md).

!!! tip "Guided setup"
    Rather answer questions than look up options? `./setup.sh -i` walks you through the
    image, add-ons, CPU/memory limits, GPU and network one step at a time, then prints the
    equivalent `setup.sh` command line before writing anything. See
    [Guided setup](../reference/setup-sh.md#guided-setup).

## 3. Configure and start

As the sandbox user (`sudo machinectl shell agent-sandbox@`):

```bash
nano ~/.config/agent-sandbox/web/gateway.env      # mode, allowlist profiles
systemctl --user daemon-reload
systemctl --user start web-gateway web
systemctl --user enable --now podman-auto-update.timer
```

If your image packages are private, log in once as the sandbox user with
`podman login --authfile ~/.config/containers/auth.json ghcr.io` (`setup.sh` prints this
line too).

## 4. Log in to the agent

```bash
podman exec -it -u agent web claude      # first time: log in
```

For Codex, see [its login options](../addons/codex.md#login): the browser login doesn't
work in a headless container.

## Day to day

```bash
podman exec -it -u agent web claude --dangerously-skip-permissions
podman exec -it -u agent web codex --dangerously-bypass-approvals-and-sandbox
```

Always pass `-u agent` to `exec`. An alias in your own account saves the user switch:

```bash
alias claude-web='sudo machinectl shell agent-sandbox@ /usr/bin/podman exec -it -u agent web claude --dangerously-skip-permissions'
```

## Next steps

- Let the agent reach the hosts your project needs: [Network allowlist](../guides/network-allowlist.md).
- Give it GitHub access: [github-app](../addons/github-app.md).
- Get notified when it needs you: [notify](../addons/notify.md).
- Manage instances, add-ons and restarts: [Deployment with Quadlet](../deployment/quadlet.md).
