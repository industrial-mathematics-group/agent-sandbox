# codex add-on, sourced by the entrypoint as root before it drops to `agent`.
# Installs or updates Codex in the root-owned /opt/codex (a named volume shared by
# all sandboxes), puts `codex` on PATH and writes Codex's system config
# (/etc/codex/config.toml, root-owned): its own sandbox off, since the container and
# the gateway are the sandbox, and the environment notes (the same text Claude Code
# gets as CLAUDE.md) as developer instructions. Your ~/.codex/config.toml overrides
# any of these keys. Never fails the container start.
codex_setup() {
    local d=/opt/agent-sandbox/addons/codex f=/run/agent-sandbox/addons/codex.env
    local content line key val version="" sandbox="danger-full-access" src cfg=/etc/codex/config.toml tmp
    if content=$(drop_to_agent cat "$f" 2>/dev/null); then
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(CODEX_VERSION|CODEX_SANDBOX_MODE)=(.*)$ ]] || continue
            key=${BASH_REMATCH[2]} val=${BASH_REMATCH[3]}
            val=${val%%[[:space:]]#*}; val=${val%"${val##*[![:space:]]}"}
            val=${val#[\"\']}; val=${val%[\"\']}
            case "$key" in
                CODEX_VERSION)      version=$val ;;
                CODEX_SANDBOX_MODE) [ -z "$val" ] || sandbox=$val ;;
            esac
        done <<< "$content"
    else
        echo "WARN: codex: $f is not readable by agent; using defaults (and the gateway" \
             "may not allow OpenAI's hosts)." >&2
    fi
    version=${version:-${CODEX_VERSION:-latest}}
    case "$sandbox" in
        danger-full-access|workspace-write|read-only) ;;
        *) echo "WARN: codex: unknown CODEX_SANDBOX_MODE '$sandbox'; using danger-full-access" >&2
           sandbox=danger-full-access ;;
    esac

    if ! src=$(drop_to_agent cat "$d/libexec/install-codex" 2>/dev/null); then
        echo "WARN: codex: $d/libexec/install-codex is not readable by agent; add-on inactive." >&2
        return 0
    fi
    if ! CODEX_VERSION=$version bash -c "$src" install-codex; then
        if [ -x /opt/codex/bin/codex ]; then
            echo "WARN: Codex update failed, keeping $(/opt/codex/bin/codex --version 2>/dev/null | head -1)" >&2
        else
            echo "WARN: Codex could not be installed; \`codex\` is unavailable. Check the gateway log" \
                 "(registry.npmjs.org must be allowed: codex.env mounted into the gateway?)." >&2
        fi
    fi
    [ -x /opt/codex/bin/codex ] && ln -sfn /opt/codex/bin/codex /opt/agent-sandbox/bin/codex

    # A JSON string is a valid TOML basic string (same escapes)
    install -d -m 0755 /etc/codex
    tmp=$(mktemp)
    {
        echo "# Written by the codex add-on at container start. ~/.codex/config.toml wins over this."
        echo "# The container and its gateway are the sandbox; Codex's own (bubblewrap) can't run here."
        printf 'sandbox_mode = "%s"\n' "$sandbox"
        echo "# Updates come from the entrypoint (CODEX_VERSION in codex.env)"
        echo "check_for_update_on_startup = false"
        echo "# No keyring in the container: keep the login in ~/.codex/auth.json"
        echo 'cli_auth_credentials_store = "file"'
        if [ -r /etc/agent-sandbox/AGENTS.md ]; then
            echo "# The sandbox's environment notes (/etc/agent-sandbox/AGENTS.md)"
            printf 'developer_instructions = %s\n' "$(jq -Rs . < /etc/agent-sandbox/AGENTS.md)"
        fi
    } > "$tmp"
    install -m 0644 "$tmp" "$cfg"
    rm -f "$tmp"
}
codex_setup || echo "WARN: codex: setup failed." >&2
unset -f codex_setup
