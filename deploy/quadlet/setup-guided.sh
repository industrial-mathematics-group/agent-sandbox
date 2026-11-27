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
# Prompts: ui_menu, ui_checklist, ui_input. Each sets REPLY (ui_checklist:
# REPLY_LIST), or returns 1 when the user goes back (the Back button, or "<" at a
# plain prompt; only where BACK_OK=1). Esc, Cancel or Ctrl-D ends setup.sh without
# writing anything.
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
    BACK_OK=0
    ui_size
}
ui_cancel() { [ "$UI" = plain ] || clear; echo "Cancelled; nothing was written." >&2; exit 1; }
# Box size for whiptail/dialog: fit the terminal, at most 76 x 22
ui_size() { local c l; c=$(tput cols 2>/dev/null || echo 80); l=$(tput lines 2>/dev/null || echo 24)
    W=$(( c > 80 ? 76 : c - 4 )); H=$(( l > 26 ? 22 : l - 2 )); }
# Run whiptail/dialog into BOX; their answer comes on stderr, the screen on stdout.
# ui_box back ...: the Cancel button says "Back" and returns 1 (Esc still cancels).
ui_box() {
    local back=0 rc=0 label=()
    if [ "$1" = back ]; then shift; [ "$BACK_OK" = 1 ] && back=1; fi
    if [ "$back" = 1 ]; then
        if [ "$UI" = whiptail ]; then label=(--cancel-button Back); else label=(--cancel-label Back); fi
    fi
    BOX=$("$UI" --title "$TITLE" "${label[@]}" "$@" 3>&1 1>&2 2>&3) || rc=$?
    case "$rc" in 0) return 0 ;; 1) [ "$back" = 1 ] && return 1 ;; esac
    ui_cancel
}
plain_read() {   # plain_read <prompt>: one line from the terminal into REPLY; 1 for "<"
    printf '%s' "$1" >&2
    IFS= read -r REPLY || { echo >&2; ui_cancel; }
    REPLY=${REPLY#"${REPLY%%[![:space:]]*}"}; REPLY=${REPLY%"${REPLY##*[![:space:]]}"}
    if [ "$REPLY" = "<" ]; then
        [ "$BACK_OK" = 1 ] && return 1
        echo "  This is the first question." >&2; plain_read "$1"; return
    fi
    return 0
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
        ui_box back --default-item "$def" --menu "$q" "$H" "$W" "$n" "${items[@]}" || return 1
        REPLY=$BOX
        return 0
    fi
    plain_heading "$q"
    for i in "${!tags[@]}"; do
        printf '  %2d) %-12s %s%s\n' $(( i + 1 )) "${tags[$i]}" "${descs[$i]}" \
            "$([ "${tags[$i]}" = "$def" ] && echo '  [default]')" >&2
    done
    while :; do
        plain_read "Choice [${def}]: " || return 1
        [ -n "$REPLY" ] || { REPLY=$def; return 0; }
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1 ] && [ "$REPLY" -le ${#tags[@]} ]; then
            REPLY=${tags[$(( REPLY - 1 ))]}; return 0
        fi
        for n in "${tags[@]}"; do [ "$REPLY" = "$n" ] && return 0; done
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
        ui_box back --separate-output --checklist "$q" "$H" "$W" "$n" "${items[@]}" || return 1
        picked=$BOX
        [ -z "$picked" ] || mapfile -t REPLY_LIST <<<"$picked"
        return 0
    fi
    plain_heading "$q"
    for i in "${!tags[@]}"; do
        printf '  %2d) [%s] %-12s %s\n' $(( i + 1 )) "$([ "${states[$i]}" = on ] && echo x || echo ' ')" \
            "${tags[$i]}" "${descs[$i]}" >&2
    done
    echo "  Enter keeps the [x] ones; or type the numbers or names you want, e.g. \"1 3\"; \"-\" for none." >&2
    while :; do
        plain_read "Selection: " || return 1
        REPLY_LIST=()
        if [ -z "$REPLY" ]; then
            for i in "${!tags[@]}"; do [ "${states[$i]}" = on ] && REPLY_LIST+=("${tags[$i]}"); done
            return 0
        fi
        [ "$REPLY" = - ] && return 0
        local ok=1 w
        for w in ${REPLY//,/ }; do
            t=
            if [[ "$w" =~ ^[0-9]+$ ]] && [ "$w" -ge 1 ] && [ "$w" -le ${#tags[@]} ]; then t=${tags[$(( w - 1 ))]}
            else for i in "${!tags[@]}"; do [ "$w" = "${tags[$i]}" ] && t=$w; done; fi
            if [ -z "$t" ]; then echo "  Not in the list: $w" >&2; ok=0; break; fi
            case " ${REPLY_LIST[*]} " in *" $t "*) ;; *) REPLY_LIST+=("$t") ;; esac
        done
        [ "$ok" = 1 ] && return 0
    done
}

# ui_input <question> <default> [<check function> <error message>]
ui_input() {
    local q=$1 def=$2 check=${3:-} err=${4:-}
    while :; do
        if [ "$UI" != plain ]; then
            ui_box back --inputbox "$q" 12 "$W" "$def" || return 1
            REPLY=$BOX
        else
            plain_heading "$q"
            plain_read "$([ -n "$def" ] && echo "[$def]: " || echo "> ")" || return 1
            [ -n "$REPLY" ] || REPLY=$def
        fi
        if [ -z "$check" ] || "$check" "$REPLY"; then return 0; fi
        if [ "$UI" != plain ]; then ui_box --msgbox "$err" 10 "$W"; else echo "  $err" >&2; fi
    done
}
ui_note() { if [ "$UI" != plain ]; then ui_box --msgbox "$1" 16 "$W"; else printf '\n%s\n' "$1" >&2; fi; }

# sudo without leaving the dialogs: the password is asked in a password box and
# handed to `sudo -S -v` on a pipe (a shell builtin writes it: never in arguments,
# the environment or a file). sudo caches the login as usual, so the sudo calls of
# setup.sh after it don't ask again. Plain prompts just let sudo ask.
g_sudo_auth() {   # g_sudo_auth <why>
    local why=$1 try pw
    [ "$(id -u)" != 0 ] || return 0
    sudo -n true 2>/dev/null && return 0   # still cached, or no password needed
    if [ "$UI" = plain ]; then
        printf '\n%s\n' "$why" >&2
        sudo -v || die "sudo failed"
        return 0
    fi
    for try in 1 2 3; do
        ui_box --passwordbox "$why$([ "$try" = 1 ] || printf '\n\nSorry, try again.')

[sudo] password for $(id -un):" 13 "$W"
        pw=$BOX; BOX=
        if printf '%s\n' "$pw" | sudo -S -p '' -v 2>/dev/null; then pw=; return 0; fi
        pw=
    done
    clear; die "sudo: no valid password after 3 tries"
}

# ---------------------------------------------------------------------------
# Checks for the answers (the same rules as setup.sh's own)
# ---------------------------------------------------------------------------
g_has()         { case " ${ADDONS[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
g_name_ok()     { [[ "$1" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; }
g_user_ok()     { id "$1" >/dev/null 2>&1 && [ "$1" != root ]; }
g_registry_ok() { [ -n "$1" ] && [[ "$1" != *[[:space:]]* ]]; }
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
# The questions, one step each, so Back goes to the previous question. A step
# returns 1 to go back; one that doesn't apply (e.g. ~/.codex without Codex) sets
# SKIP=1 and is passed over in either direction.
# ---------------------------------------------------------------------------
g_sb_home() { getent passwd "$SANDBOX_USER" | cut -d: -f6; }
g_lang() { local l=${FLAVOR%-rocm}; printf '%s' "${l%-utils}"; }

g_step_user() {
    ui_input "Sandbox user that runs the containers (\"$(id -un)\" = your own account, no isolation)" \
        "$SANDBOX_USER" g_user_ok "No such user (or root). Create it first: sudo useradd -m agent-sandbox" || return 1
    SANDBOX_USER=$REPLY
    [ "$SANDBOX_USER" = "$(id -un)" ] \
        || g_sudo_auth "The files of $SANDBOX_USER are read and written with sudo."
}
g_step_name() {
    ui_input "Instance name (one gateway + one agent container per project)" "$NAME" \
        g_name_ok "Lowercase letters, digits and '-', starting with a letter." || return 1
    NAME=$REPLY
}
g_step_existing() {   # an existing instance can be the starting point
    as_sb_user test -e "$(g_sb_home)/.config/agent-sandbox/$NAME/setup.conf" 2>/dev/null || { SKIP=1; return 0; }
    ui_menu "Instance '$NAME' exists. Start from its settings? (Its env files are kept either way.)" saved \
        saved   "Use its settings as the defaults below" \
        current "Keep the defaults as they are" || return 1
    if [ "$REPLY" = saved ]; then
        load_instance
        HOST_SETUP=0   # done when the instance was set up
    fi
}
g_step_registry() {
    ui_input "Image registry (\"localhost\" for images built with ./build.sh)" "$REGISTRY" \
        g_registry_ok "A registry such as ghcr.io/<owner> or localhost." || return 1
    REGISTRY=$REPLY
}
g_step_lang() {
    local old new variant
    old=$(g_lang)
    ui_menu "Image: which language tools does the agent need? (All have Python + uv.)" "$old" \
        minimal "Python projects, scripting, plain repo work" \
        node    "Websites, JS/TS tooling (Node LTS)" \
        julia   "Julia packages" \
        octave  "MATLAB-style code with GNU Octave" \
        full    "Everything: Node + Julia" || return 1
    new=$REPLY
    case "$FLAVOR" in *-rocm) variant=-rocm ;; *-utils) variant=-utils ;; *) variant= ;; esac
    [ "$new" = full ] || [ "$variant" != -rocm ] || variant=-utils
    FLAVOR=$new$variant
    # Allowlists follow the image unless they were changed from its default
    if [ -z "$PROFILES" ] || [ "$PROFILES" = "$(g_default_profiles "$old")" ]; then
        PROFILES=$(g_default_profiles "$new")
    fi
}
g_step_variant() {
    local lang variant
    lang=$(g_lang)
    case "$FLAVOR" in *-rocm) variant=rocm ;; *-utils) variant=utils ;; *) variant=headless ;; esac
    if [ "$lang" = full ]; then
        ui_menu "Image variant" "$variant" \
            headless "Command-line only (smallest download)" \
            utils    "+ virtual display (Xvfb) and headless Chromium" \
            rocm     "utils + ROCm, for an AMD GPU (amd64 only)" || return 1
    else
        ui_menu "Image variant" "$variant" \
            headless "Command-line only (smallest download)" \
            utils    "+ virtual display (Xvfb) and headless Chromium" || return 1
    fi
    case "$REPLY" in headless) FLAVOR=$lang ;; *) FLAVOR=$lang-$REPLY ;; esac
}
g_step_workspace() {
    ui_input "Workspace: host folder the agent sees as /workspace" \
        "${WORKSPACE:-/var/srv/agent-sandbox/$NAME}" g_abs_ok "An absolute path (or one starting with ~)." || return 1
    WORKSPACE=${REPLY/#\~/$HOME}
}
g_step_addons() {
    local items a on
    while :; do
        items=()
        for a in "${ALL_ADDONS[@]}"; do
            on=off; case " ${ADDONS[*]} " in *" $a "*) on=on ;; esac
            # Claude Code is what setup.sh adds when no agent is chosen
            if [ ${#ADDONS[@]} -eq 0 ] && [ "$a" = claude-code ]; then on=on; fi
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
        ui_checklist "Add-ons (Space toggles). Their hosts are allowlisted in the gateway automatically." "${items[@]}" || return 1
        case " ${REPLY_LIST[*]} " in
            *" claude-code "*|*" codex "*) ADDONS=("${REPLY_LIST[@]}"); return 0 ;;
        esac
        ui_note "Pick at least one coding agent: claude-code or codex."
    done
}
g_step_claude_config() {
    g_has claude-code || { SKIP=1; return 0; }
    ui_input "~/.claude of Claude Code: a named volume (shared by instances) or an absolute host folder" \
        "$CLAUDE_CONFIG" g_cfg_ok "A volume name or an absolute path without ':' or ','." || return 1
    CLAUDE_CONFIG=$REPLY
}
g_step_codex_config() {
    g_has codex || { SKIP=1; return 0; }
    local default_codex
    default_codex=$(g_sb_home)/.config/agent-sandbox/codex
    ui_input "~/.codex of Codex: an absolute host folder or a named volume" \
        "${CODEX_CONFIG:-$default_codex}" g_cfg_ok "A volume name or an absolute path without ':' or ','." || return 1
    CODEX_CONFIG=$REPLY
    [ "$CODEX_CONFIG" != "$default_codex" ] || CODEX_CONFIG=
}
g_step_memory() {
    local mem_total
    mem_total=$(awk '/^MemTotal:/ {printf "%dg", $2 / 1048576}' /proc/meminfo 2>/dev/null || true)
    ui_input "Memory limit of the agent container, e.g. 8g or 16g${mem_total:+ (this host has $mem_total)}" \
        "$MEMORY" g_mem_ok "A size such as 8g, 16g or 4096m." || return 1
    MEMORY=$REPLY
}
g_step_cpus() {
    ui_input "CPU limit of the agent container, e.g. 4 or 2.5 (this host has $(nproc 2>/dev/null || echo '?') CPUs)" \
        "$CPUS" g_cpus_ok "A number of CPUs such as 4 or 2.5." || return 1
    CPUS=$REPLY
}
g_step_gpu() {
    local hint='' def=${GPU:-none}
    [ -e /dev/kfd ] && hint=" (found: AMD)"
    command -v nvidia-smi >/dev/null && hint=" (found: NVIDIA)"
    if [ "$FLAVOR" = full-rocm ] && [ -z "$GPU" ]; then def=amd; fi
    ui_menu "Local GPU for the agent container$hint" "$def" \
        none   "No GPU" \
        amd    "AMD GPU via ROCm (uses the -rocm image)" \
        nvidia "NVIDIA GPU via CDI (nvidia-container-toolkit)" || return 1
    GPU=$REPLY; [ "$GPU" != none ] || GPU=
}
g_step_net() {
    ui_menu "Network: how does the gateway reach the internet?" "$NET" \
        plain     "Directly from this host" \
        tailscale "Only via a Tailscale exit node" || return 1
    NET=$REPLY
}
g_step_mode() {
    ui_menu "Gateway filter mode" "$MODE" \
        standard "Only allowlisted hosts, checked by name (recommended)" \
        strict   "standard + direct IPs of allowlisted hosts (proxy-unaware tools)" \
        open     "Any public host; LAN, metadata, IPv6 stay blocked" || return 1
    MODE=$REPLY
}
g_step_profiles() {
    local items=() f a on
    [ -n "$PROFILES" ] || PROFILES=$(g_default_profiles "$(g_lang)")
    for f in "$REPO"/gateway/lists/*.list; do
        a=$(basename "$f" .list); [ "$a" = base ] && continue
        on=off; case ",$PROFILES," in *",$a,"*) on=on ;; esac
        items+=("$a" "allow the $a package hosts" "$on")
    done
    ui_checklist "Allowlists besides base (defaults follow the image)" "${items[@]}" || return 1
    PROFILES=$(IFS=,; echo "${REPLY_LIST[*]}")
}
g_step_ports() {
    ui_input "TCP ports for dev servers, separated by spaces (empty for none). $([ "$NET" = plain ] && echo 'Published on 127.0.0.1 of this host.' || echo 'Open on the tailnet.')" \
        "${PORTS[*]}" g_ports_ok "Port numbers from 1 to 65535, separated by spaces." || return 1
    read -ra PORTS <<<"${REPLY//,/ }"
}
g_step_host_setup() {
    ui_menu "Host setup: subuids, linger, workspace ACLs and SELinux label (uses sudo). Needed the first time for a sandbox user and workspace." \
        "$([ "$HOST_SETUP" = 1 ] && echo yes || echo no)" \
        yes "Do the host setup" \
        no  "Skip it (done before for this user and workspace)" || return 1
    if [ "$REPLY" = yes ]; then HOST_SETUP=1; else HOST_SETUP=0; fi
}
G_STEPS=(g_step_user g_step_name g_step_existing g_step_registry g_step_lang g_step_variant
         g_step_workspace g_step_addons g_step_claude_config g_step_codex_config
         g_step_memory g_step_cpus g_step_gpu g_step_net g_step_mode g_step_profiles
         g_step_ports g_step_host_setup)

guided_setup() {
    { [ -t 0 ] && [ -t 1 ]; } || die "--interactive needs a terminal (run the options without -i in scripts)"
    ui_init
    local i=0 dir=1 n=${#G_STEPS[@]}
    if [ "${AGENT_SANDBOX_GUIDED_RESUME:-}" = 1 ]; then
        i=$(( n - 1 ))   # back from the summary: start at the last question
    else
        ui_note "Guided setup of an agent-sandbox instance (a gateway + an agent container).

You choose the image, the add-ons, the hardware limits and the network. Nothing is
written until you confirm at the end, and you get the equivalent setup.sh command
line to reuse. $([ "$UI" = plain ] && echo 'Type < to go back a question, Ctrl-C to cancel.' || echo 'Back goes to the previous question, Esc cancels.')"
    fi
    while [ "$i" -lt "$n" ]; do
        # Back is offered where an earlier question was asked
        BACK_OK=0; [ "$i" -gt 0 ] && BACK_OK=1
        SKIP=0
        if "${G_STEPS[$i]}"; then
            [ "$SKIP" = 1 ] || dir=1
        else
            dir=-1
        fi
        i=$(( i + dir ))
        [ "$i" -ge 0 ] || { i=0; dir=1; }
    done
    BACK_OK=0
    [ "$UI" = plain ] || clear
}

# Back from the summary: setup.sh again with these answers as its options, starting
# at the last question (setup.sh has filled in its defaults by now, so starting over
# from the answers is simpler than undoing that).
g_restart() {
    local args=(-i --name "$NAME" --registry "$REGISTRY" --flavor "$FLAVOR" --workspace "$WORKSPACE"
                --net "$NET" --mode "$MODE" --profiles "$PROFILES" --memory "$MEMORY" --cpus "$CPUS"
                --sandbox-user "$SANDBOX_USER") p a
    for p in "${PORTS[@]}"; do args+=(--port "$p"); done
    [ -z "$GPU" ] || args+=(--gpu "$GPU")
    for a in "${ADDONS[@]}"; do args+=(--addon "$a"); done
    args+=(--claude-config "$CLAUDE_CONFIG")
    [ "$CODEX_CONFIG" = "$SB_HOME/.config/agent-sandbox/codex" ] || args+=(--codex-config "$CODEX_CONFIG")
    if [ "$HOST_SETUP" = 1 ]; then args+=(--host-setup); else args+=(--no-host-setup); fi
    AGENT_SANDBOX_GUIDED_RESUME=1 AGENT_SANDBOX_UI=$UI exec bash "$HERE/setup.sh" "${args[@]}"
}

# After setup.sh has checked the settings and filled in its defaults: show the
# command line for them and ask whether to go ahead.
guided_confirm() {
    local cmd
    BACK_OK=1   # Back (or "<") here restarts the questions at the last one
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
            back    "Go back and change answers" \
            cancel  "Change nothing" || REPLY=back
    else
        printf '\n%s\n\nSame setup without the questions:\n  %s\n' "$summary" "$cmd" >&2
        ui_menu "Go ahead?" write \
            write   "Write the instance now" \
            dry-run "Only show what would be written" \
            back    "Go back and change answers (or type <)" \
            cancel  "Change nothing" || REPLY=back
    fi
    case "$REPLY" in
        back)    g_restart ;;
        cancel)  ui_cancel ;;
        dry-run) DRY=1 ;;
        write)   if [ "$HOST_SETUP" = 1 ] || [ "$SAME_USER" = 0 ]; then
                     g_sudo_auth "Writing the instance$([ "$HOST_SETUP" = 1 ] && echo ' and the host setup') needs sudo."
                 fi ;;
    esac
    [ "$UI" = plain ] && return
    clear
    printf 'Same setup without the questions:\n  %s\n\n' "$cmd"
}
