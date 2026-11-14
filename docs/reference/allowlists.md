# Allowlists

The gateway always loads `base`, plus the profiles in `GATEWAY_PROFILES`, `extra.list`,
`GATEWAY_EXTRA_DOMAINS` and the hosts of every enabled add-on. The lists are in
`gateway/lists/*.list` and part of the gateway image.

| List | Hosts |
|---|---|
| `base` (always) | GitHub: `github.com`, `api.github.com`, `codeload.github.com`, `*.githubusercontent.com` |
| `python` | PyPI (`pypi.org`, `files.pythonhosted.org`), PyTorch wheels (`download.pytorch.org`) |
| `node` | npm, yarn, JSR, `nodejs.org`, Playwright downloads, Prisma engines, Google Fonts |
| `julia` | Pkg servers (`pkg.julialang.org`, `*.pkg.julialang.org`), Julia storage and binaries |
| `octave` | Octave Forge index and SourceForge downloads (`pkg install -forge`) |

`setup.sh` enables `python` and the flavor's language by default.

## Hosts added by add-ons

| Add-on | Hosts |
|---|---|
| [claude-code](../addons/claude-code.md) | `api.anthropic.com`, `claude.ai`, `console.anthropic.com`, `platform.claude.com`, `downloads.claude.ai` |
| [codex](../addons/codex.md) | `api.openai.com`, `auth.openai.com`, `chatgpt.com`, `registry.npmjs.org` |
| [github-app](../addons/github-app.md) | `GITHUB_APP_HOST` (GitHub Enterprise; github.com is in `base`) |
| [git-remote](../addons/git-remote.md) | `GIT_REMOTE_HOST`, the host of `GIT_REMOTE_API_URL` |
| [notify](../addons/notify.md) | The host of `NOTIFY_URL` |
| [gpu-remote](../addons/gpu-remote.md) | `GPU_HOST` |
| [slurm](../addons/slurm.md) | `SLURM_HOST` |

## Not enabled by default

Copy into `extra.list` if a project needs them:

```
conda.anaconda.org
repo.anaconda.com      # conda / CondaPkg.jl
huggingface.co
*.hf.co                # Hugging Face models and datasets
```
