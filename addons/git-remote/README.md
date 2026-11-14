# git-remote: push, pull and API for one Git hosting account

Lets the agent push and pull over HTTPS and use the API of one account on GitHub,
Forgejo/Gitea or GitLab (hosted or your own server), without you setting up
credentials in every sandbox by hand.

- `git-remote.env` holds the service, host and personal access token (PAT). It is
  mounted read-only as a file, not passed as environment, so the token is not in every
  process's environment and logs.
- At start, the agent's entrypoint writes `/etc/gitconfig` (root-owned): a credential
  helper for `https://<host>` that reads the token from the file when git asks,
  `git@<host>:` URLs rewritten to HTTPS, and an optional commit identity.
- The gateway reads the same file and allowlists `GIT_REMOTE_HOST` (and the host of
  `GIT_REMOTE_API_URL`). If the server is on your LAN or tailnet, `GIT_REMOTE_PRIVATE_IP`
  lets its address through the block on private ranges (the gateway then still only
  allows that host name to it, on ports 80/443/22).
- `git-remote` (on the agent's `PATH`) clones, prints URLs and makes authenticated API
  calls; `git-remote gh …` runs `gh` with the token for GitHub.

For GitHub, the [github-app](../github-app/README.md) add-on is usually the better
choice: an App owned by your organization, tokens that expire after an hour, and a
private key that never enters the agent container.

**The agent can read the token**: it has to send it. Use a token that only covers what
the agent should touch, ideally a separate bot account:

| Service | Token | Minimal rights |
|---|---|---|
| GitHub | Fine-grained PAT (Settings → Developer settings) | Only the selected repositories; Contents read/write, Pull requests read/write |
| Forgejo / Gitea | Access token (Settings → Applications) | `write:repository` (+ `write:issue` for issues/PRs); set `GIT_REMOTE_USER` to the account name |
| GitLab | Project or personal access token | `read_repository`, `write_repository` (+ `api` for merge requests) |

Branch protection on the server is the real guard: let the token push branches and
open pull requests, and keep merging to the default branch for yourself.

## Setup

Quadlet: `setup.sh … --addon git-remote` (existing instance: `setup.sh add-addon <name> git-remote`), then fill in
`~/.config/agent-sandbox/<name>/git-remote.env` and restart
(`systemctl --user restart <name>-gateway`).

Compose: copy `git-remote.env.example` to `deploy/compose/git-remote.env`, fill it in and
add `-f ../../addons/git-remote/compose.yaml`. The file must be readable by uid 1000 in
the agent (with `compose.podman.yaml` that is your own user).

Existing Quadlet instance without rerunning `setup.sh` (it rewrites the units): copy
`bin/`, `claude.md` and `entrypoint.d/` to `~/.config/agent-sandbox/addons/git-remote/`,
`git-remote.env.example` to `~/.config/agent-sandbox/<name>/git-remote.env` (mode 600),
`quadlet/32-git-remote.conf` to `<name>.container.d/` and
`deploy/quadlet/addon-gateway.conf` to `<name>-gateway.container.d/50-addon-git-remote.conf`,
replacing `@ADDON_DIR@`, `@CONFIG_DIR@`, `@NAME@` and `@ADDON@` in both.

The gateway log shows `Add-on git-remote: allowing <host> …`, the agent log
`git-remote: credentials for https://<host>`.

## Use (inside the sandbox)

```bash
git-remote info                          # what is configured (never prints the token)
git-remote clone owner/repo
git push -u origin my-branch             # credentials are filled in by git
git-remote api GET /user
git-remote api POST /repos/owner/repo/pulls '{"title":"Fix","head":"my-branch","base":"main"}'   # GitHub, Forgejo
git-remote api POST /projects/owner%2Frepo/merge_requests '{"title":"Fix","source_branch":"my-branch","target_branch":"main"}'   # GitLab
git-remote gh pr create --fill           # GitHub only
```

One account per instance. GitHub over HTTPS is in the base allowlist already, so pushing
there only needs the token.
