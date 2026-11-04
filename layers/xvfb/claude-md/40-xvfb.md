## Graphics (virtual display)

There is no screen. A virtual X display (`DISPLAY=:99`) with software OpenGL is running
(no GPU acceleration).

- **GLMakie / CairoMakie:** work headless. Save figures to files
  (`save("fig.png", fig)`), never rely on `display()` or windows.
- **WGLMakie / Bonito:** the user views it from another machine. Listen on all
  interfaces, port 9384:
  `Bonito.configure_server!(listen_url="0.0.0.0", listen_port=9384)`. Inbound ports
  only work if the user opened them.
- **ocp_vscode viewer:** `uv run python -m ocp_vscode --host 0.0.0.0 --port 3939`.
- `build123d` (or `build123d[novtk]` when VTK isn't needed) installs from wheels.
