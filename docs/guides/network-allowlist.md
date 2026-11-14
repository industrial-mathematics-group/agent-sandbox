# Network allowlist

New instances allow the `base` list (GitHub), PyPI, the language of the flavor, and the
hosts of their add-ons. Anything else is refused until you allow it.

## Add hosts

Either works; restart the gateway afterwards.

- `extra.list` next to `gateway.env`, one host per line (`*.example.com` includes
  subdomains),
- `GATEWAY_EXTRA_DOMAINS` in `gateway.env`, space or comma separated,
- another profile in `GATEWAY_PROFILES` (`node`, `python`, `julia`, `octave`), see
  [Allowlists](../reference/allowlists.md).

=== "Quadlet"

    ```bash
    nano ~/.config/agent-sandbox/web/extra.list
    systemctl --user restart web-gateway
    ```

=== "Compose"

    ```bash
    nano extra.list
    docker compose restart gateway agent
    ```

## Find out what a project needs

The proxy logs every request, including refused ones
(`Proxying refused on filtered domain "…"`). Run once in `open` mode, let the agent do its
usual work (install dependencies, run tests), then read the gateway log and copy the hosts
you trust into `extra.list`:

```bash
journalctl --user -u web-gateway | grep -o 'CONNECT [^ ]*' | sort -u    # Quadlet
docker compose logs gateway | grep -o 'CONNECT [^ ]*' | sort -u         # Compose
```

Switch back to `standard` afterwards.

## Tools that ignore the proxy

Most tools honour `HTTPS_PROXY`. For the ones that don't (custom HTTP clients, some
language package managers), set the tool's own proxy option to `127.0.0.1:3128`, or use
`GATEWAY_MODE=strict`, which also allows direct connections to the IPs the allowlist
resolved to at startup. It is IP-based and coarse, see
[Known limits](../concepts/isolation.md#known-limits).

## Your own services

LAN and tailnet addresses are blocked even for allowlisted names. Allowlist the name and
add the address to `GATEWAY_PRIVATE_ALLOW`, see
[Private services](../concepts/gateway.md#private-services).

## Keep it short

An allowed host is allowed entirely: anything the agent can upload there can leave. Prefer
specific hosts over wildcards, and don't keep `open` mode running.
