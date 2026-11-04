#!/bin/bash
# agent-sandbox entrypoint. The network (proxy + firewall, optionally a VPN) is
# owned by the gateway sidecar; this container has no network capabilities.
# Runs as (container) root only long enough to check the network, run the layer
# hooks and assemble CLAUDE.md, then drops to `agent` for good.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "entrypoint.sh must start as root (it drops to 'agent' itself)." >&2
    exit 1
fi

PROXY_HOST=127.0.0.1
PROXY_PORT=${AGENT_PROXY_PORT:-3128}

# ---------------------------------------------------------------------------
# 1. Network checks: fail closed. Nothing else runs until they pass.
#    SANDBOX_SKIP_NETWORK_CHECK=1 skips them (only for debugging the image).
# ---------------------------------------------------------------------------
if [ "${SANDBOX_SKIP_NETWORK_CHECK:-0}" != 1 ]; then
    # The gateway starts its proxy only after the firewall is installed, so a
    # listening proxy also means "firewall active".
    for i in $(seq 120); do
        (exec 3<>"/dev/tcp/$PROXY_HOST/$PROXY_PORT") 2>/dev/null && break
        [ "$i" = 1 ] && echo "Waiting for the gateway (proxy on $PROXY_HOST:$PROXY_PORT) ..."
        sleep 1
    done
    if ! (exec 3<>"/dev/tcp/$PROXY_HOST/$PROXY_PORT") 2>/dev/null; then
        echo "ERROR: no gateway proxy on $PROXY_HOST:$PROXY_PORT after 120s." >&2
        echo "       Is the gateway running, and does this container share its network" >&2
        echo "       namespace (Quadlet: Network=<gateway>.container, Compose: network_mode: service:gateway)?" >&2
        exit 1
    fi
    # Direct connections must be blocked. IP literals: hostnames could share an
    # allowlisted CDN IP in strict mode.
    for ip in 1.1.1.1 9.9.9.9; do
        if curl --noproxy '*' -s -o /dev/null --connect-timeout 5 "https://$ip"; then
            echo "ERROR: $ip is reachable without the proxy: the gateway firewall is not active." >&2
            exit 1
        fi
    done
    require_reachable() {
        local url=$1 i
        for i in $(seq 24); do
            curl -s -o /dev/null --connect-timeout 5 "$url" && return 0
            [ "$i" = 1 ] && echo "Waiting for egress ($url) ..."
            sleep 5
        done
        echo "ERROR: $url is unreachable through the gateway. Check its log." >&2
        exit 1
    }
    require_reachable https://api.anthropic.com
    echo "Network ready (egress only through the gateway)."
fi

# ---------------------------------------------------------------------------
# Claude Code: installed/updated at start into the root-owned /opt/claude-code
# (not part of the image). A failed update keeps the version already there.
# ---------------------------------------------------------------------------
if ! /usr/local/bin/install-claude-code; then
    if [ -x /opt/claude-code/bin/claude ]; then
        echo "WARN: Claude Code update failed, keeping $(/opt/claude-code/bin/claude --version 2>/dev/null | head -1)" >&2
    else
        echo "WARN: Claude Code could not be installed; \`claude\` is unavailable. Check the gateway log" \
             "(claude.ai and downloads.claude.ai must be allowed)." >&2
    fi
fi

export HOME=/home/agent USER=agent LOGNAME=agent
cd /workspace

# Supplementary groups: normally reset to agent's own. With local GPU access the
# host's video/render groups are passed in (Podman GroupAdd=keep-groups, Docker
# group_add) and must be kept, otherwise /dev/dri/renderD* is not accessible.
if [ "${KEEP_GROUPS:-0}" = 1 ]; then
    GROUPS_OPT=--keep-groups
else
    GROUPS_OPT=--init-groups
fi
drop_to_agent() {
    setpriv --reuid=agent --regid=agent "$GROUPS_OPT" --inh-caps=-all -- "$@"
}

# ---------------------------------------------------------------------------
# 2. Add-ons mounted under /opt/agent-sandbox/addons/<name>/ (bin/, claude.md)
# ---------------------------------------------------------------------------
for d in /opt/agent-sandbox/addons/*/bin; do
    [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

# ---------------------------------------------------------------------------
# 3. Layer hooks (e.g. Xvfb from layers/xvfb). Sourced as root; they start
#    their own processes with drop_to_agent.
# ---------------------------------------------------------------------------
for hook in /usr/local/lib/agent-sandbox/entrypoint.d/*.sh; do
    [ -r "$hook" ] || continue
    # shellcheck source=/dev/null
    . "$hook"
done

# ---------------------------------------------------------------------------
# 4. Managed CLAUDE.md: image fragments + mounted add-on fragments. Root-owned,
#    so the agent can read but not change it.
# ---------------------------------------------------------------------------
/usr/local/bin/assemble-claude-md

exec setpriv --reuid=agent --regid=agent "$GROUPS_OPT" --inh-caps=-all -- "$@"
