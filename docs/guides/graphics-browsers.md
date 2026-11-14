# Graphics, browsers, dev servers

The display and browser parts need a `-utils` flavor.

## Dev servers

Dev servers must listen on `0.0.0.0` inside the agent and use a published port
(`setup.sh --port 5173`, or `PORT_1`/`PORTS` in Compose). Open `http://localhost:5173`
(plain) or `http://<TS_HOSTNAME>:5173` ([Tailscale](../deployment/tailscale.md)).

These ports have no authentication: anyone who can reach them can use them.

## Virtual display and GLMakie

A virtual display (`DISPLAY=:99`) with Mesa software OpenGL starts with the container.
Save figures to files. `VIRTUAL_DISPLAY=0` in `sandbox.env` turns it off,
`XVFB_RESOLUTION` changes the size.

## WGLMakie / Bonito

Publish port 9384, then

```julia
Bonito.configure_server!(listen_url="0.0.0.0", listen_port=9384, proxy_url="http://<host>:9384")
```

and open `/browser-display`.

## Headless Chromium

There is no GPU, so WebGL runs on SwiftShader, and rootless containers can't provide
Chromium's sandbox. Debian's `chromium` picks up the right flags from
`/etc/chromium.d/container`; pass the same flags to Playwright or Electron:

```
--no-sandbox --use-angle=swiftshader --enable-unsafe-swiftshader
```

Without them, WebGL canvases render blank.

## Python CAD

```bash
uv add build123d ocp_vscode
uv run python -m ocp_vscode --host 0.0.0.0 --port 3939    # publish 3939
```

## GPUs

For real GPU work, see [gpu-local](../addons/gpu-local.md) (a GPU in this machine) and
[gpu-remote](../addons/gpu-remote.md) (a remote GPU server).
