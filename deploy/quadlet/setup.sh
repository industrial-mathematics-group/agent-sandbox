#!/bin/bash
# Installs an agent-sandbox instance as rootless Podman Quadlet units (systemd user
# services), by default under a dedicated sandbox user. Run as YOUR normal user;
# it uses sudo where needed.
#
#   ./setup.sh [options]
#
#   --name NAME          instance name (default: agent). One instance = one gateway +
#                        one agent container; run several for several projects.
#   --flavor FLAVOR      image flavor: minimal node node-chromium python python-gui
#                        julia julia-gui octave octave-gui full full-rocm (default: full)
#   --workspace DIR      host folder mounted as /workspace
#                        (default: /var/srv/agent-sandbox/<name>)
#   --net plain|tailscale   egress directly (default) or only via a Tailscale exit node
#   --mode standard|strict|open   gateway filter mode (default: standard)
#   --profiles LIST      allowlists besides base (default: from the flavor, e.g. node,python,julia)
#   --port N             publish/open a TCP port for dev servers (repeatable).
#                        plain: published on 127.0.0.1:N of the host; tailscale: open on the tailnet
#   --gpu amd|nvidia     local GPU (amd switches to the -rocm image)
#   --addon NAME         add-on: claude-code, codex, gpu-remote, slurm, git-remote, notify,
#                        github-app (repeatable). Its hosts are allowlisted in the gateway automatically.
#                        claude-code is added unless claude-code or codex is given.
#   --claude-config SRC  ~/.claude of the claude-code add-on: a named volume or an absolute
#                        host folder (default: volume agent-sandbox-claude, shared by instances)
#   --codex-config SRC   ~/.codex of the codex add-on: an absolute host folder or a named
#                        volume (default: ~SANDBOX_USER/.config/agent-sandbox/codex, shared)
#   --memory SIZE --cpus N   container limits (default: 16g, min(8, nproc))
#   --registry REG       image registry (default: $AGENT_SANDBOX_REGISTRY or ghcr.io/OWNER;
#                        use "localhost" for images built with ./build.sh)
#   --sandbox-user USER  run the containers as this user (default: agent-sandbox;
#                        "$USER" = your own account, no isolation between you and it)
#   --no-host-setup      skip subuids/linger/groups/ACL/SELinux steps
#   --dry-run            print what would be written, change nothing
#
# Example: a web project with a Vite dev server
#   ./setup.sh --name web --flavor node-chromium --workspace ~/code/site --port 5173
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

NAME=agent
FLAVOR=full
WORKSPACE=
NET=plain
MODE=standard
PROFILES=
PORTS=()
GPU=
ADDONS=()
CLAUDE_CONFIG=agent-sandbox-claude
CODEX_CONFIG=
MEMORY=16g
CPUS=$(n=$(nproc 2>/dev/null || echo 8); [ "$n" -lt 8 ] && echo "$n" || echo 8)   # 8, or fewer on smaller hosts
REGISTRY=${AGENT_SANDBOX_REGISTRY:-ghcr.io/OWNER}
SANDBOX_USER=agent-sandbox
HOST_SETUP=1
DRY=0

usage() { sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
    case "$1" in
        --name)         NAME=$2; shift 2 ;;
        --flavor)       FLAVOR=$2; shift 2 ;;
        --workspace)    WORKSPACE=$2; shift 2 ;;
        --net)          NET=$2; shift 2 ;;
        --mode)         MODE=$2; shift 2 ;;
        --profiles)     PROFILES=$2; shift 2 ;;
        --port)         PORTS+=("$2"); shift 2 ;;
        --gpu)          GPU=$2; shift 2 ;;
        --addon)        ADDONS+=("$2"); shift 2 ;;
        --claude-config) CLAUDE_CONFIG=$2; shift 2 ;;
        --codex-config) CODEX_CONFIG=$2; shift 2 ;;
        --memory)       MEMORY=$2; shift 2 ;;
        --cpus)         CPUS=$2; shift 2 ;;
        --registry)     REGISTRY=$2; shift 2 ;;
        --sandbox-user) SANDBOX_USER=$2; shift 2 ;;
        --no-host-setup) HOST_SETUP=0; shift ;;
        --dry-run)      DRY=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "$NAME" =~ ^[a-z][a-z0-9-]{0,30}$ ]] || die "--name: lowercase letters, digits and '-' only"
case "$FLAVOR" in minimal|node|node-chromium|python|python-gui|julia|julia-gui|octave|octave-gui|full|full-rocm) ;; *) die "unknown flavor $FLAVOR" ;; esac
case "$NET" in plain|tailscale) ;; *) die "--net must be plain or tailscale" ;; esac
case "$MODE" in standard|strict|open) ;; *) die "--mode must be standard, strict or open" ;; esac
case "$GPU" in ""|amd|nvidia) ;; *) die "--gpu must be amd or nvidia" ;; esac
for a in "${ADDONS[@]}"; do
    case "$a" in claude-code|codex|gpu-remote|slurm|git-remote|notify|github-app) ;;
        *) die "unknown add-on $a (claude-code, codex, gpu-remote, slurm, git-remote, notify, github-app)" ;; esac
done
# A sandbox without a coding agent is rarely what you want: Claude Code by default
case " ${ADDONS[*]} " in
    *" claude-code "*|*" codex "*) ;;
    *) echo "NOTE: no agent add-on given (--addon claude-code / codex); adding claude-code."
       ADDONS=(claude-code "${ADDONS[@]}") ;;
esac
# Sorted and unique, so drop-ins and messages come in a stable order
mapfile -t ADDONS < <(printf '%s\n' "${ADDONS[@]}" | sort -u)
has_addon() { case " ${ADDONS[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
config_src_ok() { [[ "$1" =~ ^/[^:,[:space:]]*$ || "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; }
config_src_ok "$CLAUDE_CONFIG" || die "--claude-config: a volume name or an absolute path without ':' or ','"
[ -z "$CODEX_CONFIG" ] || config_src_ok "$CODEX_CONFIG" || die "--codex-config: a volume name or an absolute path without ':' or ','"
for p in "${PORTS[@]}"; do [[ "$p" =~ ^[0-9]{1,5}$ ]] || die "bad port $p"; done
[ "$REGISTRY" != ghcr.io/OWNER ] || die "set --registry (or AGENT_SANDBOX_REGISTRY), e.g. ghcr.io/<owner> or localhost"

# Image + default allowlists from the flavor
base_flavor=${FLAVOR%-rocm}
IMAGE=$REGISTRY/agent-sandbox:$FLAVOR
IMAGE_ROCM=$REGISTRY/agent-sandbox:$base_flavor-rocm
[ "$GPU" = amd ] && [ "$base_flavor" != full ] && echo "NOTE: only full-rocm is prebuilt; build $base_flavor-rocm yourself (see build.sh) or use --flavor full."
if [ -z "$PROFILES" ]; then
    case "$base_flavor" in
        minimal)          PROFILES= ;;
        node|node-*)      PROFILES=node ;;
        python|python-*)  PROFILES=python ;;
        julia|julia-*)    PROFILES=julia ;;
        octave|octave-*)  PROFILES=octave ;;
        full)             PROFILES=node,python,julia ;;
    esac
fi
LANG_VOLUMES=()
case "$base_flavor" in node*|full) LANG_VOLUMES+=("Volume=agent-sandbox-npm:/home/agent/.npm") ;; esac
case "$base_flavor" in python*|full) LANG_VOLUMES+=("Volume=agent-sandbox-uv-python:/home/agent/.local/share/uv") ;; esac
case "$base_flavor" in julia*|full) LANG_VOLUMES+=("Volume=agent-sandbox-julia-depot:/home/agent/.julia") ;; esac
case "$base_flavor" in octave*) LANG_VOLUMES+=("Volume=agent-sandbox-octave:/home/agent/.local/share/octave") ;; esac

# Users and paths
ME=$(id -un)
[ "$ME" != root ] || die "run as your normal user, not root"
id "$SANDBOX_USER" >/dev/null 2>&1 || die "user $SANDBOX_USER does not exist (create it first, e.g. sudo useradd -m $SANDBOX_USER)"
SB_HOME=$(getent passwd "$SANDBOX_USER" | cut -d: -f6)
SAME_USER=0; [ "$SANDBOX_USER" = "$ME" ] && SAME_USER=1
WORKSPACE=${WORKSPACE:-/var/srv/agent-sandbox/$NAME}
WORKSPACE=$(realpath -m "$WORKSPACE")
UNIT_DIR=$SB_HOME/.config/containers/systemd
CONFIG_DIR=$SB_HOME/.config/agent-sandbox/$NAME
ADDON_DIR=$SB_HOME/.config/agent-sandbox/addons
CODEX_CONFIG=${CODEX_CONFIG:-$SB_HOME/.config/agent-sandbox/codex}
# Host folders get the shared SELinux label (several instances mount them); named
# volumes need none. In units, the sandbox user's home is written as %h.
mount_src() { case "$1" in /*) printf '%s' "${1/#$SB_HOME/%h}" ;; *) printf '%s' "$1" ;; esac; }
mount_opts() { case "$1" in /*) printf ':z' ;; esac; }

# Run as the sandbox user's file owner (sudo unless it's you)
run() { if [ "$DRY" = 1 ]; then echo "  + $*"; else "$@"; fi; }
as_root() { if [ "$DRY" = 1 ]; then echo "  + sudo $*"; else sudo "$@"; fi; }
install_file() {   # install_file <mode> <src> <dst>
    if [ "$DRY" = 1 ]; then echo "  write $3"; return; fi
    if [ "$SAME_USER" = 1 ]; then install -m "$1" "$2" "$3"
    else sudo install -o "$SANDBOX_USER" -g "$SANDBOX_USER" -m "$1" "$2" "$3"; fi
}
make_dir() {
    if [ "$DRY" = 1 ]; then echo "  mkdir $*"; return; fi
    if [ "$SAME_USER" = 1 ]; then install -d -m 700 "$@"
    else sudo install -d -o "$SANDBOX_USER" -g "$SANDBOX_USER" -m 700 "$@"; fi
}
exists() { if [ "$SAME_USER" = 1 ]; then test -e "$1"; else sudo test -e "$1"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
render() {   # render <template> <out>: fill in @VARS@
    local publish=() ports_csv
    if [ "$NET" = plain ]; then
        for p in "${PORTS[@]}"; do publish+=("PublishPort=127.0.0.1:$p:$p"); done
    fi
    ports_csv=$(IFS=' '; echo "${PORTS[*]}")
    awk -v name="$NAME" -v flavor="$FLAVOR" -v image="$IMAGE" -v image_rocm="$IMAGE_ROCM" \
        -v gw="$REGISTRY/agent-sandbox-gateway:latest" -v gwts="$REGISTRY/agent-sandbox-gateway:tailscale" \
        -v config="${CONFIG_DIR/#$SB_HOME/%h}" -v addon="${ADDON_DIR/#$SB_HOME/%h}" \
        -v ws="$WORKSPACE" -v mem="$MEMORY" -v cpus="$CPUS" -v profiles="$PROFILES" -v ports="$ports_csv" \
        -v claudecfg="$(mount_src "$CLAUDE_CONFIG")" -v claudeopts="$(mount_opts "$CLAUDE_CONFIG")" \
        -v codexcfg="$(mount_src "$CODEX_CONFIG")" -v codexopts="$(mount_opts "$CODEX_CONFIG")" \
        -v publish="$(printf '%s\n' "${publish[@]}")" -v langvols="$(printf '%s\n' "${LANG_VOLUMES[@]}")" '
        $0 == "@PUBLISH_PORTS@" { if (publish != "") printf "%s\n", publish; else print "# (none)"; next }
        $0 == "@LANG_VOLUMES@" { if (langvols != "") printf "%s\n", langvols; next }
        { gsub(/@NAME@/, name); gsub(/@FLAVOR@/, flavor); gsub(/@IMAGE_ROCM@/, image_rocm); gsub(/@IMAGE@/, image)
          gsub(/@GATEWAY_TS_IMAGE@/, gwts); gsub(/@GATEWAY_IMAGE@/, gw)
          gsub(/@CONFIG_DIR@/, config); gsub(/@ADDON_DIR@/, addon); gsub(/@WORKSPACE@/, ws)
          gsub(/@MEMORY@/, mem); gsub(/@CPUS@/, cpus); gsub(/@PROFILES@/, profiles); gsub(/@INBOUND_PORTS@/, ports)
          gsub(/@CLAUDE_CONFIG_OPTS@/, claudeopts); gsub(/@CLAUDE_CONFIG@/, claudecfg)
          gsub(/@CODEX_CONFIG_OPTS@/, codexopts); gsub(/@CODEX_CONFIG@/, codexcfg)
          print }' "$1" > "$2"
}

echo "== agent-sandbox instance '$NAME'"
echo "   image $IMAGE, net $NET, mode $MODE, profiles base${PROFILES:+,$PROFILES}"
echo "   workspace $WORKSPACE, sandbox user $SANDBOX_USER${GPU:+, gpu $GPU}${ADDONS[*]:+, add-ons ${ADDONS[*]}}"

# Quadlet drop-ins and Network=<name>.container need Podman >= 5.0
if command -v podman >/dev/null; then
    pv=$(podman version --format '{{.Client.Version}}' 2>/dev/null || echo 0)
    [ "${pv%%.*}" -ge 5 ] 2>/dev/null || echo "WARNING: Podman $pv found; these units need Podman >= 5.0 (or use deploy/compose)."
fi

# ---------------------------------------------------------------------------
# Host setup (once per sandbox user; safe to repeat)
# ---------------------------------------------------------------------------
if [ "$HOST_SETUP" = 1 ]; then
    for tool in setfacl loginctl; do
        command -v "$tool" >/dev/null || die "missing '$tool'. On Debian/Ubuntu: sudo apt install acl systemd-container"
    done
    echo "== Host setup"
    # Subordinate UID/GID range for rootless podman. Must NOT overlap with yours,
    # otherwise the two users could access each other's container files.
    for f in subuid subgid; do
        if ! grep -q "^$SANDBOX_USER:" "/etc/$f"; then
            start=$(awk -F: '{e=$2+$3; if (e>m) m=e} END {print (m>524288 ? m : 524288)}' "/etc/$f")
            echo "   adding $f range $start-$((start + 65535))"
            if [ "$f" = subuid ]; then as_root usermod --add-subuids "$start-$((start + 65535))" "$SANDBOX_USER"
            else as_root usermod --add-subgids "$start-$((start + 65535))" "$SANDBOX_USER"; fi
        fi
    done
    [ "$GPU" = amd ] && as_root usermod -aG video,render "$SANDBOX_USER"
    as_root loginctl enable-linger "$SANDBOX_USER"
    if [ "$SAME_USER" = 0 ]; then
        perm=$(stat -c %a "$HOME")
        [ "${perm: -1}" = 0 ] || echo "WARNING: your home $HOME is mode $perm, readable by other users. Consider: chmod 700 $HOME"
    fi

    echo "== Workspace $WORKSPACE"
    if [ ! -d "$WORKSPACE" ]; then
        as_root mkdir -p "$WORKSPACE"
        as_root chown "$SANDBOX_USER:$SANDBOX_USER" "$WORKSPACE"
        as_root chmod 2770 "$WORKSPACE"
    fi
    if [ "$SAME_USER" = 0 ]; then
        # Both users get rwX now and on everything created later (default ACLs)
        as_root setfacl -R -m "u:$ME:rwX,u:$SANDBOX_USER:rwX,m::rwX" "$WORKSPACE"
        as_root setfacl -R -d -m "u:$ME:rwX,u:$SANDBOX_USER:rwX,m::rwX" "$WORKSPACE"
        # The sandbox user must be able to reach the folder
        d=$(dirname "$WORKSPACE")
        while [ "$d" != / ]; do as_root setfacl -m "u:$SANDBOX_USER:x" "$d" 2>/dev/null || true; d=$(dirname "$d"); done
    fi
    # SELinux: label for container access once (a :Z mount would try to relabel
    # your files as the sandbox user and fail). Skipped without SELinux.
    if command -v selinuxenabled >/dev/null && selinuxenabled; then
        if command -v semanage >/dev/null; then
            as_root semanage fcontext -a -t container_file_t "$WORKSPACE(/.*)?" 2>/dev/null \
                || as_root semanage fcontext -m -t container_file_t "$WORKSPACE(/.*)?"
            as_root restorecon -R "$WORKSPACE"
        else
            as_root chcon -R -t container_file_t "$WORKSPACE"
        fi
        echo "   SELinux label set"
    fi
fi

# ---------------------------------------------------------------------------
# Units, drop-ins, config
# ---------------------------------------------------------------------------
echo "== Units -> $UNIT_DIR"
make_dir "$SB_HOME/.config" "$SB_HOME/.config/containers" "$UNIT_DIR" \
         "$SB_HOME/.config/agent-sandbox" "$CONFIG_DIR"

render "$HERE/sandbox.network"   "$TMP/$NAME.network"
render "$HERE/gateway.container" "$TMP/$NAME-gateway.container"
render "$HERE/agent.container"   "$TMP/$NAME.container"
for u in "$NAME.network" "$NAME-gateway.container" "$NAME.container"; do
    install_file 644 "$TMP/$u" "$UNIT_DIR/$u"
done

if [ "$NET" = tailscale ]; then
    make_dir "$UNIT_DIR/$NAME-gateway.container.d"
    render "$HERE/tailscale.conf" "$TMP/10-tailscale.conf"
    install_file 644 "$TMP/10-tailscale.conf" "$UNIT_DIR/$NAME-gateway.container.d/10-tailscale.conf"
fi

ssh_addon() { case "$1" in gpu-remote|slurm) return 0 ;; *) return 1 ;; esac; }
dropins=()
[ -n "$GPU" ] && dropins+=("$REPO/addons/gpu-local/quadlet/10-gpu-$GPU.conf")
for a in "${ADDONS[@]}"; do
    case "$a" in
        claude-code) dropins+=("$REPO/addons/claude-code/quadlet/20-claude-code.conf") ;;
        codex)      dropins+=("$REPO/addons/codex/quadlet/21-codex.conf") ;;
        gpu-remote) dropins+=("$REPO/addons/gpu-remote/quadlet/30-gpu-remote.conf") ;;
        slurm)      dropins+=("$REPO/addons/slurm/quadlet/31-slurm.conf") ;;
        git-remote) dropins+=("$REPO/addons/git-remote/quadlet/32-git-remote.conf") ;;
        notify)     dropins+=("$REPO/addons/notify/quadlet/33-notify.conf") ;;
        github-app) dropins+=("$REPO/addons/github-app/quadlet/34-github-app.conf") ;;
    esac
    # The add-on's client (bin/: on PATH), helpers its hooks run as root (libexec/),
    # claude.md and start-up hooks, mounted read-only into the agent
    make_dir "$ADDON_DIR" "$ADDON_DIR/$a"
    ssh_addon "$a" && make_dir "$CONFIG_DIR/${a%%-*}-ssh"
    for sub in bin libexec; do
        [ -d "$REPO/addons/$a/$sub" ] || continue
        make_dir "$ADDON_DIR/$a/$sub"
        for f in "$REPO/addons/$a/$sub/"*; do install_file 755 "$f" "$ADDON_DIR/$a/$sub/$(basename "$f")"; done
    done
    install_file 644 "$REPO/addons/$a/claude.md" "$ADDON_DIR/$a/claude.md"
    if [ -d "$REPO/addons/$a/entrypoint.d" ]; then
        make_dir "$ADDON_DIR/$a/entrypoint.d"
        for f in "$REPO/addons/$a/entrypoint.d/"*.sh; do install_file 644 "$f" "$ADDON_DIR/$a/entrypoint.d/$(basename "$f")"; done
    fi
    env=$CONFIG_DIR/$a.env
    if exists "$env"; then echo "   keeping $env"; else install_file 600 "$REPO/addons/$a/$a.env.example" "$env"; fi
done
# github-app: the App's private key, mounted into the gateway only. An empty
# placeholder keeps the mount (and so the gateway) working until you put it there.
if has_addon github-app && ! exists "$CONFIG_DIR/github-app.pem"; then
    : > "$TMP/github-app.pem"
    install_file 600 "$TMP/github-app.pem" "$CONFIG_DIR/github-app.pem"
fi
# Agent config folders given as host paths: create them for the sandbox user. A
# folder outside its home (e.g. an existing /srv/... one) is left as it is.
for cfg in "$(has_addon claude-code && echo "$CLAUDE_CONFIG")" "$(has_addon codex && echo "$CODEX_CONFIG")"; do
    case "$cfg" in
        "$SB_HOME"/*) exists "$cfg" || make_dir "$cfg" ;;
        /*)           exists "$cfg" || echo "WARNING: $cfg does not exist; create it for $SANDBOX_USER (mode 700)." ;;
    esac
done
# Gateway side of each add-on: it reads the add-on's env file and allowlists its
# hosts (*_HOST, *_URL) and private addresses (*_PRIVATE_IP).
if [ ${#ADDONS[@]} -gt 0 ]; then
    make_dir "$UNIT_DIR/$NAME-gateway.container.d"
    for a in "${ADDONS[@]}"; do
        render "$HERE/addon-gateway.conf" "$TMP/50-addon-$a.conf"
        sed -i "s/@ADDON@/$a/g" "$TMP/50-addon-$a.conf"
        install_file 644 "$TMP/50-addon-$a.conf" "$UNIT_DIR/$NAME-gateway.container.d/50-addon-$a.conf"
        # More gateway drop-ins of the add-on (github-app: its private key)
        for f in "$REPO/addons/$a/quadlet/gateway/"*.conf; do
            [ -f "$f" ] || continue
            render "$f" "$TMP/gw-$(basename "$f")"
            install_file 644 "$TMP/gw-$(basename "$f")" "$UNIT_DIR/$NAME-gateway.container.d/$(basename "$f")"
        done
    done
fi
if [ ${#dropins[@]} -gt 0 ]; then
    make_dir "$UNIT_DIR/$NAME.container.d"
    for f in "${dropins[@]}"; do
        render "$f" "$TMP/$(basename "$f")"
        install_file 644 "$TMP/$(basename "$f")" "$UNIT_DIR/$NAME.container.d/$(basename "$f")"
    done
fi

echo "== Config -> $CONFIG_DIR"
render "$HERE/gateway.env.example" "$TMP/gateway.env"
sed -i "s/^GATEWAY_MODE=.*/GATEWAY_MODE=$MODE/" "$TMP/gateway.env"
[ "$NET" = tailscale ] && sed -i 's/^#\(TS_[A-Z_]*=\)/\1/' "$TMP/gateway.env"
for f in gateway sandbox; do
    dst=$CONFIG_DIR/$f.env
    if exists "$dst"; then echo "   keeping $dst"
    elif [ "$f" = gateway ]; then install_file 600 "$TMP/gateway.env" "$dst"
    else install_file 600 "$HERE/sandbox.env.example" "$dst"; fi
done
if ! exists "$CONFIG_DIR/extra.list"; then
    printf '# Extra allowed hosts for instance %s, one per line ("*.example.com" = with subdomains)\n' "$NAME" > "$TMP/extra.list"
    install_file 644 "$TMP/extra.list" "$CONFIG_DIR/extra.list"
fi

cat <<EOF

Done. Next steps, as $SANDBOX_USER:

$( [ "$SAME_USER" = 0 ] && echo "  sudo machinectl shell $SANDBOX_USER@" )
  nano ${CONFIG_DIR/#$SB_HOME/\~}/gateway.env       # mode, profiles$( [ "$NET" = tailscale ] && echo ', TS_AUTHKEY, TS_EXIT_NODE' )
  nano ${CONFIG_DIR/#$SB_HOME/\~}/extra.list        # your own allowed hosts
$( for a in "${ADDONS[@]}"; do
       if ssh_addon "$a"; then echo "  nano ${CONFIG_DIR/#$SB_HOME/\~}/$a.env   # + SSH key in ${CONFIG_DIR/#$SB_HOME/\~}/${a%%-*}-ssh/ (addons/$a/README.md)"
       elif [ "$a" = codex ]; then echo "  # Codex login: copy your auth.json into ${CODEX_CONFIG/#$SB_HOME/\~}/ (addons/codex/README.md)"
       elif [ "$a" = github-app ]; then echo "  nano ${CONFIG_DIR/#$SB_HOME/\~}/github-app.env   # App ID, organization; App private key -> github-app.pem (addons/github-app/README.md)"
       elif [ "$a" != claude-code ]; then echo "  nano ${CONFIG_DIR/#$SB_HOME/\~}/$a.env   # host, token (addons/$a/README.md)"; fi
     done )
$( case "$IMAGE" in localhost/*) ;; *) echo "  podman login --authfile ~/.config/containers/auth.json ${IMAGE%%/*}   # private packages: once";; esac )
  /usr/libexec/podman/quadlet -dryrun -user | less   # check the generated units
  systemctl --user daemon-reload
  systemctl --user start $NAME-gateway $NAME
  systemctl --user enable --now podman-auto-update.timer
  journalctl --user -u $NAME -f                     # wait for "Network ready"
$( has_addon claude-code && echo "  podman exec -it -u agent $NAME claude              # first time: log in" )
$( has_addon codex && echo "  podman exec -it -u agent $NAME codex               # or: codex login --device-auth" )

Your files for the agent go into $WORKSPACE.
EOF
