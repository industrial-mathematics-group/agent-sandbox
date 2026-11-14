# Development

## Repository layout

| Folder | |
|---|---|
| `images/` | `base`, the language images (`node`, `julia`, `octave`) and `final` |
| `layers/` | General layers: `utils` (Xvfb, Mesa, Chromium), `rocm` |
| `gateway/` | Gateway image: firewall, proxy, allowlists, github-app token broker |
| `addons/` | Specific add-ons, one folder each |
| `deploy/quadlet/` | Quadlet templates and `setup.sh` |
| `deploy/compose/` | Compose files and env examples |
| `tests/smoke.sh` | Smoke test of an image against the gateway |
| `docs/` | This site (Zensical) |

## CI

`.github/workflows/build.yml` builds every flavor for amd64 and arm64 on push to `main`,
weekly and on demand. It smoke-tests each image against the gateway (`tests/smoke.sh`),
pushes to `ghcr.io/<owner>`, merges multi-arch tags and signs them with cosign (keyless).
Pull requests build and test without pushing.

`.forgejo/workflows/build.yml` is a manual test build for a Forgejo instance: it builds the
flavors you pick and can push them to that instance's registry.

## Smoke test

```bash
./build.sh node-utils gateway
tests/smoke.sh node-utils localhost      # needs Docker
```

## Documentation

The site is built with [Zensical](https://zensical.org) from `docs/` and `zensical.toml`.
To preview it:

```bash
pip install zensical        # or: uv tool install zensical
zensical serve              # http://localhost:8000, rebuilds on change
```

`.github/workflows/docs.yml` builds the site on every pull request that touches it and
publishes it to GitHub Pages from `main`.

Each add-on folder keeps a short `README.md` that points to its page here, so error
messages and scripts can keep referring to `addons/<name>/README.md`.
