#!/bin/bash
# Gateway entrypoint: allowlist + proxy config, firewall, then the proxy,
# (Tailscale variant) tailscaled and (github-app add-on) the token broker. The
# agent container waits for the proxy port, which only opens after the firewall is
# in place. If one of them dies, the container exits, so the agent loses its
# network (fails closed) and the service manager restarts both.
set -euo pipefail

VPN=${GATEWAY_VPN:-none}
if [ "$VPN" = none ] && [ "${GATEWAY_VARIANT:-plain}" = tailscale ] && [ -n "${TS_AUTHKEY:-}${TS_EXIT_NODE:-}" ]; then
    VPN=tailscale
fi
export GATEWAY_VPN=$VPN

if [ "$VPN" = tailscale ]; then
    command -v containerboot >/dev/null || { echo "ERROR: GATEWAY_VPN=tailscale needs the tailscale gateway image" >&2; exit 1; }
    if [[ ! "${TS_EXIT_NODE:-}" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: TS_EXIT_NODE must be the exit node's Tailscale IPv4 (100.x.y.z)," >&2
        echo "       got '${TS_EXIT_NODE:-}'. Hostnames don't work at startup." >&2
        exit 1
    fi
    # allow-lan-access keeps DNS to the container runtime's resolver on the local bridge
    export TS_EXTRA_ARGS="--exit-node=$TS_EXIT_NODE --exit-node-allow-lan-access=true ${TS_EXTRA_ARGS:-}"
    export TS_USERSPACE=${TS_USERSPACE:-false} TS_ACCEPT_DNS=${TS_ACCEPT_DNS:-false}
    export TS_STATE_DIR=${TS_STATE_DIR:-/var/lib/tailscale}
fi

/usr/local/bin/render-config.sh
/usr/local/bin/init-firewall.sh

pids=()
# github-app add-on: token broker on 127.0.0.1:3129, before the proxy opens (the
# agent's start-up hook asks it once the proxy answers). A broken setup only
# costs the add-on: the gateway log says why and the agent warns.
if [ -f /etc/agent-sandbox/addons/github-app.env ]; then
    if /usr/local/bin/github-app-broker prepare; then
        /usr/local/bin/github-app-broker serve &
        pids+=("$!")
    fi
fi

tinyproxy -d -c /run/agent-gateway/tinyproxy.conf &
proxy_pid=$!
for _ in $(seq 50); do
    (exec 3<>"/dev/tcp/127.0.0.1/${GATEWAY_PROXY_PORT:-3128}") 2>/dev/null && break
    sleep 0.1
done
echo "Gateway ready: proxy on 127.0.0.1:${GATEWAY_PROXY_PORT:-3128}, mode ${GATEWAY_MODE:-standard}, vpn $VPN"

pids+=("$proxy_pid")
if [ "$VPN" = tailscale ]; then
    /usr/local/bin/containerboot &
    pids+=("$!")
fi
trap 'kill "${pids[@]}" 2>/dev/null || true' TERM INT
set +e
wait -n "${pids[@]}"
rc=$?
echo "Gateway: a component exited (rc=$rc), stopping." >&2
kill "${pids[@]}" 2>/dev/null
exit "$rc"
