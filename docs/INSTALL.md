# Install & Verify

Camoufox for Termux is a **native Bionic build** (no glibc, no proot) — a real
Bionic-ELF Firefox engine. Install through the signed Termux APT repository;
everything else on this page is fallback.

## Requirements

- **Termux** (F-Droid or GitHub build), **aarch64** device
- Internet for the first install (key + packages + dependencies)
- `x11-repo` — Camoufox links GTK3, which lives in the x11 repo (step 1.2 covers it)
- Optional, for automation: `nodejs` (≥ 20) + `playwright-core`

> ⚠️ Do **not** install from Google Play's Termux — it is abandoned and ships an
> old `$PREFIX`/ABI. Use F-Droid or the GitHub release.

---

## 1. Easy install (recommended)

### 1.1 Add the signed repository (one command)

```bash
pkg install curl
curl -fsSL https://raw.githubusercontent.com/bd-loser/opencode-bionic/main/repo-setup.sh \
  | TERMUX_PACKAGE=camoufox bash
```

That script:

1. installs the repo signing key to `$PREFIX/etc/apt/trusted.gpg.d/`,
2. writes `deb [arch=aarch64] https://bd-loser.github.io/opencode-bionic stable main`,
3. runs `pkg update`, then `pkg install camoufox`.

It is safe to re-run, and it works on a **fresh Termux** (it creates the apt
`trusted.gpg.d` / `sources.list.d` directories first). If your connection drops,
it fails with a clear message rather than hanging — retry.

### 1.2 Enable `x11-repo` first (fresh-phone fix)

Camoufox depends on `gtk3`, and `gtk3` only exists once the **x11** repository
is enabled. On a brand-new Termux, `pkg install camoufox` alone can fail to
resolve `gtk3`. Do this once:

```bash
pkg install x11-repo
```

The `.deb` also declares `Depends: x11-repo, gtk3, …` (see
[camoufox-termux#1](https://github.com/bd-loser/camoufox-termux/issues/1)), so
apt will pull `x11-repo` for you on a machine that already has apt metadata —
but running the line above makes the fresh case deterministic.

### 1.3 Install and verify

```bash
pkg update
pkg install camoufox      # or: pkg install -y --allow-downgrades camoufox
camoufox --version
```

Expected (version tracks the current release):

```text
Camoufox Camoufox 159.0-beta.35
```

- Engine: `$PREFIX/opt/camoufox/` · launcher: `camoufox` (on `PATH`)
- Update later with `pkg upgrade camoufox` (or `pkg upgrade`)
- The dependency closure (`gtk3`, `libnspr`, `libnss`, `libevent`, `libwebp`,
  …) is installed automatically, and is regenerated from `libxul.so`'s NEEDED
  set at build time so it cannot drift.

### 1.4 Uninstall

```bash
pkg uninstall camoufox
rm -rf ~/.camoufox          # profile/prefs, only if you want a clean slate
```

---

## 2. Verify it really works

```bash
camoufox --version            # loader + XPCOM boot
```

Then a quick headless run (no X server needed):

```bash
camoufox --headless --no-remote --profile ~/.camoufox-test \
  --screenshot ~/shot.png "about:support" && ls -l ~/shot.png
```

If `--version` prints `Couldn't load XPCOM`, the install layout is wrong — the
APT package is correct by construction, so this only happens for manual
tar/zip installs (see below).

---

## 3. Playwright on Termux

playwright-core refuses `process.platform === "android"`; patch the platform at
Node start:

```bash
mkdir -p ~/jtest && cd ~/jtest && npm i playwright-core
cat > pw-linux.cjs <<'EOF'
const os = require('os');
Object.defineProperty(process, 'platform', { value: 'linux' });
os.platform = () => 'linux';
EOF

cat > t.js <<'EOF'
const { firefox } = require('playwright-core');
(async () => {
  const b = await firefox.launch({
    executablePath: process.env.PREFIX + '/opt/camoufox/camoufox-bin',
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

Verified on-device: engine launches, title reads, screenshot PNG written.

---

## 4. Other install methods (fallbacks)

Prefer APT. Use these only if you cannot use the repository.

### A. pacman (Termux pacman users)

```bash
# download camoufox-<ver>-aarch64.pkg.tar.xz from the bionic-latest release:
# https://github.com/bd-loser/camoufox-termux/releases
pacman -U camoufox-<ver>-aarch64.pkg.tar.xz
```

`x11-repo` must already be enabled (pacman has no repo-dependency mechanism).

### B. zip (no apt/pacman)

```bash
curl -fLO https://github.com/bd-loser/camoufox-termux/releases/download/bionic-latest/camoufox-<ver>-aarch64.zip
unzip camoufox-<ver>-aarch64.zip -d ~/browsers/camoufox
~/browsers/camoufox/install.sh
~/browsers/camoufox/camoufox-bin --version
```

### C. tar.xz tree (side-by-side / testing)

```bash
curl -fLO https://github.com/bd-loser/camoufox-termux/releases/download/bionic-latest/camoufox-<ver>-aarch64-tree.tar
curl -fLO https://github.com/bd-loser/camoufox-termux/releases/download/bionic-latest/camoufox-<ver>-aarch64-tree.tar.sha256
sha256sum -c camoufox-<ver>-aarch64-tree.tar.sha256
mkdir -p ~/browsers/camoufox-test
tar -xf camoufox-<ver>-aarch64-tree.tar -C ~/browsers/camoufox-test
~/browsers/camoufox-test/camoufox/camoufox-bin --version
```

Always verify the `.sha256` sidecar for manual formats; APT verifies for you.

---

## 5. Troubleshooting (fresh Termux)

| Symptom | Cause | Fix |
|---|---|---|
| `Unable to locate package camoufox` | repo not added yet / stale metadata | run step 1.1, then `pkg update` |
| apt cannot resolve **`gtk3`** | x11 repo not enabled | `pkg install x11-repo` (step 1.2), then retry |
| `library libplds4.so not found` at runtime | old package metadata (pre-#1 fix) missing `libnspr`/`libnss` | `pkg update && pkg upgrade camoufox` — current packages declare the full closure |
| `Couldn't load XPCOM` | wrong layout (manual install) | use APT, or keep `omni.ja` beside `camoufox-bin` |
| GPG / `NO_PUBKEY` on `pkg update` | key not installed or partial download | re-run step 1.1 (refetch key) |
| `curl: (6) Could not resolve host` / timeout | mobile link dropped | retry; the setup script fails fast by design |

Still stuck? Open an issue with the output of:

```bash
termux-info
pkg show camoufox
camoufox --version
```

---

## Notes

- Runs headless without an X server (`gfx.webrender.software`).
- Display rendering works with [Termux:X11](https://github.com/termux/termux-x11)
  if you want a real window.
- First launch creates `~/.camoufox` (profile) — keep `HOME` set.
- Supported device class: **aarch64 only** (the repo line is `arch=aarch64`).
