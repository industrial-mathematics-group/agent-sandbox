# Gateway and network

The agent container has no network of its own. It joins the network namespace of the
**gateway** container, which runs the firewall (iptables/ipset) and a filtering proxy
(tinyproxy). The agent has no network capabilities, so it can't change the rules; the
gateway's secrets (a Tailscale auth key, a GitHub App key) never enter the agent.

## What always holds

- The agent can only reach the proxy on `127.0.0.1:3128` (`HTTPS_PROXY` points there).
- The proxy only connects to **public** IPs, on ports 80, 443 and 22. SSH goes through
  it via `ProxyCommand`.
- LAN ranges, cloud metadata and IPv6 are blocked, even for allowlisted names (unless you
  [allow a private address](#private-services) explicitly).
- In `standard` and `open` mode the agent can't use DNS either, which closes the DNS side
  channel.
- Inbound is closed except the ports you publish (`--port`, `PORTS`), which the gateway
  opens (`GATEWAY_INBOUND_PORTS`).

## Allowlists

The gateway loads `base.list` plus the profiles in `GATEWAY_PROFILES`, your
`extra.list`, `GATEWAY_EXTRA_DOMAINS`, and the hosts of every enabled add-on. Entries are
host names; `*.example.com` matches `example.com` and all its subdomains. The profiles and
their hosts are in the [allowlists reference](../reference/allowlists.md).

The proxy logs every request, including refused ones, so the gateway log tells you what
a project needs. See [Network allowlist](../guides/network-allowlist.md) for the
workflow.

## Modes

| `GATEWAY_MODE` | What gets out |
|---|---|
| `standard` (default) | Only allowlisted hosts, checked by name in the proxy. No IP lists to go stale, wildcards work. |
| `strict` | `standard`, plus direct connections to the IPv4 addresses the allowlist resolves to at startup (plus networks in `GATEWAY_STRICT_CIDRS`), for tools that ignore proxy settings. IP-based, so coarse. |
| `open` | Any public host through the proxy. LAN, metadata and IPv6 stay blocked. |

## Tailscale exit node

With the Tailscale gateway image, the gateway also runs tailscaled, and everything may
only leave via `tailscale0`. If the tunnel is down, nothing gets out. Published ports are
then reachable from your tailnet instead of localhost. Setup:
[Tailscale exit node](../deployment/tailscale.md).

## Private services

Private ranges (LAN, tailnet `100.x`) are blocked even for allowlisted names. To reach one
of your own services, allowlist its name and add its address to `GATEWAY_PRIVATE_ALLOW`
in `gateway.env`, e.g. `GATEWAY_PRIVATE_ALLOW=100.85.46.4`. The usual ports apply
(80/443/22, via `tailscale0` with Tailscale). Prefer single addresses over ranges. LAN
hosts behind a subnet router also need `TS_EXTRA_ARGS=--accept-routes`.

Add-ons do both for their own hosts: every `*_PRIVATE_IP` in an add-on's env file is let
through, see [Add-ons](addons.md#firewall).

## Corporate proxy

`GATEWAY_UPSTREAM_PROXY=host:port` chains the gateway's proxy to an existing HTTP proxy.

## Restarts

A restarted gateway has a new network namespace. The agent container is bound to its
gateway and always follows it: it fails closed, never open. With Quadlet,
`systemctl --user restart <name>-gateway` restarts both.

All gateway settings: [gateway.env reference](../reference/gateway-env.md).
