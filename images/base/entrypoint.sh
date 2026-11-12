#!/bin/bash
# agent-sandbox entrypoint. The network (proxy + firewall, optionally a VPN) is
# owned by the gateway sidecar; this container has no network capabilities.
# Runs as (container) root only long enough to check the network, assemble the
# agent notes and run the layer and add-on hooks (which install the coding agent
# CLIs, see addons/claude-code and addons/codex), then drops to `agent` for good.
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
    # GitHub is on the gateway's base list; the agents' own hosts come from their add-ons
    require_reachable https://api.github.com
    echo "Network ready (egress only through the gateway)."
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
# 2. Add-ons mounted under /opt/agent-sandbox/addons/<name>/ (bin/, claude.md,
#    entrypoint.d/). The mounts belong to the host user (= agent) and are
#    usually mode 0700, and this root has no CAP_DAC_OVERRIDE (all capabilities
#    are dropped), so it can't look inside them: list and read them as agent.
#
#    Commands are linked into /opt/agent-sandbox/bin, which is on the image
#    PATH: a PATH set here would reach only this process, not the shells and
#    `claude` sessions started later with `podman exec` / `docker exec`.
# ---------------------------------------------------------------------------
addon_files() {   # addon_files <find -path pattern> [find tests...]: NUL-separated, sorted
    local pattern=$1; shift
    drop_to_agent find /opt/agent-sandbox/addons/ -mindepth 3 -maxdepth 3 -path "$pattern" "$@" -print0 2>/dev/null \
        | sort -z
}
install -d -m 0755 /opt/agent-sandbox/bin
find /opt/agent-sandbox/bin -mindepth 1 -maxdepth 1 -type l -delete
mapfile -d '' -t addon_bins < <(addon_files '*/bin/*' \( -type f -o -type l \) -executable)
for f in "${addon_bins[@]}"; do
    ln -sfn "$f" "/opt/agent-sandbox/bin/${f##*/}"
done
if compgen -G '/opt/agent-sandbox/addons/*' >/dev/null && [ "${#addon_bins[@]}" = 0 ]; then
    echo "WARN: add-ons are mounted under /opt/agent-sandbox/addons, but agent can't run any" \
         "command in their bin/. Check the host folder's owner and permissions" \
         "(SELinux host: keep the :z label on the add-on volume)." >&2
fi
unset addon_bins

# Claude Code used to be part of the image; it is the claude-code add-on now. An
# instance set up before still mounts its volume but not the add-on.
if [ ! -d /opt/agent-sandbox/addons/claude-code ] && mountpoint -q /opt/claude-code 2>/dev/null; then
    echo "WARN: Claude Code is an add-on now and this instance doesn't mount it, so \`claude\` is" \
         "not installed. Rerun deploy/quadlet/setup.sh with your options (it adds the add-on by" \
         "default), or add -f ../../addons/claude-code/compose.yaml (see addons/claude-code/README.md)." >&2
fi

# ---------------------------------------------------------------------------
# 3. Agent notes: image fragments + mounted add-on fragments, assembled into the
#    root-owned /etc/agent-sandbox/AGENTS.md before the hooks, which hand it to
#    the agent CLIs (claude-code: /etc/claude-code/CLAUDE.md).
# ---------------------------------------------------------------------------
/usr/local/bin/assemble-agent-md

# ---------------------------------------------------------------------------
# 4. Layer hooks (e.g. Xvfb from layers/xvfb). Sourced as root; they start
#    their own processes with drop_to_agent. Add-ons can ship their own
#    (/opt/agent-sandbox/addons/<name>/entrypoint.d/), e.g. claude-code and codex
#    install their CLI, git-remote writes /etc/gitconfig, notify installs Claude
#    Code hooks; those are read as agent and run as root.
# ---------------------------------------------------------------------------
for hook in /usr/local/lib/agent-sandbox/entrypoint.d/*.sh; do
    [ -r "$hook" ] || continue
    # shellcheck source=/dev/null
    . "$hook"
done
mapfile -d '' -t addon_hooks < <(addon_files '*/entrypoint.d/*.sh' -type f)
for hook in "${addon_hooks[@]}"; do
    if ! hook_src=$(drop_to_agent cat "$hook"); then
        echo "WARN: $hook is not readable by agent; skipped." >&2
        continue
    fi
    eval "$hook_src"
done
unset addon_hooks hook_src

echo "Sandbox ready."
exec setpriv --reuid=agent --regid=agent "$GROUPS_OPT" --inh-caps=-all -- "$@"
