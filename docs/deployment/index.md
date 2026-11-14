# Deployment

| | |
|---|---|
| [Podman Quadlet](quadlet.md) | systemd user services under a dedicated user, set up by `setup.sh`. Recommended on Linux. |
| [Docker / Podman Compose](compose.md) | One Compose project per sandbox, configured with env files and overlays. |
| [Tailscale exit node](tailscale.md) | All egress only through one of your Tailscale exit nodes. Works with both. |
| [Updates and maintenance](updates.md) | Image updates, agent CLI updates, resetting state. |

The templates live in `deploy/quadlet` and `deploy/compose`.
