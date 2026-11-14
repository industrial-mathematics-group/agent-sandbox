# Concepts

An instance of agent-sandbox is built from four kinds of parts:

```mermaid
flowchart LR
    subgraph image["Agent image (one flavor)"]
        base["base<br/>shell, build tools, Python + uv"] --> lang["language layer<br/>node / julia / octave"]
        lang --> utils["utils layer (-utils)<br/>Xvfb, Mesa, Chromium"]
        utils --> final["final step<br/>proxy settings, notes"]
    end
    subgraph instance["Instance"]
        agent["agent container"] -- "shares network namespace" --> gw["gateway container<br/>firewall + proxy"]
        addons["add-ons<br/>claude-code, codex, github-app, ..."] -. "mounted into" .-> agent
        addons -. "env file allowlists hosts" .-> gw
    end
    image --> agent
    gw --> internet(("allowlisted hosts"))
```

- **[Images](images.md):** the agent container's image, a chain of layers chosen by the
  *flavor*. Headless core images and `-utils` variants with a display and Chromium.
- **[Gateway and network](gateway.md):** the sidecar that owns the network namespace,
  runs the firewall and the filtering proxy, and decides what gets out.
- **[Add-ons](addons.md):** per-instance features mounted into the containers at start:
  the coding agent itself, Git access, notifications, GPUs, clusters.
- **[Isolation and limits](isolation.md):** what the sandbox keeps the agent away from,
  and what it can't.
