# shellcheck shell=bash disable=SC2034,SC2088
# Guided setup for setup.sh: `./setup.sh --interactive` (or -i) asks for the image,
# add-ons, hardware limits and network one step at a time. Sourced by setup.sh, not
# run on its own.
#
# The answers only fill in setup.sh's own settings (the same variables its options
# set), and setup.sh then runs exactly as with those options. So a guided run writes
# the same files as the command line it prints at the end. Options given together
# with -i are the defaults of the questions.
#
# Dialogs: whiptail or dialog if installed, otherwise plain prompts.
# AGENT_SANDBOX_UI=plain|whiptail|dialog picks one.

# ---------------------------------------------------------------------------
# Prompts: ui_menu, ui_checklist, ui_input, ui_yesno. Each sets REPLY (ui_checklist:
# REPLY_LIST); Cancel/Esc or Ctrl-D ends setup.sh without writing anything.
# ---------------------------------------------------------------------------
ui_init() {
    UI=${AGENT_SANDBOX_UI:-}
    if [ -z "$UI" ]; then
        if command -v whiptail >/dev/null; then UI=whiptail
        elif command -v dialog >/dev/null; then UI=dialog
        else UI=plain; fi
    fi
    case "$UI" in
        plain) ;;
        whiptail|dialog) command -v "$UI" >/dev/null || die "AGENT_SANDBOX_UI=$UI: $UI is not installed" ;;
        *) die "AGENT_SANDBOX_UI must be plain, whiptail or dialog" ;;
    esac
    TITLE="agent-sandbox setup"
    ui_size
}
ui_cancel() { [ "$UI" = plain ] || clear; echo "Cancelled; nothing was written." >&2; exit 1; }
# Box size for whiptail/dialog: fit the terminal, at most 76 x 22
ui_size() { local c l; c=$(tput cols 2>/dev/null || echo 80); l=$(tput lines 2>/dev/null || echo 24)
    W=$(( c > 80 ? 76 : c - 4 )); H=$(( l > 26 ? 22 : l - 2 )); }
# Run whiptail/dialog into BOX; their answer comes on stderr, the screen on stdout
ui_box() { BOX=$("$UI" --title "$TITLE" "$@" 3>&1 1>&2 2>&3) || ui_cancel; }
plain_read() {   # plain_read <prompt>: one line from the terminal into REPLY
    printf '%s' "$1" >&2
    IFS= read -r REPLY || { echo >&2; ui_cancel; }
    REPLY=${REPLY#"${REPLY%%[![:space:]]*}"}; REPLY=${REPLY%"${REPLY##*[![:space:]]}"}
}
plain_heading() { printf '\n\033[1m== %s\033[0m\n' "$1" >&2; }

# ui_menu <question> <default tag> <tag> <description> [<tag> <description>...]
ui_menu() {
    local q=$1 def=$2; shift 2
    local tags=() descs=() i n
    while [ $# -gt 0 ]; do tags+=("$1"); descs+=("$2"); shift 2; done
    if [ "$UI" != plain ]; then
        local items=()
        for i in "${!tags[@]}"; do items+=("${tags[$i]}" "${descs[$i]}"); done
        n=$(( ${#tags[@]} < H - 8 ? ${#tags[@]} : H - 8 ))
        ui_box --default-item "$def" --menu "$q" "$H" "$W" "$n" "${items[@]}"
        REPLY=$BOX
        return
    fi
    plain_heading "$q"
    for i in "${!tags[@]}"; do
        printf '  %2d) %-12s %s%s\n' $(( i + 1 )) "${tags[$i]}" "${descs[$i]}" \
            "$([ "${tags[$i]}" = "$def" ] && echo '  [default]')" >&2
    done
    while :; do
        plain_read "Choice [${def}]: "
        [ -n "$REPLY" ] || { REPLY=$def; return; }
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1 ] && [ "$REPLY" -le ${#tags[@]} ]; then
            REPLY=${tags[$(( REPLY - 1 ))]}; return
        fi
        for n in "${tags[@]}"; do [ "$REPLY" = "$n" ] && return; done
        echo "  Type a number from 1 to ${#tags[@]}, or a name from the list." >&2
    done
}

# ui_checklist <question> <tag> <description> <on|off> [...]: sets REPLY_LIST
ui_checklist() {
    local q=$1; shift
    local tags=() descs=() states=() i t picked
    while [ $# -gt 0 ]; do tags+=("$1"); descs+=("$2"); states+=("$3"); shift 3; done
    REPLY_LIST=()
    if [ "$UI" != plain ]; then
        local items=()
        for i in "${!tags[@]}"; do items+=("${tags[$i]}" "${descs[$i]}" "$([ "${states[$i]}" = on ] && echo ON || echo OFF)"); done
        local n=$(( ${#tags[@]} < H - 8 ? ${#tags[@]} : H - 8 ))
        ui_box --separate-output --checklist "$q" "$H" "$W" "$n" "${items[@]}"
        picked=$BOX
        [ -z "$picked" ] || mapfile -t REPLY_LIST <<<"$picked"
        return
    fi
    plain_heading "$q"
    for i in "${!tags[@]}"; do
        printf '  %2d) [%s] %-12s %s\n' $(( i + 1 )) "$([ "${states[$i]}" = on ] && echo x || echo ' ')" \
            "${tags[$i]}" "${descs[$i]}" >&2
    done
    echo "  Enter keeps the [x] ones; or type the numbers or names you want, e.g. \"1 3\"; \"-\" for none." >&2
    while :; do
        plain_read "Selection: "
        REPLY_LIST=()
        if [ -z "$REPLY" ]; then
            for i in "${!tags[@]}"; do [ "${states[$i]}" = on ] && REPLY_LIST+=("${tags[$i]}"); done
            return
        fi
        [ "$REPLY" = - ] && return
        local ok=1 w
        for w in ${REPLY//,/ }; do
            t=
            if [[ "$w" =~ ^[0-9]+$ ]] && [ "$w" -ge 1 ] && [ "$w" -le ${#tags[@]} ]; then t=${tags[$(( w - 1 ))]}
            else for i in "${!tags[@]}"; do [ "$w" = "${tags[$i]}" ] && t=$w; done; fi
            if [ -z "$t" ]; then echo "  Not in the list: $w" >&2; ok=0; break; fi
            case " ${REPLY_LIST[*]} " in *" $t "*) ;; *) REPLY_LIST+=("$t") ;; esac
        done
        [ "$ok" = 1 ] && return
    done
}

# ui_input <question> <default> [<check function> <error message>]
ui_input() {
    local q=$1 def=$2 check=${3:-} err=${4:-}
    while :; do
        if [ "$UI" != plain ]; then
            ui_box --inputbox "$q" 12 "$W" "$def"
            REPLY=$BOX
        else
            plain_heading "$q"
            plain_read "$([ -n "$def" ] && echo "[$def]: " || echo "> ")"
            [ -n "$REPLY" ] || REPLY=$def
        fi
        if [ -z "$check" ] || "$check" "$REPLY"; then return; fi
        if [ "$UI" != plain ]; then ui_box --msgbox "$err" 10 "$W"; else echo "  $err" >&2; fi
    done
}

# ui_yesno <question> <y|n default>: returns 0 for yes
ui_yesno() {
    local q=$1 def=$2
    if [ "$UI" != plain ]; then
        local no=() rc=0; [ "$def" = n ] && no=(--defaultno)
        "$UI" --title "$TITLE" "${no[@]}" --yesno "$q" 12 "$W" 3>&1 1>&2 2>&3 || rc=$?
        case $rc in 0) return 0 ;; 1) return 1 ;; *) ui_cancel ;; esac
    fi
    plain_heading "$q"
    while :; do
        plain_read "$([ "$def" = y ] && echo '[Y/n]' || echo '[y/N]'): "
        case "${REPLY:-$def}" in [yY]|[yY]es) return 0 ;; [nN]|[nN]o) return 1 ;; esac
        echo "  Answer y or n." >&2
    done
}
ui_note() { if [ "$UI" != plain ]; then ui_box --msgbox "$1" 16 "$W"; else printf '\n%s\n' "$1" >&2; fi; }

# ---------------------------------------------------------------------------
# Checks for the answers (the same rules as setup.sh's own)
# ---------------------------------------------------------------------------
g_has()         { case " ${ADDONS[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
g_name_ok()     { [[ "$1" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; }
g_user_ok()     { id "$1" >/dev/null 2>&1 && [ "$1" != root ]; }
g_registry_ok() { [ -n "$1" ] && [ "$1" != ghcr.io/OWNER ] && [[ "$1" != *[[:space:]]* ]]; }
g_abs_ok()      { [[ "$1" = /* || "$1" = "~"* ]]; }
g_cfg_ok()      { [[ "$1" =~ ^/[^:,[:space:]]*$ || "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; }
g_mem_ok()      { [[ "$1" =~ ^[0-9]+[bkmgBKMG]?$ ]] && [[ ! "$1" =~ ^0+[bkmgBKMG]?$ ]]; }
g_cpus_ok()     { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ ! "$1" =~ ^0+(\.0+)?$ ]]; }
g_ports_ok()    { local p; for p in ${1//,/ }; do [[ "$p" =~ ^[0-9]{1,5}$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ] || return 1; done; }

# Default allowlists of a core flavor (as setup.sh picks them)
g_default_profiles() {
    case "$1" in
        minimal) echo python ;; node) echo node,python ;; julia) echo julia,python ;;
        octave) echo octave,python ;; full) echo node,python,julia ;;
    esac
}

# ---------------------------------------------------------------------------
# The questions
# ---------------------------------------------------------------------------
guided_setup() {
    { [ -t 0 ] && [ -t 1 ]; } || die "--interactive needs a terminal (run the options without -i in scripts)"
    ui_init
    local lang variant mem_total sb_home a f on default_codex items profiles_given=0
    [ -n "$PROFILES" ] && profiles_given=1

    ui_note "Guided setup of an agent-sandbox instance (a gateway + an agent container).

You choose the image, the add-ons, the hardware limits and the network. Nothing is
written until you confirm at the end, and you get the equivalent setup.sh command
line to reuse. Cancel any time with Esc or Ctrl-C."

    # --- Who runs the containers
    ui_input "Sandbox user that runs the containers (\"$(id -un)\" = your own account, no isolation)" \
        "$SANDBOX_USER" g_user_ok "No such user (or root). Create it first: sudo useradd -m agent-sandbox"
    SANDBOX_USER=$REPLY
    sb_home=$(getent passwd "$SANDBOX_USER" | cut -d: -f6)

    # --- Instance; an existing one can be the starting point
    ui_input "Instance name (one gateway + one agent container per project)" "$NAME" \
        g_name_ok "Lowercase letters, digits and '-', starting with a letter."
    NAME=$REPLY
    if as_sb_user test -e "$sb_home/.config/agent-sandbox/$NAME/setup.conf" 2>/dev/null \
        && ui_yesno "Instance '$NAME' exists. Start from its settings? (Its env files are kept either way.)" y; then
        load_instance
        profiles_given=1
        HOST_SETUP=0   # done when the instance was set up
    fi

    # --- Image: registry, flavor, variant
    ui_input "Image registry (\"localhost\" for images built with ./build.sh)" \
        "$([ "$REGISTRY" = ghcr.io/OWNER ] && echo localhost || echo "$REGISTRY")" \
        g_registry_ok "A registry such as ghcr.io/<owner> or localhost."
    REGISTRY=$REPLY
    lang=${FLAVOR%-rocm}; lang=${lang%-utils}
    ui_menu "Image: which language tools does the agent need? (All have Python + uv.)" "$lang" \
        minimal "Python projects, scripting, plain repo work" \
        node    "Websites, JS/TS tooling (Node LTS)" \
        julia   "Julia packages" \
        octave  "MATLAB-style code with GNU Octave" \
        full    "Everything: Node + Julia"
    lang=$REPLY
    case "$FLAVOR" in *-rocm) variant=rocm ;; *-utils) variant=utils ;; *) variant=headless ;; esac
    if [ "$lang" = full ]; then
        ui_menu "Image variant" "$variant" \
            headless "Command-line only (smallest download)" \
            utils    "+ virtual display (Xvfb) and headless Chromium" \
            rocm     "utils + ROCm, for an AMD GPU (amd64 only)"
    else
        [ "$variant" = rocm ] && variant=utils
        ui_menu "Image variant" "$variant" \
            headless "Command-line only (smallest download)" \
            utils    "+ virtual display (Xvfb) and headless Chromium"
    fi
    case "$REPLY" in headless) FLAVOR=$lang ;; *) FLAVOR=$lang-$REPLY ;; esac

    ui_input "Workspace: host folder the agent sees as /workspace" \
        "${WORKSPACE:-/var/srv/agent-sandbox/$NAME}" g_abs_ok "An absolute path (or one starting with ~)."
    WORKSPACE=${REPLY/#\~/$HOME}

    # --- Add-ons
    while :; do
        items=()
        for a in "${ALL_ADDONS[@]}"; do
            on=off; case " ${ADDONS[*]} " in *" $a "*) on=on ;; esac
            # Claude Code is what setup.sh adds when no agent is chosen
            [ ${#ADDONS[@]} -eq 0 ] && [ "$a" = claude-code ] && on=on
            case "$a" in
                claude-code) items+=("$a" "Claude Code (coding agent)" "$on") ;;
                codex)       items+=("$a" "OpenAI Codex (coding agent)" "$on") ;;
                github-app)  items+=("$a" "GitHub access as a GitHub App" "$on") ;;
                git-remote)  items+=("$a" "Push, pull and API for one Git hosting account" "$on") ;;
                notify)      items+=("$a" "Push notifications when the agent needs you" "$on") ;;
                slurm)       items+=("$a" "Jobs on an HPC cluster (Slurm, over SSH)" "$on") ;;
                gpu-remote)  items+=("$a" "Tests on a remote GPU server (over SSH)" "$on") ;;
                *)           items+=("$a" "" "$on") ;;
            esac
        done
        ui_checklist "Add-ons (Space toggles). Their hosts are allowlisted in the gateway automatically." "${items[@]}"
        ADDONS=("${REPLY_LIST[@]}")
        case " ${ADDONS[*]} " in *" claude-code "*|*" codex "*) break ;; esac
        ui_note "Pick at least one coding agent: claude-code or codex."
    done
    if g_has claude-code; then
        ui_input "~/.claude of Claude Code: a named volume (shared by instances) or an absolute host folder" \
            "$CLAUDE_CONFIG" g_cfg_ok "A volume name or an absolute path without ':' or ','."
        CLAUDE_CONFIG=$REPLY
    fi
    if g_has codex; then
        default_codex=$sb_home/.config/agent-sandbox/codex
        ui_input "~/.codex of Codex: an absolute host folder or a named volume" \
            "${CODEX_CONFIG:-$default_codex}" g_cfg_ok "A volume name or an absolute path without ':' or ','."
        CODEX_CONFIG=$REPLY
        [ "$CODEX_CONFIG" != "$default_codex" ] || CODEX_CONFIG=
    fi

    # --- Hardware
    mem_total=$(awk '/^MemTotal:/ {printf "%dg", $2 / 1048576}' /proc/meminfo 2>/dev/null || true)
    ui_input "Memory limit of the agent container, e.g. 8g or 16g${mem_total:+ (this host has $mem_total)}" \
        "$MEMORY" g_mem_ok "A size such as 8g, 16g or 4096m."
    MEMORY=$REPLY
    ui_input "CPU limit of the agent container, e.g. 4 or 2.5 (this host has $(nproc 2>/dev/null || echo '?') CPUs)" \
        "$CPUS" g_cpus_ok "A number of CPUs such as 4 or 2.5."
    CPUS=$REPLY
    local gpu_hint=
    [ -e /dev/kfd ] && gpu_hint=" (found: AMD)"
    command -v nvidia-smi >/dev/null && gpu_hint=" (found: NVIDIA)"
    if [ "$FLAVOR" = full-rocm ] && [ -z "$GPU" ]; then GPU=amd; fi
    ui_menu "Local GPU for the agent container$gpu_hint" "${GPU:-none}" \
        none   "No GPU" \
        amd    "AMD GPU via ROCm (uses the -rocm image)" \
        nvidia "NVIDIA GPU via CDI (nvidia-container-toolkit)"
    GPU=$REPLY; [ "$GPU" != none ] || GPU=

    # --- Network
    ui_menu "Network: how does the gateway reach the internet?" "$NET" \
        plain     "Directly from this host" \
        tailscale "Only via a Tailscale exit node"
    NET=$REPLY
    ui_menu "Gateway filter mode" "$MODE" \
        standard "Only allowlisted hosts, checked by name (recommended)" \
        strict   "standard + direct IPs of allowlisted hosts (proxy-unaware tools)" \
        open     "Any public host; LAN, metadata, IPv6 stay blocked"
    MODE=$REPLY
    [ "$profiles_given" = 1 ] || PROFILES=$(g_default_profiles "$lang")
    items=()
    for f in "$REPO"/gateway/lists/*.list; do
        a=$(basename "$f" .list); [ "$a" = base ] && continue
        on=off; case ",$PROFILES," in *",$a,"*) on=on ;; esac
        items+=("$a" "allow the $a package hosts" "$on")
    done
    ui_checklist "Allowlists besides base (defaults follow the image)" "${items[@]}"
    PROFILES=$(IFS=,; echo "${REPLY_LIST[*]}")
    ui_input "TCP ports for dev servers, separated by spaces (empty for none). $([ "$NET" = plain ] && echo 'Published on 127.0.0.1 of this host.' || echo 'Open on the tailnet.')" \
        "${PORTS[*]}" g_ports_ok "Port numbers from 1 to 65535, separated by spaces."
    read -ra PORTS <<<"${REPLY//,/ }"

    # --- Host setup
    if ui_yesno "Do the host setup (subuids, linger, workspace ACLs and SELinux label; uses sudo)? Needed the first time for a sandbox user and workspace." \
        "$([ "$HOST_SETUP" = 1 ] && echo y || echo n)"; then HOST_SETUP=1; else HOST_SETUP=0; fi
    [ "$UI" = plain ] || clear
}

# After setup.sh has checked the settings and filled in its defaults: show the
# command line for them and ask whether to go ahead.
guided_confirm() {
    local cmd
    cmd="$(setup_cmdline)"
    [ "$HOST_SETUP" = 1 ] || cmd+=" --no-host-setup"
    local summary
    summary="Instance '$NAME' of $SANDBOX_USER
  image      $IMAGE$( [ "$GPU" = amd ] && echo " ($IMAGE_ROCM with the GPU)")
  workspace  $WORKSPACE
  add-ons    ${ADDONS[*]}
  limits     memory $MEMORY, cpus $CPUS${GPU:+, gpu $GPU}
  network    $NET, mode $MODE, profiles base${PROFILES:+,$PROFILES}, ports ${PORTS[*]:-(none)}
  host setup $([ "$HOST_SETUP" = 1 ] && echo yes || echo no)"
    if [ "$UI" != plain ]; then
        ui_menu "$summary

Same setup without the questions:
$cmd" write \
            write   "Write the instance now" \
            dry-run "Only show what would be written" \
            cancel  "Change nothing"
    else
        printf '\n%s\n\nSame setup without the questions:\n  %s\n' "$summary" "$cmd" >&2
        ui_menu "Go ahead?" write \
            write   "Write the instance now" \
            dry-run "Only show what would be written" \
            cancel  "Change nothing"
    fi
    case "$REPLY" in
        cancel)  ui_cancel ;;
        dry-run) DRY=1 ;;
    esac
    [ "$UI" = plain ] && return
    clear
    printf 'Same setup without the questions:\n  %s\n\n' "$cmd"
}
