# gateway.env

Read only by the gateway. Keep it at mode 600: it may hold the Tailscale auth key. Quadlet:
`~agent-sandbox/.config/agent-sandbox/<name>/gateway.env`; Compose:
`deploy/compose/gateway.env`. Changes take effect on a gateway restart.

## Filtering

| Key | Default | |
|---|---|---|
| `GATEWAY_MODE` | `standard` | `standard`, `strict` or `open`, see [Modes](../concepts/gateway.md#modes). |
| `GATEWAY_PROFILES` | set by `setup.sh` | Allowlists to load besides `base`: `node`, `python`, `julia`, `octave` ([Allowlists](allowlists.md)). |
| `GATEWAY_EXTRA_DOMAINS` | | More allowed hosts, space or comma separated (`*.example.com` = with subdomains). Longer lists go into `extra.list` next to this file. |
| `GATEWAY_STRICT_CIDRS` | | `strict` mode: extra IPv4 networks the agent may reach directly (e.g. a provider's published ranges). |
| `GATEWAY_PRIVATE_ALLOW` | | Private addresses (LAN, tailnet `100.x`) the gateway may still reach, space or comma separated. The host must also be allowlisted. |
| `GATEWAY_INBOUND_PORTS` | set by `setup.sh` / `PORTS` | TCP ports reachable from outside (published ports, or the tailnet with Tailscale). |
| `GATEWAY_UPSTREAM_PROXY` | | Chain to an existing HTTP proxy, `host:port`. |
| `GATEWAY_AGENT_DNS` | `0` | `1` lets the agent use DNS in `standard`/`open` mode (always on in `strict`). |
| `GATEWAY_LOG_LEVEL` | `Connect` | tinyproxy log level. |
| `JULIA_PKG_SERVER` | | Regional Julia package server, e.g. `https://eu-central.pkg.julialang.org`; also allowlisted automatically. |

## Tailscale

Only with `--net tailscale` / `compose.tailscale.yaml`. See
[Tailscale exit node](../deployment/tailscale.md).

| Key | |
|---|---|
| `TS_AUTHKEY` | Auth key. Tag it (e.g. `tag:agent-sandbox`) to restrict the sandbox with ACLs. |
| `TS_EXIT_NODE` | The exit node's Tailscale IPv4 (`tailscale ip -4` on it), not a hostname. |
| `TS_HOSTNAME` | The sandbox's name on the tailnet; must be unique per sandbox. |
| `TS_EXTRA_ARGS` | Extra `tailscale up` flags. `--accept-routes` is needed to reach LAN hosts behind a subnet router. |

## extra.list

Next to `gateway.env`, mounted read-only into the gateway. One host per line,
`*.example.com` matches the domain and all its subdomains, `#` starts a comment.

## Add-on env files

Each enabled add-on's `<addon>.env` is mounted into the gateway too. The gateway
allowlists the host of every `*_HOST` and `*_URL` value and lets every `*_PRIVATE_IP`
through, see [Add-ons](../concepts/addons.md#firewall).
