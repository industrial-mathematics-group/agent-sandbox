## Codex

The OpenAI Codex CLI (`codex`) is installed and updated by the container at start
(root-owned); don't try to install or update it. Its config, login and sessions live in
`~/.codex`, which persists. Codex's own sandbox is off here by default: the container
and its network gateway are the sandbox.
