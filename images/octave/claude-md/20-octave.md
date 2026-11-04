## Octave (MATLAB-compatible)

- GNU Octave, run headless: `octave-cli script.m` or `octave-cli --eval '…'`. There is no
  MATLAB and no MATLAB license here; write code that runs in Octave. If the user's code
  needs a MATLAB-only feature or toolbox, say so instead of faking it.
- Keep code MATLAB-compatible unless the project says otherwise: avoid Octave-only syntax
  (`#` comments, `!=`, `++`, `endif`/`endfunction`, double-quoted strings with escapes).
- Preinstalled packages (load with `pkg load <name>`): signal, statistics, control,
  optim, io, image, symbolic. More: `pkg install -forge <name>` (persists in
  `~/.local/share/octave`); don't install packages without asking.
- Plots: no screen. Use invisible figures and save them:
  `figure("visible", "off"); plot(x, y); print("-dpng", "fig.png")`. If printing fails,
  `graphics_toolkit("gnuplot")` works without a display.
- Tests: built-in `%!test` / `%!assert` blocks run with `test("myfunc")`; scripts with
  `assert(...)` calls run with `octave-cli tests/run_tests.m`.
