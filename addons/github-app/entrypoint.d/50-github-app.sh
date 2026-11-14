# github-app add-on, sourced by the entrypoint as root before it drops to `agent`.
# Asks the gateway's token broker (127.0.0.1:3129, same network namespace) for the
# host and commit identity and writes the system git config (/etc/gitconfig,
# root-owned): a credential helper that fetches a fresh installation token when git
# asks, git@ URLs rewritten to HTTPS, and the App's bot identity for commits. No
# secret is written anywhere. Never fails the container start.
github_app_setup() {
    local broker=http://127.0.0.1:${GITHUB_APP_BROKER_PORT:-3129} info="" err host name email app
    local helper=/opt/agent-sandbox/addons/github-app/bin/github-app cfg=/etc/gitconfig
    for _ in $(seq 5); do
        info=$(curl -sS --noproxy '*' --max-time 60 "$broker/info" 2>/dev/null) && [ -n "$info" ] && break
        info=""; sleep 1
    done
    if [ -z "$info" ] || ! jq -e . >/dev/null 2>&1 <<< "$info"; then
        echo "WARN: github-app: no token broker on $broker. The gateway log says why (no github-app.pem," \
             "bad settings, or a gateway image without the broker). Add-on inactive." >&2
        return 0
    fi
    err=$(jq -r '.error // empty' <<< "$info")
    host=$(jq -r '.host // empty' <<< "$info")
    name=$(jq -r '.author_name // empty' <<< "$info")
    email=$(jq -r '.author_email // empty' <<< "$info")
    app=$(jq -r '.app // empty' <<< "$info")
    [ -z "$err" ] || echo "WARN: github-app: the broker reports: ${err//$'\n'/; }" >&2
    if [[ ! "$host" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
        echo "WARN: github-app: the broker gave no valid host ('$host'); add-on inactive." >&2
        return 0
    fi
    touch "$cfg"
    # Replaces git-remote's helper for the same host (this hook runs after it)
    git config --file "$cfg" --unset-all "credential.https://$host.helper" 2>/dev/null || true
    git config --file "$cfg" --add "credential.https://$host.helper" ""
    git config --file "$cfg" --add "credential.https://$host.helper" "!$helper credential $host"
    git config --file "$cfg" --unset-all "url.https://$host/.insteadOf" 2>/dev/null || true
    git config --file "$cfg" --add "url.https://$host/.insteadOf" "git@$host:"
    git config --file "$cfg" --add "url.https://$host/.insteadOf" "ssh://git@$host/"
    [ -z "$name" ]  || git config --file "$cfg" user.name "$name"
    [ -z "$email" ] || git config --file "$cfg" user.email "$email"
    chmod 0644 "$cfg"
    echo "github-app: credentials for https://$host from the gateway${app:+ (App $app)}${name:+, commits as $name}"
}
github_app_setup || echo "WARN: github-app: setup failed; add-on inactive." >&2
unset -f github_app_setup
