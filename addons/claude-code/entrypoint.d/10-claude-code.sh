# claude-code add-on, sourced by the entrypoint as root before it drops to `agent`.
# Installs or updates Claude Code in the root-owned /opt/claude-code (a named volume
# shared by all sandboxes), puts `claude` on PATH and hands Claude the sandbox's
# managed CLAUDE.md. Never fails the container start: without it, only `claude` is
# missing.
claude_code_setup() {
    local d=/opt/agent-sandbox/addons/claude-code f=/run/agent-sandbox/addons/claude-code.env
    local content line val version="" src
    # The add-on's env file, then sandbox.env (older setups set it there), then stable
    if content=$(drop_to_agent cat "$f" 2>/dev/null); then
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?CLAUDE_CODE_VERSION=(.*)$ ]] || continue
            val=${BASH_REMATCH[2]}
            val=${val%%[[:space:]]#*}; val=${val%"${val##*[![:space:]]}"}
            val=${val#[\"\']}; val=${val%[\"\']}
            version=$val
        done <<< "$content"
    else
        echo "WARN: claude-code: $f is not readable by agent; using defaults (and the gateway" \
             "may not allow Anthropic's hosts)." >&2
    fi
    version=${version:-${CLAUDE_CODE_VERSION:-stable}}

    # Mount is owned by the host user (= agent) and may be mode 0700: read as agent,
    # run as root, so the installed files are root-owned.
    if ! src=$(drop_to_agent cat "$d/libexec/install-claude-code" 2>/dev/null); then
        echo "WARN: claude-code: $d/libexec/install-claude-code is not readable by agent; add-on inactive." >&2
        return 0
    fi
    if ! CLAUDE_CODE_VERSION=$version bash -c "$src" install-claude-code; then
        if [ -x /opt/claude-code/bin/claude ]; then
            echo "WARN: Claude Code update failed, keeping $(/opt/claude-code/bin/claude --version 2>/dev/null | head -1)" >&2
        else
            echo "WARN: Claude Code could not be installed; \`claude\` is unavailable. Check the gateway log" \
                 "(claude.ai and downloads.claude.ai must be allowed: claude-code.env mounted into the gateway?)." >&2
        fi
    fi
    [ -x /opt/claude-code/bin/claude ] && ln -sfn /opt/claude-code/bin/claude /opt/agent-sandbox/bin/claude

    # Managed CLAUDE.md: loaded in every session, root-owned, outside ~/.claude.
    # (Images from before the add-on write it themselves and have no AGENTS.md.)
    if [ -r /etc/agent-sandbox/AGENTS.md ]; then
        install -d -m 0755 /etc/claude-code
        install -m 0644 /etc/agent-sandbox/AGENTS.md /etc/claude-code/CLAUDE.md
    fi
    return 0
}
claude_code_setup || echo "WARN: claude-code: setup failed." >&2
unset -f claude_code_setup
