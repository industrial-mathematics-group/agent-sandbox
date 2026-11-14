# Concepts

An instance of agent-sandbox is built from four kinds of parts:

```mermaid
flowchart TB
    subgraph image["Agent image (one flavor)"]
        direction LR
        base["base<br/>shell, build tools,<br/>Python + uv"] --> lang["language<br/>node / julia /<br/>octave"]
        lang --> utils["utils (-utils only)<br/>Xvfb, Mesa,<br/>Chromium"]
        utils --> final["final step<br/>proxy settings,<br/>notes"]
    end
    subgraph instance["Instance"]
        direction LR
        addons["add-ons<br/>claude-code, codex,<br/>github-app, ..."] -. "mounted" .-> agent["agent<br/>container"]
        agent -- "shares<br/>network" --> gw["gateway<br/>firewall + proxy<br/>→ allowlisted hosts"]
        addons -. "allowlist<br/>their hosts" .-> gw
    end
    image -- "runs as" --> instance
```

- **[Images](images.md):** the agent container's image, a chain of layers chosen by the
  *flavor*. Headless core images and `-utils` variants with a display and Chromium.
- **[Gateway and network](gateway.md):** the sidecar that owns the network namespace,
  runs the firewall and the filtering proxy, and decides what gets out.
- **[Add-ons](addons.md):** per-instance features mounted into the containers at start:
  the coding agent itself, Git access, notifications, GPUs, clusters.
- **[Isolation and limits](isolation.md):** what the sandbox keeps the agent away from,
  and what it can't.
