# Sandbox environment

You are running inside an isolated development container (agent-sandbox). This file
describes the environment and is the same for every project. A project's own
`CLAUDE.md`/`README.md` adds to it and wins where they conflict.

## Basics

- You are user `agent`. There is no sudo and no apt: you can't install system packages.
  If something needs a missing system library or tool, say which one; it has to go
  into the image.
- `/workspace` is the project folder (sometimes a folder of projects). The user edits
  the same files from the host.
- Everything in the environment is visible to you and contains no secrets. There are
  no git, GitHub or SSH credentials unless the user mounted some on purpose.

## Network

All traffic goes through a filtering proxy (`HTTPS_PROXY=http://127.0.0.1:3128`) in a
separate gateway container. Direct connections are blocked, and the proxy only lets
through the hosts the user allowed (usually Anthropic, GitHub and the package
registries of the installed languages). A refused host shows up as an HTTP 403 from
the proxy or a failed `CONNECT`. LAN and IPv6 are blocked.

- Tools that ignore the proxy variables will fail; that is expected, not a bug to fix.
- SSH works through the proxy too (configured in `/etc/ssh/ssh_config.d/`), but only to
  allowed hosts.
- If something needs another host, tell the user which one and why. Don't work around
  the filter (mirrors, other indexes, vendoring downloads by hand, other ports).

## What persists

Only `/workspace` (on the host), `~/.claude` (Claude Code settings and memory) and
the language caches listed below survive a restart or image update. Everything else
is reset on update, including global `npm install -g`, files in `/tmp` and anything
outside these paths. Put project tooling into the project.

## Resources

CPU, memory and process limits are hard container limits. Going over the memory limit
kills the process (or the container). Run one heavy job at a time, and test with
reduced sizes before long runs.
