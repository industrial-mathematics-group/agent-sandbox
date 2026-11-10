# notify add-on, sourced by the entrypoint as root before it drops to `agent`.
# Installs Claude Code hooks for NOTIFY_EVENTS in the managed settings
# (/etc/claude-code/managed-settings.json: root-owned, loaded in every session, the
# agent can't remove them). Never fails the container start.
notify_setup() {
    local f=/run/agent-sandbox/addons/notify.env content line val events="notification"
    local settings=/etc/claude-code/managed-settings.json tmp hooks='{}' ev name
    local cmd="/opt/agent-sandbox/addons/notify/bin/notify --hook"
    if ! content=$(drop_to_agent cat "$f" 2>/dev/null); then
        echo "WARN: notify: $f is not readable by agent; add-on inactive." >&2
        return 0
    fi
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?NOTIFY_EVENTS=(.*)$ ]] || continue
        val=${BASH_REMATCH[2]}
        val=${val%%[[:space:]]#*}; val=${val#[\"\']}; val=${val%[\"\']}
        events=$val
    done <<< "$content"
    for ev in ${events//,/ }; do
        case "${ev,,}" in
            notification) name=Notification ;;
            stop)         name=Stop ;;
            *) echo "WARN: notify: unknown event '$ev' in NOTIFY_EVENTS (notification, stop)" >&2; continue ;;
        esac
        hooks=$(jq -c --arg n "$name" --arg c "$cmd" \
            '.[$n] = [{hooks: [{type: "command", command: $c, timeout: 20}]}]' <<< "$hooks")
    done
    install -d -m 0755 /etc/claude-code
    tmp=$(mktemp)
    if [ -s "$settings" ]; then
        jq --argjson h "$hooks" '.hooks = ((.hooks // {}) + $h)' "$settings" > "$tmp"
    else
        jq -n --argjson h "$hooks" '{hooks: $h}' > "$tmp"
    fi
    install -m 0644 "$tmp" "$settings"
    rm -f "$tmp"
    echo "notify: hooks for ${events:-no events}"
}
notify_setup || echo "WARN: notify: setup failed; add-on inactive." >&2
unset -f notify_setup
