# Tailscale exit node

With the Tailscale variant, the gateway also runs tailscaled, and all egress (the proxy,
and `strict` mode's direct connections) may only leave via `tailscale0`. If the tunnel is
down, nothing gets out. Use it to give the sandbox a fixed, known egress IP, or to keep it
off your local uplink.

## 1. Prepare the tailnet

1. On the exit node: `tailscale set --advertise-exit-node`, then approve it in the admin
   console.
2. Create an auth key, tagged (e.g. `tag:agent-sandbox`), so you can restrict the sandbox
   with ACLs.
3. In your ACLs, let the tag use the exit node (`autogroup:internet`), allow the published
   ports towards the sandbox from the devices that need them, and keep everything else
   towards the sandbox denied.

## 2. Configure the gateway

In `gateway.env`:

```bash
TS_AUTHKEY=tskey-auth-...
TS_EXIT_NODE=100.x.y.z          # the exit node's Tailscale IPv4 (`tailscale ip -4` on it), not a hostname
TS_HOSTNAME=web                 # unique per sandbox
#TS_EXTRA_ARGS=--accept-routes  # to reach LAN hosts behind a subnet router
```

## 3. Enable it

=== "Quadlet"

    ```bash
    ./setup.sh --name web ... --net tailscale
    ```

    This adds the drop-in `web-gateway.container.d/10-tailscale.conf`, which switches to
    the `:tailscale` gateway image and adds `/dev/net/tun` and a state volume.

=== "Compose"

    Add `compose.tailscale.yaml` to `COMPOSE_FILE`.

Published ports are then reachable from your tailnet (`http://<TS_HOSTNAME>:5173`)
instead of localhost.

## Private hosts on the tailnet

Tailnet addresses (`100.x`) are private, so they are blocked like LAN addresses. Allowlist
the name and add the address to `GATEWAY_PRIVATE_ALLOW`, or use an add-on's
`*_PRIVATE_IP`. See [Private services](../concepts/gateway.md#private-services).

Problems: see [Troubleshooting](../guides/troubleshooting.md#tailscale).
