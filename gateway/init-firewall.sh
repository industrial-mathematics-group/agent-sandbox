#!/bin/bash
# Egress firewall for agent-sandbox, run in the gateway BEFORE the proxy (and
# tailscaled) start. The agent container shares this network namespace and has
# no capabilities, so these rules apply to it and it can't change them.
#
# Modes (GATEWAY_MODE):
#   standard  default. Only the proxy may connect out (ports 80/443/22, public IPs
#             only); it enforces the allowlist by hostname. The agent itself can
#             only reach the proxy on 127.0.0.1.
#   strict    standard + the agent may also connect directly to the addresses the
#             allowlist resolves to at startup (+ GATEWAY_STRICT_CIDRS), for tools
#             that ignore proxy settings. Address-based, so coarse (shared CDN IPs).
#   open      like standard, but the proxy lets every public host through.
#
# Always: LAN, link-local, CGNAT/tailnet and IPv6 blocked (except the addresses in
# GATEWAY_PRIVATE_ALLOW, see below); inbound closed except GATEWAY_INBOUND_PORTS. With GATEWAY_VPN=tailscale, all egress (proxy and strict
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
# strict: look up every allowlisted name once and load the addresses into an
# ipset in one batch. Wildcard entries contribute their apex only (subdomains
# can't be enumerated); they keep working through the proxy. Extra networks
# (e.g. a provider's published ranges) can be given as GATEWAY_STRICT_CIDRS.
# ---------------------------------------------------------------------------
is_ipv4_net() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[12][0-9]|3[0-2]))?$ ]]; }
if [ "$MODE" = strict ]; then
    batch=$(mktemp)
    echo "create allowed-ips hash:net" > "$batch"
    unresolved=()
    while read -r name; do
        name=${name#\*.}
        found=0
        for addr in $(dig +short +time=3 +tries=2 A "$name" 2>/dev/null); do
            is_ipv4_net "$addr" || continue          # skips CNAME lines
            echo "add allowed-ips $addr -exist" >> "$batch"; found=1
        done
        [ "$found" = 1 ] || unresolved+=("$name")
    done < "$DOMAINS"
    IFS=' ,' read -r -a cidrs <<< "${GATEWAY_STRICT_CIDRS:-}"
    for c in "${cidrs[@]}"; do
        [ -n "$c" ] || continue
        is_ipv4_net "$c" || { echo "ERROR: GATEWAY_STRICT_CIDRS: '$c' is not an IPv4 address/network" >&2; exit 1; }
        echo "add allowed-ips $c -exist" >> "$batch"
    done
    ipset restore < "$batch"
    rm -f "$batch"
    [ ${#unresolved[@]} -eq 0 ] || echo "WARN: no IPv4 address for: ${unresolved[*]}"
    echo "strict: direct access to $(ipset list allowed-ips | grep -cE '^[0-9]') addresses/networks"
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
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
[ "$VPN" = tailscale ] && iptables -A OUTPUT -m mark --mark "$TS_BYPASS_MARK" -j ACCEPT

# DNS only to the configured resolver(s), and only for root and the proxy. These
# rules come before the loopback rule: Docker's embedded resolver (127.0.0.11)
# is on lo, and its nat rules redirect port 53 to a random port, so match the
# connection's original destination instead of the rewritten one.
resolvers=$(awk '/^nameserver/ && $2 ~ /^[0-9.]+$/ {print $2}' /etc/resolv.conf)
[ -n "$resolvers" ] || { echo "ERROR: no IPv4 nameserver in /etc/resolv.conf" >&2; exit 1; }
while read -r ns; do
    for proto in udp tcp; do
        dns=(-p "$proto" -m conntrack --ctorigdst "$ns" --ctorigdstport 53)
        if [ "$agent_dns" = 1 ]; then
            iptables -A OUTPUT "${dns[@]}" -j ACCEPT
        else
            iptables -A OUTPUT "${dns[@]}" -m owner --uid-owner 0 -j ACCEPT
            iptables -A OUTPUT "${dns[@]}" -m owner --uid-owner "$PROXY_UID" -j ACCEPT
            iptables -A OUTPUT "${dns[@]}" -j REJECT --reject-with icmp-admin-prohibited
        fi
    done
    echo "DNS via $ns$([ "$agent_dns" = 1 ] && echo ' (agent too)')"
done <<< "$resolvers"

iptables -A OUTPUT -o lo -j ACCEPT

# GATEWAY_PRIVATE_ALLOW: private addresses the proxy (and strict direct access)
# may still reach, e.g. your own services on the tailnet or LAN. The proxy's
# hostname allowlist still applies, so the host must be allowlisted as well. Name
# single addresses where you can: a wide range lets every allowlisted name that
# resolves into it through, including ones whose DNS someone else controls.
# Add-ons add theirs (*_PRIVATE_IP in their env files, collected by render-config.sh).
IFS=' ,' read -r -a private_allow <<< "${GATEWAY_PRIVATE_ALLOW:-}"
if [ -s /run/agent-gateway/private-allow ]; then
    while read -r c; do private_allow+=("$c"); done < /run/agent-gateway/private-allow
fi
private_ok=()
for c in "${private_allow[@]}"; do
    [ -n "$c" ] || continue
    is_ipv4_net "$c" || { echo "ERROR: GATEWAY_PRIVATE_ALLOW / add-on *_PRIVATE_IP: '$c' is not an IPv4 address/network" >&2; exit 1; }
    dup=0; for o in "${private_ok[@]}"; do [ "$o" != "$c" ] || dup=1; done
    [ "$dup" = 1 ] || private_ok+=("$c")
done
[ ${#private_ok[@]} -eq 0 ] || echo "Private addresses allowed: $(IFS=" "; echo "${private_ok[*]}")"

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
    for c in "${private_ok[@]}"; do
        iptables -A PROXY-OUT -d "$c" "${OUT_IF[@]}" -p tcp -m multiport --dports 80,443,22 -j ACCEPT
    done
    iptables -A PROXY-OUT -j NO-PRIVATE
    iptables -A PROXY-OUT "${OUT_IF[@]}" -p tcp -m multiport --dports 80,443,22 -j ACCEPT
fi
iptables -A PROXY-OUT -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -m owner --uid-owner "$PROXY_UID" -j PROXY-OUT

# strict: direct to the resolved allowlist
if [ "$MODE" = strict ]; then
    for c in "${private_ok[@]}"; do
        iptables -A OUTPUT -d "$c" "${OUT_IF[@]}" -m set --match-set allowed-ips dst -j ACCEPT
    done
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
