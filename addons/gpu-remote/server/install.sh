#!/bin/bash
# Installs the Claude GPU gateway for the current user. No root needed.
#
#   ./install.sh "ssh-ed25519 AAAA... claude-sandbox" [VPS_PUBLIC_IP]
#
# - bubblewrap: unpacked from the distribution's own package into ~/.local/lib
# - gateway:    ~/.local/bin/claude-gpu-gateway
# - config:     ~/.config/claude-gpu/config (edit limits there)
# - prints the authorized_keys line to add (it does NOT edit the file for you)
set -euo pipefail

PUBKEY=${1:?usage: $0 \"<sandbox public key>\" [vps-ip]}
VPS_IP=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=$HOME/.local/lib/claude-gpu
BWRAP=$PREFIX/bwrap/usr/bin/bwrap
CONF_DIR=$HOME/.config/claude-gpu

[[ "$PUBKEY" =~ ^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa)\ [A-Za-z0-9+/=]+ ]] \
    || { echo "That doesn't look like a public key: $PUBKEY" >&2; exit 1; }

mkdir -p "$PREFIX" "$HOME/.local/bin" "$CONF_DIR"

# --- bubblewrap -------------------------------------------------------------
if [ -x "$BWRAP" ]; then
    echo "bubblewrap already installed: $("$BWRAP" --version)"
elif command -v bwrap >/dev/null; then
    BWRAP=$(command -v bwrap); echo "Using system bubblewrap: $BWRAP"
else
    echo "Fetching bubblewrap from the distribution's package (no root needed) ..."
    tmp=$(mktemp -d)
    (cd "$tmp" && apt-get download bubblewrap >/dev/null)
    dpkg-deb -x "$tmp"/bubblewrap_*.deb "$PREFIX/bwrap"
    rm -rf "$tmp"
    echo "Installed $("$BWRAP" --version)"
fi

# --- gateway + config ---------------------------------------------------------
install -m 0755 "$HERE/claude-gpu-gateway" "$HOME/.local/bin/claude-gpu-gateway"

use_systemd=0
if systemd-run --user --scope --quiet -p MemoryMax=1G true 2>/dev/null; then
    use_systemd=1
fi
if [ ! -f "$CONF_DIR/config" ]; then
    cat > "$CONF_DIR/config" <<EOF
# Claude GPU gateway settings (sourced by ~/.local/bin/claude-gpu-gateway)
BASE=/tmp/\$USER-claude-gpu          # project copies + Julia depot (local disk)
BWRAP=$BWRAP
JULIA=$(command -v julia)
PKG_SERVER=https://pkg.julialang.org
TIMEOUT_RUN=3600                    # seconds per test/run
TIMEOUT_SETUP=3600                  # seconds per instantiate
USE_SYSTEMD=$use_systemd                       # 1 = enforce MEMORY_MAX via systemd-run --user
MEMORY_MAX=64G
JULIA_THREADS=8
EOF
    echo "Wrote $CONF_DIR/config (USE_SYSTEMD=$use_systemd)"
else
    echo "Keeping existing $CONF_DIR/config"
fi

# --- self-test ------------------------------------------------------------------
echo
echo "Self-test: sandbox without network, GPU visible, home hidden ..."
. "$CONF_DIR/config"
"$BWRAP" --unshare-all --die-with-parent --ro-bind /usr /usr \
    $(for p in /bin /sbin /lib /lib64; do [ -L "$p" ] && echo "--symlink $(readlink "$p") $p"; done) \
    --proc /proc --dev /dev --tmpfs /tmp \
    $(for d in /dev/nvidia*; do [ -e "$d" ] && echo "--dev-bind $d $d"; done) \
    --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache \
    -- /bin/bash -c '
        nvidia-smi -L | head -1
        if [ -e "'"$HOME"'" ]; then echo "FAIL: home visible"; exit 1; else echo "home hidden: ok"; fi
        if timeout 3 bash -c "echo > /dev/tcp/1.1.1.1/443" 2>/dev/null; then
            echo "FAIL: network reachable"; exit 1
        else echo "no network: ok"; fi
    '

# --- authorized_keys line -------------------------------------------------------
opts="restrict"
[ -n "$VPS_IP" ] && opts="$opts,from=\"$VPS_IP\""
opts="$opts,command=\"$HOME/.local/bin/claude-gpu-gateway\""
echo
echo "Add this ONE line to ~/.ssh/authorized_keys (keep the key on a single line):"
echo
echo "$opts $PUBKEY"
echo
echo "It limits the key to the gateway: no shell, no port/agent/X11 forwarding."
[ -z "$VPS_IP" ] && echo "Tip: pass your VPS's public IP as 2nd argument to also add from=\"...\"."
exit 0
