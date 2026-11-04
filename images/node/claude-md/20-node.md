## Node.js

- Node LTS with `npm`, and `pnpm`/`yarn` through corepack. Use the package manager the
  project's lockfile points to; don't switch it.
- Install tools as project devDependencies and run them with `npx`/`pnpm exec`.
  Global installs (`npm install -g`) are lost on every update.
- Dev servers: listen on `0.0.0.0` (e.g. `vite --host 0.0.0.0`, `next dev -H 0.0.0.0`)
  so the user can open them. Only ports the user published or opened are reachable from
  outside; if a page isn't reachable, say so rather than trying other ports.
- `~/.npm` and `~/.cache` persist (npm cache, Playwright browsers).
