# Updates and maintenance

## Images

=== "Quadlet"

    The units carry `AutoUpdate=registry`. Enable the timer once as the sandbox user and
    new images are pulled and the services restarted automatically:

    ```bash
    systemctl --user enable --now podman-auto-update.timer
    podman auto-update            # by hand
    ```

=== "Compose"

    ```bash
    docker compose pull && docker compose up -d
    ```

Images are rebuilt on every push to `main` and weekly (new Julia releases, base image
fixes). Each is also tagged `<flavor>-YYYYMMDD` if you want to pin a date.

## Claude Code and Codex

The CLIs are installed at container start, so a restart updates them:

- `CLAUDE_CODE_VERSION` in `claude-code.env`: `stable` (default), `latest`, or an exact
  version.
- `CODEX_VERSION` in `codex.env`: `latest` (default) or an exact version.

Channels are checked at most once a day, and a failed download keeps the installed
version. To force a check, delete `/opt/claude-code/.checked-*` or
`/opt/codex/.checked-latest` as root in the container and restart it.

## Resetting state

Stop the sandbox, then remove the volume you want to reset, e.g.:

```bash
podman volume rm agent-sandbox-julia-depot
```

The volumes are listed in [Paths and volumes](../reference/paths-volumes.md). Most are
shared by all instances on the machine.
