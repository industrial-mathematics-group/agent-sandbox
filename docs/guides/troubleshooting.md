# Troubleshooting

Start with the gateway log, then the agent log:

=== "Quadlet"

    ```bash
    journalctl --user -u <name>-gateway -e
    journalctl --user -u <name> -e
    ```

=== "Compose"

    ```bash
    docker compose logs gateway
    docker compose logs agent
    ```

## Network

**`no gateway proxy on 127.0.0.1:3128`** in the agent log
:   The gateway didn't start or the agent doesn't share its namespace. Check the gateway
    log first.

**A download fails with 403 / `CONNECT tunnel failed`**
:   The host isn't allowlisted. The gateway log names it; see
    [Network allowlist](network-allowlist.md).

**A tool ignores the proxy** (custom HTTP clients, some language package managers)
:   Set its proxy option, or use `GATEWAY_MODE=strict` for direct access to the
    allowlisted IPs.

### `ipset`/`iptables` errors {#ipset-iptables-errors}

Rootless containers can't load kernel modules. Load them on the host once:

```bash
sudo modprobe -a ip_set ip_set_hash_net xt_set xt_mark xt_owner xt_multiport tun
printf '%s\n' ip_set ip_set_hash_net xt_set xt_mark xt_owner xt_multiport tun | sudo tee /etc/modules-load.d/agent-sandbox.conf
```

## Agents

**`claude: command not found`** (or `codex`)
:   The add-on isn't mounted, or the start-up install failed. The agent log says which.
    Usually `claude-code.env` / `codex.env` isn't mounted into the gateway, so
    `downloads.claude.ai` / `registry.npmjs.org` is refused.

**Codex login doesn't complete**
:   Its browser login needs a redirect to `localhost:1455`, which a headless container
    can't receive. Copy `auth.json` or use `--device-auth`, see
    [codex](../addons/codex.md#login).

## Quadlet

**Units don't exist after `daemon-reload`**
:   Run `/usr/libexec/podman/quadlet -dryrun -user`; it prints the parsing error.
    Drop-ins and `Network=<name>.container` need Podman >= 5.0.

**Services stop when you log out**
:   Linger is off: `sudo loginctl enable-linger agent-sandbox`.

**`show`/`add-addon` can't find the instance**
:   They read `~/.config/agent-sandbox/<name>/setup.conf` of the sandbox user. Pass
    `--sandbox-user` if it isn't `agent-sandbox`, or run `setup.sh` with the full options
    once to write it.

## Tailscale

**`TS_EXIT_NODE must be the exit node's Tailscale IPv4`**
:   Use its `100.x.y.z` address, not its hostname. If status doesn't show
    `active; exit node`, approve the exit node and check your ACLs
    (`autogroup:internet`).

**`tstun.New("tailscale0"): permission denied`**
:   SELinux is blocking the TUN device. The Tailscale drop-in sets
    `SecurityLabelDisable=true`; the host-wide alternative is
    `sudo setsebool -P container_use_devices on`.

## Graphics and ports

**Dev server page doesn't load**
:   The port must be published (`--port`), the server must listen on `0.0.0.0`, and with
    Tailscale your ACLs must allow it.

**GLMakie `GLFW initialization failed`**
:   Check `/tmp/xvfb.log` and `glxinfo -B` in the container (OpenGL core profile >= 3.3).
    The display only exists in `-utils` flavors.

**WebGL canvases render blank in Chromium**
:   Pass `--no-sandbox --use-angle=swiftshader --enable-unsafe-swiftshader`, see
    [Headless Chromium](graphics-browsers.md#headless-chromium).

## Add-ons

Each add-on page has its own troubleshooting notes, e.g.
[github-app](../addons/github-app.md#troubleshooting). The gateway log lists the hosts each
add-on allowlisted (`Add-on <name>: allowing …`).
