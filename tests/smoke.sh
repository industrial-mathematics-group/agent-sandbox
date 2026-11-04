#!/usr/bin/env bash
# Smoke test: start gateway + agent with Compose and check the network policy
# from inside the agent. Used by CI; works locally with Docker.
#
#   tests/smoke.sh [FLAVOR] [REGISTRY]      (default: minimal localhost)
#   TAG_SUFFIX=-amd64 GATEWAY_TAG=latest    tag overrides (CI)
set -euo pipefail
cd "$(dirname "$0")/../deploy/compose"

FLAVOR=${1:-minimal}
REGISTRY=${2:-localhost}
TAG_SUFFIX=${TAG_SUFFIX:-}
WORKSPACE=$(mktemp -d)
chmod 777 "$WORKSPACE"
export SANDBOX_NAME=smoke FLAVOR="$FLAVOR$TAG_SUFFIX" REGISTRY GATEWAY_TAG="${GATEWAY_TAG:-latest}" WORKSPACE PORT_1=3999 PORTS=3999 CPUS=1 MEMORY=4g   # limits that fit any runner
tmp=$(mktemp -d)
cp gateway.env.example gateway.env; cp sandbox.env.example sandbox.env; : > extra.list
dc() { docker compose -p smoke "$@"; }
cleanup() { dc logs --no-color > "$tmp/compose.log" 2>&1 || true; dc down -v >/dev/null 2>&1 || true; rm -f gateway.env sandbox.env extra.list; }
trap cleanup EXIT

dc up -d
for _ in $(seq 90); do
    dc logs agent 2>/dev/null | grep -q "Network ready" && break
    if ! dc ps --status running --services | grep -q agent; then break; fi
    sleep 2
done
dc logs agent | tail -5

fail=0
check() {   # check <description> <expected: ok|blocked> <command...>
    local what=$1 want=$2; shift 2
    if dc exec -T -u agent agent "$@" >/dev/null 2>&1; then got=ok; else got=blocked; fi
    if [ "$got" = "$want" ]; then echo "PASS  $what ($got)"; else echo "FAIL  $what (expected $want, got $got)"; fail=1; fi
}
check "Anthropic API via proxy"      ok      curl -s -o /dev/null --max-time 15 https://api.anthropic.com
check "GitHub via proxy"             ok      curl -sf -o /dev/null --max-time 15 https://api.github.com/zen
check "non-allowlisted host"         blocked curl -sf -o /dev/null --max-time 15 https://example.com
check "direct connection (no proxy)" blocked curl --noproxy '*' -s -o /dev/null --max-time 8 https://1.1.1.1
check "LAN / metadata address"       blocked curl -sf -o /dev/null --max-time 8 http://169.254.169.254
check "agent DNS"                    blocked getent hosts example.com
check "claude CLI"                   ok      claude --version
check "managed CLAUDE.md readable"   ok      test -r /etc/claude-code/CLAUDE.md
check "managed CLAUDE.md read-only"  blocked test -w /etc/claude-code/CLAUDE.md

if [ "$fail" = 1 ]; then
    echo "--- compose logs"; dc logs --no-color | tail -50
    exit 1
fi
echo "Smoke test passed for $FLAVOR."
