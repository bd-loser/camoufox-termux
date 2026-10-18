# Install & Verify

## Requirements

- Termux (F-Droid / GitHub build), aarch64
- For headless rendering: `pkg install gtk3` (via `x11-repo`)
- For Playwright automation: `pkg install nodejs` (≥ 20) and `playwright-core`

## 1. Get the package

Builds are GitHub Actions artifacts ([camofox-build](https://github.com/bd-loser/camoufox-bionic/actions/workflows/camofox-build.yml)): download `camofox-build-out`, verify sha256, extract:

```bash
unzip "camofox-build-out (N).zip" -d camofox-pkg
sha256sum -c camofox-pkg/camoufox-*.tar.xz.sha256
mkdir -p ~/browsers/camoufox && tar -xJf camofox-pkg/camoufox-*.tar.xz -C ~/browsers/camoufox
```

## 2. Quick verification

```bash
~/browsers/camoufox/camoufox/camoufox-bin --version
# Camoufox Camoufox 156.0.1-beta.32   (= runs; Bionic ELF, no glibc)
```

`--version` proves the loader + XPCOM. If you get `Couldn't load XPCOM`, the package layout is wrong (must be `camoufox/omni.ja` beside `camoufox-bin`).

## 3. Playwright on Termux

playwright-core refuses `process.platform === "android"`; patch the platform at Node start:

```bash
cd ~/jtest && npm i playwright-core
cat > pw-linux.cjs <<'EOF'
const os = require('os');
Object.defineProperty(process, 'platform', { value: 'linux' });
os.platform = () => 'linux';
EOF

cat > t.js <<'EOF'
const { firefox } = require('playwright-core');
(async () => {
  const b = await firefox.launch({
    executablePath: process.env.HOME + '/browsers/camoufox/camoufox/camoufox-bin',
    headless: true,
    firefoxUserPrefs: {
      'network.process.enabled': false,
      'media.rdd-process.enabled': false,
      'gfx.webrender.software': true,
    },
  });
  const page = await b.newPage();
  await page.goto('https://example.org');
  console.log(await page.title());
  await page.screenshot({ path: 'shot.png' });
  await b.close();
})();
EOF
NODE_OPTIONS="--require $PWD/pw-linux.cjs" node t.js
```

Verified output on-device: engine launches, title reads, screenshot PNG written.

## Notes

- Runs fine headless without an X server (`gfx.webrender.software`).
- Display rendering works with [Termux:X11](https://github.com/termux/termux-x11) if you want a real window.
- First launch creates `~/.camoufox` (profile) — keep `HOME` set.
