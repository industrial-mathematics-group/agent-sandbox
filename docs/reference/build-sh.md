# build.sh

Builds agent-sandbox images locally (Podman, Docker or Buildah) and in CI.

```bash
./build.sh --list                    # what exists
./build.sh full                      # one flavor
./build.sh node julia gateway        # several
./build.sh --registry ghcr.io/me --tag-suffix -amd64 --push node
./build.sh --engine buildah node     # daemonless (CI runners without Docker)
```

Images are tagged `<registry>/agent-sandbox:<flavor>` and
`<registry>/agent-sandbox-gateway:latest|tailscale`; the default registry is `localhost`.

## Targets

| Target | Chain |
|---|---|
| `minimal` / `minimal-utils` | base (+utils) |
| `node` / `node-utils` | base, node (+utils) |
| `julia` / `julia-utils` | base, julia (+utils) |
| `octave` / `octave-utils` | base, octave (+utils) |
| `full` / `full-utils` | base, node, julia (+utils) |
| `full-rocm` | base, node, julia, +utils, +rocm |
| `gateway` | gateway (plain) |
| `gateway-tailscale` | gateway (Tailscale exit node) |

Each step is a normal `podman/docker build` with `--build-arg BASE=<previous step>`, so
nothing is engine-specific. Shared prefixes (base, base + node, ...) are built once per run
and come from the build cache after that.

## Options

| Option | |
|---|---|
| `--engine podman\|docker\|buildah` | Default: Podman if installed, otherwise Docker (or `$ENGINE`). |
| `--registry REG` | Registry prefix of the tags (default `localhost`). |
| `--tag-suffix SUFFIX` | Appended to every tag, e.g. `-amd64`. |
| `--push` | Push after building. |
| `--list` | List the targets and their chains. |

## Environment

| Variable | |
|---|---|
| `JULIA_VERSION`, `NODE_VERSION`, `UV_VERSION`, `ROCM_VERSION`, `ROCM_SUITE` | Version pins, passed as build args when set. |
| `EXTRA_BUILD_FLAGS` | Appended to every build, e.g. `--network host` behind a proxy. |
