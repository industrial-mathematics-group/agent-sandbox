# sandbox.env

The agent container's environment. **Everything in it is visible to the agent**: put no
secrets here. Quadlet: `~agent-sandbox/.config/agent-sandbox/<name>/sandbox.env`; Compose:
`deploy/compose/sandbox.env`. Changes take effect on a restart.

| Key | Default | |
|---|---|---|
| `TZ` | `Etc/UTC` | Time zone. |
| `JULIA_NUM_THREADS` | `auto` | Julia threads. |
| `JULIA_PKG_SERVER` | | Regional Julia package server (set it in `gateway.env` too, so it is allowlisted). |
| `VIRTUAL_DISPLAY` | `1` | `-utils` flavors: `0` turns the virtual display off. |
| `XVFB_RESOLUTION` | `1920x1080x24` | Size of the virtual display. |
| `KEEP_GROUPS` | | `1` keeps the host user's supplementary groups (set by the AMD GPU drop-in for `video`/`render`). |

Any other variable you add is passed to the agent as is. The agent CLI versions are not
here: `CLAUDE_CODE_VERSION` is in `claude-code.env`, `CODEX_VERSION` in `codex.env`.

Set elsewhere, not by this file: `HTTP_PROXY`/`HTTPS_PROXY` (the gateway proxy, in the
image), and in the units / Compose file `NODE_OPTIONS=--max-old-space-size=4096` and git's
`safe.directory=*` (project files are owned by two host users).
