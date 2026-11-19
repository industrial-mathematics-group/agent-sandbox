# codex

*OpenAI Codex in the sandbox.*

Installs the [Codex CLI](https://developers.openai.com/codex/cli) when the container
starts and mounts its home folder, `~/.codex`. Works next to
[claude-code](claude-code.md) or alone.

- **The CLI** is not in the image. At start, the add-on's hook runs
  `libexec/install-codex` as root and installs into the named volume
  `agent-sandbox-codex-cli` at `/opt/codex` (root-owned, shared by all instances). It
  takes the native binary from the `@openai/codex` platform package on the npm registry,
  the same files `npm i -g @openai/codex` installs, checked against the registry's sha512
  checksum, but without needing Node: it works in every flavor. `codex` is linked into
  `/opt/agent-sandbox/bin` (on `PATH`).
- **`CODEX_VERSION`** in `codex.env`: `latest` (default, checked at most once a day) or an
  exact version such as `0.167.2`. A failed download keeps the installed version.
- **`~/.codex`** (`config.toml`, `auth.json`, sessions): by default the host folder
  `~/.config/agent-sandbox/codex/` of the sandbox user, shared by all instances.
  `setup.sh --codex-config /path` (or a volume name) changes it; Compose mounts
  `./codex` (`CODEX_CONFIG` in `.env`).
- **Codex's own sandbox is off** (`sandbox_mode = "danger-full-access"`): its bubblewrap /
  Landlock sandbox can't run in a rootless container with all capabilities dropped, and
  the container plus the gateway already are the sandbox. Approvals stay as you configure
  them; `codex --dangerously-bypass-approvals-and-sandbox` (`--yolo`) is the counterpart
  of `claude --dangerously-skip-permissions`.
- **System config:** the hook writes `/etc/codex/config.toml` (root-owned): the sandbox
  mode from `CODEX_SANDBOX_MODE`, no update checks, logins stored as a file, and the
  sandbox's environment notes (the same text Claude Code gets as its managed CLAUDE.md) as
  `developer_instructions`. Your `~/.codex/config.toml` wins over each of these keys, so
  don't set `sandbox_mode` or `developer_instructions` there if you share it with your
  host.
- **Firewall:** the gateway reads `codex.env` and allowlists `api.openai.com` (API keys),
  `auth.openai.com` and `chatgpt.com` (ChatGPT login and its Codex backend) and
  `registry.npmjs.org` (downloads). With an exact `CODEX_VERSION` already installed you
  can drop `CODEX_DOWNLOAD_HOST`; an allowed npm registry is also a way to publish
  packages.

## Codex as a reviewer

Claude Code reads `CLAUDE.md` and not `AGENTS.md`; Codex reads `AGENTS.md`
(`~/.codex/AGENTS.md`, then every `AGENTS.md` from the git root down to the working
directory) and not `CLAUDE.md`. Both get the sandbox's environment notes on top.

To have Codex review code that Claude writes, give it **its own instance** rather than
the same workspace: it reviews what is on GitHub, with read-only access, and shares no
files, caches or logins with the instances where the code is written. A rule like "treat
the workspace as read-only" would only be an instruction (Codex's own sandbox is off
here); separate instances make it a fact.

1. A separate sandbox user, so not even the shared cache volumes (Julia depot, `~/.cache`)
   are shared:
   ```bash
   sudo useradd -m codex-sandbox
   ```
2. The instance, with Codex and GitHub access but without Claude Code:
   ```bash
   ./setup.sh --registry ghcr.io/OWNER --sandbox-user codex-sandbox \
              --name julia-checker --flavor julia --addon codex --addon github-app
   ```
3. GitHub access read-only, in `~codex-sandbox/.config/agent-sandbox/julia-checker/github-app.env`
   (see [github-app](github-app.md)): `GITHUB_APP_PERMISSIONS=contents:read,pull_requests:read`
   and the repositories in `GITHUB_APP_REPOSITORIES`. An App created with only these
   permissions is safer still, since then no setting can grant more.
4. The reviewer instructions as Codex's global `AGENTS.md`, from
   `example-reviewer-AGENTS.md`:
   ```bash
   sudo install -o codex-sandbox -g codex-sandbox -m 644 addons/codex/example-reviewer-AGENTS.md \
           ~codex-sandbox/.config/agent-sandbox/codex/AGENTS.md
   ```
   Global, because the clones in `/workspace` are separate git repositories and Codex
   would not read a `/workspace/AGENTS.md` from inside them.

Codex then clones with `github-app clone`, can't push or comment, and writes its reports
to `/workspace/reviews/<repo>/` (on the host:
`/var/srv/agent-sandbox/julia-checker/reviews/`). To let it post its reviews on pull
requests, add `pull_requests:write`; it still can't push code.

## Login

Codex's browser login waits for a redirect to `localhost:1455` on the machine running
it, which doesn't work in a headless container. Two ways that do:

1. **Log in on your own machine and copy `auth.json` (recommended).** Make Codex keep the
   login in a file (`cli_auth_credentials_store = "file"` in `~/.codex/config.toml`, the
   default unless a keyring is in use), run `codex login`, then copy the file into the
   sandbox's Codex folder:
   ```bash
   sudo install -o agent-sandbox -g agent-sandbox -m 600 ~/.codex/auth.json \
        ~agent-sandbox/.config/agent-sandbox/codex/auth.json
   ```
   The sandbox refreshes the token itself from then on. Copy it, don't bind-mount your own
   `~/.codex`: the agent can read the file, and the two copies refreshing the same login
   can log each other out (log in again on one side, or use a separate login).
2. **Device code, inside the sandbox:** `podman exec -it -u agent <name> codex login --device-auth`,
   then open the shown URL on any device and enter the code. Device-code login has to be
   enabled for your ChatGPT account or workspace (ChatGPT security settings).

API key instead of ChatGPT: `printenv OPENAI_API_KEY | podman exec -i -u agent <name> codex login --with-api-key`
(stored in `~/.codex/auth.json`). Don't put the key into `sandbox.env`, where every
process sees it.

**The agent can read `auth.json`** like Claude's login in `~/.claude`. Use an account or
key you'd trust a coding agent with.

## Setup

Quadlet: `setup.sh … --addon codex` (plus `--addon claude-code` to keep Claude), log in as
above, start. An existing instance: `setup.sh add-addon <name> codex` (it keeps Claude Code; drop that
with `setup.sh remove-addon <name> claude-code`).

Compose, in `deploy/compose`:

```bash
cp ../../addons/codex/codex.env.example codex.env
mkdir -p codex && cp ~/.codex/auth.json codex/      # or log in with --device-auth later
docker compose -f compose.yaml -f ../../addons/codex/compose.yaml up -d
docker compose exec -u agent agent codex
```

`codex/` and `codex.env` must be readable (and `codex/` writable) by uid 1000 in the agent:
your own user with `compose.podman.yaml`, otherwise `chown -R 1000 codex codex.env`.

The agent log shows `Codex <version> ready`; `codex doctor` inside the sandbox checks the
config, login and the endpoints (its WebSocket probe may warn; Codex falls back to HTTPS).

`failed to read CODEX_HOME "/home/agent/.codex": Permission denied` at start came from the
installer, which runs as root and can't enter the agent's `~/.codex`; it was harmless and
current versions give the installer a home of its own. If `codex` itself says it as
`agent`, the Codex folder belongs to someone else: as the sandbox user,
`ls -ld ~/.config/agent-sandbox/codex` must show the sandbox user (fix:
`sudo chown -R <sandbox user>: ~<sandbox user>/.config/agent-sandbox/codex && chmod 700 …`).
