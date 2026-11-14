# notify: push notifications from the sandbox

Sends you a notification when Claude needs you or has finished, and gives Claude a
`notify` command for results worth interrupting you for. Works with
[ntfy](https://ntfy.sh), [Gotify](https://gotify.net), Discord and Slack webhooks, or
any URL that takes a JSON POST.

- `notify.env` holds the service, URL and token. Like git-remote's, it is mounted as a
  read-only file and read by `notify` when it sends.
- `NOTIFY_EVENTS` picks the automatic notifications. At start, the entrypoint installs
  Claude Code hooks for them in `/etc/claude-code/managed-settings.json` (root-owned,
  loaded in every session):
  - `notification` (default): Claude is waiting for a permission or, after a minute
    idle, for your input. Sent with high priority.
  - `stop`: Claude finished a turn. Chatty in interactive use, handy for long runs.
- The gateway reads the same file and allowlists the host of `NOTIFY_URL`. For a server
  on your LAN or tailnet, set `NOTIFY_PRIVATE_IP` to its address.

The agent can read the token, so use one that can only publish to this channel (an ntfy
token with write access to one topic, a Gotify application token, one webhook).

## Setup

Quadlet: `setup.sh … --addon notify` (existing instance: `setup.sh add-addon <name> notify`), fill in `~/.config/agent-sandbox/<name>/notify.env`,
restart (`systemctl --user restart <name>-gateway`).

Compose: copy `notify.env.example` to `deploy/compose/notify.env`, fill it in and add
`-f ../../addons/notify/compose.yaml`. The file must be readable by uid 1000 in the agent.

Existing Quadlet instance without rerunning `setup.sh`: same as for
[git-remote](../git-remote/README.md#setup), with `notify` and `quadlet/33-notify.conf`.

Test it from inside: `podman exec -u agent <name> notify --test`.

## Examples

```bash
# ntfy on your own server, reachable on the tailnet
NOTIFY_SERVICE=ntfy
NOTIFY_URL=https://ntfy.example.org/claude
NOTIFY_TOKEN=tk_...
NOTIFY_PRIVATE_IP=100.101.102.103

# Discord
NOTIFY_SERVICE=discord
NOTIFY_URL=https://discord.com/api/webhooks/123/abc
```

Inside the sandbox: `notify "message"`, `notify -t "Title" -p high "message"`
(priority `low`, `default`, `high`).
