## Notifications (`notify`)

You can send the user a push notification:

```bash
notify "Benchmarks done: 3 of 40 cases regressed, see bench/report.md"
notify -t "Build failed" -p high "CI is red on main: missing dependency"
```

The user may get automatic notifications when you need them or finish, so use `notify`
only for things worth interrupting them for: a long task that finished, a result they
are waiting for, or a blocker. Keep messages short and never put secrets in them.
