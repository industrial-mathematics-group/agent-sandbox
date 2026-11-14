# Add-ons

There are two kinds of add-ons:

- **General add-ons are image layers** (`layers/`): the utilities layer of the `-utils`
  flavors and ROCm. You get them by picking a flavor that has them, or by building your own
  chain in `build.sh`. See [Images](images.md).
- **Specific add-ons** (`addons/`) are switched on per instance: the coding agents, Git
  access, notifications, GPUs and clusters. The rest of this page is about them; the list
  is in the [add-on reference](../addons/index.md).

## How an add-on is mounted

An add-on folder can contain:

| Path | Purpose |
|---|---|
| `bin/` | Commands for the agent (`gh`, `gpu`, `slurm`, `notify`, ...) |
| `libexec/` | Helpers for its start-up hooks (e.g. the Claude Code installer) |
| `claude.md` | Its fragment of the agent's environment notes |
| `entrypoint.d/` | Start-up hooks, run as root before the entrypoint drops to `agent` |
| `<name>.env.example` | Its settings file |
| `quadlet/` | Drop-ins for the agent unit (and `quadlet/gateway/` for the gateway unit) |
| `compose.yaml` | Compose overlay |
| `server/` | Code that runs on a remote machine (gpu-remote, slurm) |

At start, the add-on's `bin/`, `libexec/`, `claude.md` and `entrypoint.d/` are mounted
read-only into `/opt/agent-sandbox/addons/<name>/` of the agent container. The entrypoint
then:

1. links its commands into `/opt/agent-sandbox/bin` (on `PATH`, also for `podman exec`),
2. adds its `claude.md` to the agent's environment notes,
3. runs its hooks (as root, before dropping to `agent`).

Its settings live in `<name>.env` next to `gateway.env`.

## Firewall

The add-on's env file is also mounted into the gateway, as
`/etc/agent-sandbox/addons/<name>.env`. At start the gateway:

- allowlists the host of every `*_HOST` and `*_URL` value in it,
- lets every `*_PRIVATE_IP` address through the private-range block, like
  `GATEWAY_PRIVATE_ALLOW`.

The file is parsed, not executed, and other keys (tokens) are ignored. The gateway log
lists what each add-on added. This is also why a sandbox without the claude-code add-on
can't reach Anthropic at all.

## Managing add-ons

=== "Quadlet"

    Choose add-ons when setting up (`setup.sh --addon NAME`, repeatable), or change an
    existing instance without retyping its options:

    ```bash
    ./setup.sh show web                        # settings, add-ons, and the setup.sh line that recreates it
    ./setup.sh add-addon web github-app        # several at once: add-addon web notify git-remote
    ./setup.sh remove-addon web notify         # its env file stays for later
    ```

    They read the settings `setup.sh` saved in `~/.config/agent-sandbox/<name>/setup.conf`
    of the sandbox user, rewrite the units and keep every env file. Then, as the sandbox
    user, `systemctl --user daemon-reload` and restart the gateway. Pass `--sandbox-user`
    when it isn't `agent-sandbox`.

=== "Compose"

    Add the add-on's `compose.yaml` to `COMPOSE_FILE` in `.env` (or pass it with `-f`),
    and copy its `<name>.env.example` to `deploy/compose/<name>.env`. Remove the file from
    the list to turn the add-on off.

    Env files mounted into the agent must be readable by uid 1000 inside: your own user
    with `compose.podman.yaml`, otherwise `chown 1000`.

## Installing by hand

`setup.sh` rewrites an instance's units. If you maintain them yourself, let it show you
what it would write and copy what you need:

```bash
./setup.sh --name web --flavor node-utils --addon git-remote --dry-run
```

In short, for add-on `<addon>` and instance `<name>`, as the sandbox user:

1. copy `bin/`, `libexec/`, `claude.md` and `entrypoint.d/` (whichever exist) to
   `~/.config/agent-sandbox/addons/<addon>/`,
2. copy `<addon>.env.example` to `~/.config/agent-sandbox/<name>/<addon>.env` (mode 600),
3. copy `quadlet/*.conf` to `<name>.container.d/` and `quadlet/gateway/*.conf` (if any) to
   `<name>-gateway.container.d/`,
4. copy `deploy/quadlet/addon-gateway.conf` to
   `<name>-gateway.container.d/50-addon-<addon>.conf`,

replacing the `@...@` placeholders (`@ADDON_DIR@`, `@CONFIG_DIR@`, `@NAME@`, `@ADDON@`)
in the copied drop-ins.
