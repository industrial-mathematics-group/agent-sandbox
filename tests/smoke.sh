#!/usr/bin/env bash
# Smoke test: start gateway + agent with Compose and check the network policy
# from inside the agent. Used by CI; works locally with Docker.
#
#   tests/smoke.sh [FLAVOR] [REGISTRY]      (default: minimal localhost)
#   TAG_SUFFIX=-amd64 GATEWAY_TAG=latest    tag overrides (CI)
#   SMOKE_CODEX=1                           also the codex add-on (default: only for minimal;
#                                           it downloads ~170 MB)
#
# Always with the claude-code add-on. Without codex, OpenAI must be unreachable.
set -euo pipefail
cd "$(dirname "$0")/../deploy/compose"

FLAVOR=${1:-minimal}
REGISTRY=${2:-localhost}
TAG_SUFFIX=${TAG_SUFFIX:-}
WORKSPACE=$(mktemp -d)
chmod 777 "$WORKSPACE"
export SANDBOX_NAME=smoke FLAVOR="$FLAVOR$TAG_SUFFIX" REGISTRY GATEWAY_TAG="${GATEWAY_TAG:-latest}" WORKSPACE PORT_1=3999 PORTS=3999 CPUS=1 MEMORY=4g   # limits that fit any runner
SMOKE_CODEX=${SMOKE_CODEX:-$([ "$FLAVOR" = minimal ] && echo 1 || echo 0)}
cp gateway.env.example gateway.env; cp sandbox.env.example sandbox.env; : > extra.list
cp ../../addons/claude-code/claude-code.env.example claude-code.env
files=(-f compose.yaml -f ../../addons/claude-code/compose.yaml)
if [ "$SMOKE_CODEX" = 1 ]; then
    cp ../../addons/codex/codex.env.example codex.env
    CODEX_CONFIG=$(mktemp -d); chmod 777 "$CODEX_CONFIG"; export CODEX_CONFIG
    files+=(-f ../../addons/codex/compose.yaml)
fi
# Add-on files are read as agent (uid 1000) inside
chmod 644 ./*.env
chmod -R a+rX ../../addons
dc() { docker compose -p smoke "${files[@]}" "$@"; }
show_logs() { echo "--- compose ps"; dc ps -a || true; echo "--- compose logs"; dc logs --no-color | tail -"${1:-50}" || true; }
cleanup() { dc down -v >/dev/null 2>&1 || true; rm -f gateway.env sandbox.env extra.list claude-code.env codex.env; }
trap cleanup EXIT

if ! dc up -d; then
    echo "FAIL  compose up"
    show_logs 80
    exit 1
fi
for _ in $(seq 150); do
    dc logs agent 2>/dev/null | grep -q "Sandbox ready" && break   # after the agent CLI installs
    if ! dc ps --status running --services | grep -q agent; then break; fi
    sleep 2
done
dc logs agent | tail -8

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
check "claude CLI (add-on)"          ok      claude --version
check "claude CLI not replaceable"   blocked test -w /opt/claude-code/bin
check "managed CLAUDE.md readable"   ok      test -r /etc/claude-code/CLAUDE.md
check "managed CLAUDE.md read-only"  blocked test -w /etc/claude-code/CLAUDE.md
check "add-on notes in CLAUDE.md"    ok      grep -q '^## Claude Code' /etc/claude-code/CLAUDE.md
if [ "$SMOKE_CODEX" = 1 ]; then
    check "codex CLI (add-on)"           ok      codex --version
    check "OpenAI API via proxy"         ok      curl -s -o /dev/null --max-time 15 https://api.openai.com
    check "codex system config"          ok      grep -q '^sandbox_mode = "danger-full-access"' /etc/codex/config.toml
    check "~/.codex writable"            ok      touch /home/agent/.codex/.smoke
else
    check "OpenAI without codex add-on"  blocked curl -sf -o /dev/null --max-time 15 https://api.openai.com
fi

if [ "$fail" = 1 ]; then
    show_logs
    exit 1
fi
echo "Smoke test passed for $FLAVOR."
