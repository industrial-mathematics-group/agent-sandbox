# github-app: GitHub access as a GitHub App

Lets the agent push, pull and use `gh` on GitHub as a
[GitHub App](https://docs.github.com/en/apps/overview) owned by your organization,
instead of with a personal access token. Commits and pull requests show up as the App's
bot (`my-app[bot]`), the App takes no seat, its permissions are set per repository, and
the agent only ever holds tokens that expire after an hour.

How it works:

- The App's **private key stays in the gateway**. `github-app.pem` is mounted into the
  gateway container only; the agent container never sees it, and inside the gateway it
  is copied to the broker's own user (`ghapp`, no capabilities).
- The gateway runs a small **token broker** on `127.0.0.1:3129`. The agent shares the
  gateway's network namespace, so it can reach it there; nothing outside can (loopback
  only, the firewall is unchanged). On request the broker signs an App JWT, exchanges it
  for an installation token (`POST /app/installations/{id}/access_tokens`, through the
  gateway's own proxy) and caches it until 10 minutes before it expires.
- In the agent, `/etc/gitconfig` gets a **credential helper** for `https://github.com`
  that asks the broker for a token whenever git needs one, and a **`gh` wrapper** sets
  `GH_TOKEN` to a fresh token on every call. Nothing is stored in the agent; `git@`
  URLs are rewritten to HTTPS.
- Commits are made as the App's bot user, so GitHub links them to the App (override with
  `GITHUB_APP_AUTHOR_NAME` / `GITHUB_APP_AUTHOR_EMAIL`).
- Each token can be narrowed below what the installation allows, to some repositories
  (`GITHUB_APP_REPOSITORIES`) and permissions (`GITHUB_APP_PERMISSIONS`).

**What this protects and what not:** the agent can still ask the broker for tokens while
it runs, and can use (or leak) a token until it expires. What it can't do is take away a
credential that outlives the sandbox: a leaked token is dead within the hour, the key
never leaves the gateway, and uninstalling the App (or stopping the gateway) cuts access
at once. Branch protection is still the real guard: let the App push branches and open
pull requests, and keep merging to the default branch for people.

## 1. Create the App (once per organization)

Organization → **Settings → Developer settings → GitHub Apps → New GitHub App**
(`https://github.com/organizations/ORG/settings/apps/new`):

- **GitHub App name:** e.g. `ORG-agent`. Commits will show as `ORG-agent[bot]`.
- **Homepage URL:** anything, e.g. your organization's page.
- **Webhook:** untick **Active** (the sandbox needs no events).
- **Repository permissions**, only what the agent needs:
  - **Contents: Read and write** (push branches)
  - **Pull requests: Read and write** (open and update PRs)
  - **Metadata: Read-only** (required, set automatically)
  - optional: **Issues: Read and write**; **Workflows: Read and write** only if the agent
    should change files in `.github/workflows/` (GitHub refuses those pushes otherwise);
    **Actions: Read-only** to let it read CI results.
- **Where can this GitHub App be installed?** **Only on this account.**

Create it, then on its settings page:

- note the **App ID** (or the Client ID, `Iv23…`; either works),
- **Private keys → Generate a private key**: your browser downloads a `.pem` file. It is
  the App's only secret; keep it off shared disks and delete the download once it is in
  place (below). You can add a second key and delete the old one any time to rotate it.

## 2. Install it on the repositories

App settings → **Install App** → your organization → **Only select repositories** and
pick the ones the agent should work on. You can change the selection later
(Organization → Settings → GitHub Apps → the App → Configure) without touching the
sandbox. The number at the end of that page's URL is the installation ID; you only need
it if you don't want the broker to look it up from the organization name.

One App can serve several sandboxes. To keep one sandbox to fewer repositories than the
installation covers, set `GITHUB_APP_REPOSITORIES` in that sandbox's `github-app.env`.

## 3. Set up the sandbox

Quadlet: `setup.sh … --addon github-app`, or `setup.sh add-addon <name> github-app` for an
existing instance. Then, as the sandbox user:

```bash
nano ~/.config/agent-sandbox/<name>/github-app.env    # GITHUB_APP_ID, GITHUB_APP_OWNER
# the .pem you downloaded (from your account: sudo cp, then chown to the sandbox user)
install -m 600 /path/to/ORG-agent.private-key.pem ~/.config/agent-sandbox/<name>/github-app.pem
systemctl --user restart <name>-gateway
```

`setup.sh` leaves an empty `github-app.pem` as a placeholder (so the gateway starts
without it); the broker only starts once a valid key is there.

Compose: copy `github-app.env.example` to `deploy/compose/github-app.env`, put the key at
`deploy/compose/github-app.pem` and add `-f ../../addons/github-app/compose.yaml`. The
gateway's root has no `CAP_DAC_OVERRIDE`, so it must own the key: rootful Docker
`sudo chown root:root github-app.pem && sudo chmod 400 github-app.pem`; rootless Podman
(`compose.podman.yaml`) your own file at mode 600.

Existing Quadlet instance without rerunning `setup.sh` (it rewrites the units): copy
`bin/`, `claude.md` and `entrypoint.d/` to `~/.config/agent-sandbox/addons/github-app/`,
`github-app.env.example` to `~/.config/agent-sandbox/<name>/github-app.env` (mode 600),
the key to `~/.config/agent-sandbox/<name>/github-app.pem` (mode 600),
`quadlet/34-github-app.conf` to `<name>.container.d/`, `quadlet/gateway/51-github-app-key.conf`
to `<name>-gateway.container.d/`, and `deploy/quadlet/addon-gateway.conf` to
`<name>-gateway.container.d/50-addon-github-app.conf`, replacing `@ADDON_DIR@`,
`@CONFIG_DIR@`, `@NAME@` and `@ADDON@` in all three.

The broker is part of the gateway image: pull a current one (`podman auto-update`, or
`docker compose pull`) if the gateway log doesn't mention it.

The gateway log shows `github-app: token broker on 127.0.0.1:3129 for github.com …` (or
why it didn't start), and later one line per new token. The agent log shows
`github-app: credentials for https://github.com from the gateway (App ORG-agent), commits as ORG-agent[bot]`.

## Use (inside the sandbox)

```bash
github-app info                    # host, App, commit identity, repositories, permissions
github-app clone ORG/repo
git push -u origin my-branch       # the credential helper fetches a token
gh pr create --fill                # the gh wrapper sets GH_TOKEN
gh api repos/ORG/repo/pulls
GH_TOKEN= gh …                     # a GH_TOKEN you set yourself wins over the wrapper
github-app token                   # a raw token, for tools that can't use git or gh
```

Installation tokens act as the App, not as a user: `gh auth status`, `gh api user` and
other user-only endpoints answer "Resource not accessible by integration".

## Settings (`github-app.env`)

| Key | |
|---|---|
| `GITHUB_APP_ID` | App ID or Client ID (required) |
| `GITHUB_APP_OWNER` | Organization or user the App is installed on |
| `GITHUB_APP_INSTALLATION_ID` | Instead of `GITHUB_APP_OWNER` |
| `GITHUB_APP_REPOSITORIES` | Narrow tokens to these repositories (names, space/comma separated) |
| `GITHUB_APP_PERMISSIONS` | Narrow tokens to these permissions, e.g. `contents:write,pull_requests:write` |
| `GITHUB_APP_AUTHOR_NAME`, `GITHUB_APP_AUTHOR_EMAIL` | Commit identity (default: the App's bot user) |
| `GITHUB_APP_HOST`, `GITHUB_APP_API_URL` | GitHub Enterprise Server only |

The file holds no secret and is only mounted into the gateway, which also allowlists
`GITHUB_APP_HOST` from it (github.com is on the base list anyway).

## With git-remote

Both can be on: git-remote for your Forgejo, github-app for GitHub. If both are set up
for the same host, github-app's credential helper wins for it (its hook runs later) and
`git-remote gh` still uses the PAT.

## Troubleshooting

- `no private key` / `not a valid private key` in the gateway log: `github-app.pem` is
  empty or not the downloaded `.pem`.
- `… is not readable by the gateway`: the key belongs to someone else than the gateway's
  root (Compose with rootful Docker: `chown root:root`, see above).
- `the App is not installed on 'ORG' (or GITHUB_APP_ID or the private key is wrong)`:
  check the ID, that the key belongs to this App, and that the App is installed.
- `A JSON web token could not be decoded` / `'Expiration time' claim … is too far in the
  future`: wrong key, or the host's clock is off by more than a minute.
- `There is at least one repository that does not exist or is not accessible` /
  `The permissions requested are not granted`: `GITHUB_APP_REPOSITORIES` or
  `GITHUB_APP_PERMISSIONS` asks for more than the installation has.
- `refusing to allow a GitHub App to create or update workflow … without workflows
  permission`: grant **Workflows: Read and write**, or keep the agent out of
  `.github/workflows/`.
- Debug inside the gateway: `podman exec <name>-gateway su -s /bin/sh ghapp -c 'github-app-broker token'`
  (prints a token).
