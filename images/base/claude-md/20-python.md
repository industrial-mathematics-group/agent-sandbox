## Python

- System `python3` is Debian's and "externally managed": never `pip install` into it.
- Use uv per project: `uv init`, `uv add <pkg>`, `uv sync`, `uv run python …`.
  `uv python install 3.13` if a project needs another interpreter.
- `~/.cache` (uv cache) and `~/.local/share/uv` (interpreters) persist.
- Don't add dependencies without asking.
