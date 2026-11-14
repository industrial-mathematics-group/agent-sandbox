## Headless browser

Headless `chromium` is installed (`/usr/bin/chromium`) for screenshots, console logs,
Playwright and Electron. WebGL works only via SwiftShader and Chromium's own sandbox
can't run here, so always pass
`--no-sandbox --use-angle=swiftshader --enable-unsafe-swiftshader` to Playwright or
Electron (Playwright: `chromium.launch({ args: [...] })`, or
`executablePath: '/usr/bin/chromium'`). A blank WebGL canvas usually means these flags
are missing. Playwright browser downloads go to `~/.cache/ms-playwright` (persistent).
