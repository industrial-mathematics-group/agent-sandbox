## Julia

- Latest stable Julia at `/usr/local/bin/julia`. Always work in project environments
  (`julia --project`); don't add packages to the global environment.
- `Pkg.instantiate()` after dependency changes. Don't add dependencies or change
  `[compat]` without asking.
- `~/.julia` (packages, precompile cache) persists.
