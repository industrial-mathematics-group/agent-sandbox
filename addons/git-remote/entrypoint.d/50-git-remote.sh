# git-remote add-on, sourced by the entrypoint as root before it drops to `agent`.
# Writes the system git config (/etc/gitconfig, root-owned): a credential helper for
# GIT_REMOTE_HOST, git@ URLs rewritten to HTTPS, and the commit identity. The token
# itself stays in the mounted env file; the helper reads it when git asks for it.
# Never fails the container start: a broken config only costs the add-on.
git_remote_setup() {
    local f=/run/agent-sandbox/addons/git-remote.env content line key val
    local host="" name="" email="" helper=/opt/agent-sandbox/addons/git-remote/bin/git-remote
    local cfg=/etc/gitconfig
    # Owned by the sandbox user (= agent inside), mode 600: read it as agent
    if ! content=$(drop_to_agent cat "$f" 2>/dev/null); then
        echo "WARN: git-remote: $f is not readable by agent; add-on inactive." >&2
        return 0
    fi
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(GIT_REMOTE_[A-Z_]+)=(.*)$ ]] || continue
        key=${BASH_REMATCH[2]} val=${BASH_REMATCH[3]}
        val=${val%%[[:space:]]#*}; val=${val%"${val##*[![:space:]]}"}
        val=${val#[\"\']}; val=${val%[\"\']}
        case "$key" in
            GIT_REMOTE_HOST)         host=${val,,} ;;
            GIT_REMOTE_AUTHOR_NAME)  name=$val ;;
            GIT_REMOTE_AUTHOR_EMAIL) email=$val ;;
        esac
    done <<< "$content"
    if [[ ! "$host" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
        echo "WARN: git-remote: GIT_REMOTE_HOST '$host' is not a host name; add-on inactive." >&2
        return 0
    fi
    touch "$cfg"
    git config --file "$cfg" --unset-all "credential.https://$host.helper" 2>/dev/null || true
    # The empty entry drops any helpers configured before; then ours
    git config --file "$cfg" --add "credential.https://$host.helper" ""
    git config --file "$cfg" --add "credential.https://$host.helper" "!$helper credential"
    git config --file "$cfg" --unset-all "url.https://$host/.insteadOf" 2>/dev/null || true
    git config --file "$cfg" --add "url.https://$host/.insteadOf" "git@$host:"
    git config --file "$cfg" --add "url.https://$host/.insteadOf" "ssh://git@$host/"
    [ -z "$name" ]  || git config --file "$cfg" user.name "$name"
    [ -z "$email" ] || git config --file "$cfg" user.email "$email"
    chmod 0644 "$cfg"
    echo "git-remote: credentials for https://$host"
}
git_remote_setup || echo "WARN: git-remote: setup failed; add-on inactive." >&2
unset -f git_remote_setup
