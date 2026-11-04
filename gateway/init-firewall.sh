#!/bin/bash
# Egress firewall for agent-sandbox, run in the gateway BEFORE the proxy (and
# tailscaled) start. The agent container shares this network namespace and has
# no capabilities, so these rules apply to it and it can't change them.
#
# Modes (GATEWAY_MODE):
#   standard  default. Only the proxy may connect out (ports 80/443/22, public IPs
#             only); it enforces the allowlist by hostname. The agent itself can
#             only reach the proxy on 127.0.0.1.
#   strict    standard + the agent may also connect directly to the IPs the
#             allowlist resolves to at startup (+ GitHub's published ranges), for
#             tools that ignore proxy settings. IP-based, so coarse (shared CDN IPs).
#   open      like standard, but the proxy lets every public host through.
#
# Always: LAN, link-local, CGNAT/tailnet and IPv6 blocked; inbound closed except
# GATEWAY_INBOUND_PORTS. With GATEWAY_VPN=tailscale, all egress (proxy and strict
# direct) may only leave via tailscale0, i.e. through the exit node; if the tunnel
# is down nothing gets out. tailscaled's own traffic is recognised by its fwmark.
#
# DNS: only root (tailscaled) and the proxy may query the resolver, so the agent
# can't use DNS as a side channel. strict mode or GATEWAY_AGENT_DNS=1 re-enable it
# for the agent.
set -euo pipefail
IFS=$'\n\t'

MODE=${GATEWAY_MODE:-standard}
VPN=${GATEWAY_VPN:-none}
PROXY_UID=$(id -u agentproxy)
DOMAINS=/run/agent-gateway/domains
INBOUND=${GATEWAY_INBOUND_PORTS:-${FIREWALL_INBOUND_PORTS:-}}   # old name still accepted
TS_BYPASS_MARK="0x80000/0xff0000"
PRIVATE_NETS="0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4"

case "$MODE" in standard|strict|open) ;; *) echo "ERROR: GATEWAY_MODE must be standard, strict or open (got '$MODE')" >&2; exit 1 ;; esac
case "$VPN" in
    none)      OUT_IF=() ;;
    tailscale) OUT_IF=(-o tailscale0) ;;
    *) echo "ERROR: GATEWAY_VPN must be none or tailscale (got '$VPN')" >&2; exit 1 ;;
esac
agent_dns=${GATEWAY_AGENT_DNS:-0}
[ "$MODE" = strict ] && agent_dns=1

# ---------------------------------------------------------------------------
# Reset. Only the filter table: Docker's embedded DNS (127.0.0.11) lives in
# this namespace's nat table and must survive.
# ---------------------------------------------------------------------------
iptables -F
iptables -X
ipset destroy allowed-ips 2>/dev/null || true

# ---------------------------------------------------------------------------
# strict: resolve the allowlist to IPs (+ GitHub meta ranges)
# ---------------------------------------------------------------------------
if [ "$MODE" = strict ]; then
    ipset create allowed-ips hash:net
    echo "Fetching GitHub IP ranges..."
    if gh_ranges=$(curl -fsS --connect-timeout 10 https://api.github.com/meta) \
       && echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
        n=0
        while read -r cidr; do
            [[ "$cidr" == *:* ]] && continue    # IPv6 is disabled
            [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || { echo "ERROR: bad CIDR from GitHub meta: $cidr" >&2; exit 1; }
            ipset add -exist allowed-ips "$cidr"; n=$((n + 1))
        done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | sort -u)
        echo "Allowed GitHub ($n ranges)"
    else
        echo "WARN: could not fetch GitHub meta, GitHub only via the proxy"
    fi
    while read -r d; do
        if [[ "$d" == \*.* ]]; then d=${d#\*.}; fi   # wildcards: only the apex can be resolved
        ips=$(dig +noall +answer A "$d" | awk '$4 == "A" {print $5}')
        if [ -z "$ips" ]; then echo "WARN: could not resolve $d"; continue; fi
        while read -r ip; do
            [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "ERROR: bad IP for $d: $ip" >&2; exit 1; }
            ipset add -exist allowed-ips "$ip"
        done <<< "$ips"
    done < "$DOMAINS"
    echo "strict: direct access to $(ipset list allowed-ips | grep -c '^[0-9]') IPs/ranges"
fi

# ---------------------------------------------------------------------------
# INPUT: tailscaled later inserts its own ts-input chain in front of these.
# ---------------------------------------------------------------------------
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
if [ -n "$INBOUND" ]; then
    IFS=' ,' read -r -a ports <<< "$INBOUND"
    for p in "${ports[@]}"; do
        [ -z "$p" ] && continue
        [[ "$p" =~ ^[0-9]{1,5}$ ]] || { echo "ERROR: bad inbound port '$p'" >&2; exit 1; }
        if [ "$VPN" = tailscale ]; then
            iptables -A INPUT -i tailscale0 -p tcp --dport "$p" -j ACCEPT
        else
            # Reached through ports published on the gateway container
            iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
        fi
        echo "Inbound: tcp/$p"
    done
fi
iptables -P INPUT DROP
iptables -P FORWARD DROP

# ---------------------------------------------------------------------------
# OUTPUT
# ---------------------------------------------------------------------------
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
[ "$VPN" = tailscale ] && iptables -A OUTPUT -m mark --mark "$TS_BYPASS_MARK" -j ACCEPT

# DNS only to the configured resolver(s)
resolvers=$(awk '/^nameserver/ && $2 ~ /^[0-9.]+$/ {print $2}' /etc/resolv.conf)
[ -n "$resolvers" ] || { echo "ERROR: no IPv4 nameserver in /etc/resolv.conf" >&2; exit 1; }
while read -r ns; do
    for proto in udp tcp; do
        if [ "$agent_dns" = 1 ]; then
            iptables -A OUTPUT -d "$ns" -p "$proto" --dport 53 -j ACCEPT
        else
            iptables -A OUTPUT -d "$ns" -p "$proto" --dport 53 -m owner --uid-owner 0 -j ACCEPT
            iptables -A OUTPUT -d "$ns" -p "$proto" --dport 53 -m owner --uid-owner "$PROXY_UID" -j ACCEPT
        fi
    done
    echo "DNS via $ns$([ "$agent_dns" = 1 ] && echo ' (agent too)')"
done <<< "$resolvers"

# Never to private / special ranges (LAN, router, tailnet peers, metadata service)
iptables -N NO-PRIVATE
for net in ${PRIVATE_NETS// /$'\n'}; do
    iptables -A NO-PRIVATE -d "$net" -j REJECT --reject-with icmp-admin-prohibited
done

# The proxy: public IPs, http/https/ssh only. With an upstream proxy: only that.
iptables -N PROXY-OUT
if [ -n "${GATEWAY_UPSTREAM_PROXY:-}" ]; then
    up_host=${GATEWAY_UPSTREAM_PROXY%:*} up_port=${GATEWAY_UPSTREAM_PROXY##*:}
    if [[ "$up_host" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then up_ips=$up_host
    else up_ips=$(dig +short A "$up_host" | grep -E '^[0-9.]+$' || true); fi
    [ -n "$up_ips" ] || { echo "ERROR: cannot resolve upstream proxy $up_host" >&2; exit 1; }
    while read -r ip; do
        iptables -A PROXY-OUT -d "$ip" -p tcp --dport "$up_port" -j ACCEPT
    done <<< "$up_ips"
    echo "Upstream proxy: $GATEWAY_UPSTREAM_PROXY"
else
    iptables -A PROXY-OUT -j NO-PRIVATE
    iptables -A PROXY-OUT "${OUT_IF[@]}" -p tcp -m multiport --dports 80,443,22 -j ACCEPT
fi
iptables -A PROXY-OUT -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -m owner --uid-owner "$PROXY_UID" -j PROXY-OUT

# strict: direct to the resolved allowlist
if [ "$MODE" = strict ]; then
    iptables -A OUTPUT -j NO-PRIVATE
    iptables -A OUTPUT "${OUT_IF[@]}" -m set --match-set allowed-ips dst -j ACCEPT
fi

iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
iptables -P OUTPUT DROP

# IPv6 is disabled via sysctl; also drop it here if ip6tables works
if ip6tables -L -n >/dev/null 2>&1; then
    ip6tables -F
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -P INPUT DROP
    ip6tables -A OUTPUT -o lo -j ACCEPT
    [ "$VPN" = tailscale ] && ip6tables -A OUTPUT -m mark --mark "$TS_BYPASS_MARK" -j ACCEPT
    ip6tables -P OUTPUT DROP
    ip6tables -P FORWARD DROP
fi

echo "Firewall installed (mode $MODE, egress $([ "$VPN" = tailscale ] && echo 'only via tailscale0' || echo 'direct'))."
