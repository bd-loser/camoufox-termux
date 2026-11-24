# Camoufox for Termux — Bionic-native (Android aarch64)

**Native [Camoufox](https://github.com/daijro/camoufox) (anti-fingerprinting Firefox fork) for Termux/Android, built natively for Bionic.** No glibc layer, no proot, no root — a real Firefox-class engine compiled with the Termux toolchain and running directly in Termux.

```bash
# quick preview (artifact from CI; see Install below)
```

## Why this exists

Every Camoufox/Firefox build available for Termux until now worked around one problem: Firefox for "Linux ARM64" ships as a **glibc** binary, and Termux is a **Bionic** environment. Existing workarounds run the glibc binary under a private Debian loader (`LD_LIBRARY_PATH` trees like [camoufox-termux-native](https://github.com/Thr45hx/camoufox-termux-native)).

This project removes the workaround entirely: **we cross nothing and translate nothing — we build Firefox/Camoufox natively with the Termux toolchain** (clang/rust from Termux repos), inside `termux/termux-docker:aarch64` CI, producing a true Bionic-ELF engine.

```
Camoufox source (Firefox 159.0-beta.35 + anti-detect patches)
        │  termux-docker (aarch64) + Termux clang/rust + termux firefox patch set + 9 bionic patches
        ▼
Bionic ELF · /system/bin/linker64 · runs in Termux · no proot · no root
```

## Features

- **Bionic-native**: ELF with `/system/bin/linker64`, links Termux's own `libc`, `libc++_shared`, `libandroid-shmem`
- **Full Camoufox stack**: anti-fingerprint patches + Playwright **Juggler** protocol
- **Verified on-device** (one aarch64 phone): boot, DOM access, JS, headless **screenshot via Playwright**
- **CI-built & checksummed**: `sha256` on every artifact; nothing compiles on your phone
- **One-command host build**: reproducible CI scripts included

## Verified test matrix (real device)

| Test | Result |
| --- | --- |
| `camoufox-bin --version` | ✅ `Camoufox 156.0.1-beta.32` |
| XPCOM boot + omni.ja resource loading | ✅ |
| Juggler launch via `playwright-core` | ✅ |
| Navigate + DOM read (`title`, `h1`) | ✅ |
| Headless screenshot (Playwright) | ✅ PNG produced |

## Install

**Recommended: the signed Termux APT repository** (same repo that serves opencode-bionic):

```bash
pkg install curl x11-repo
curl -fsSL https://raw.githubusercontent.com/bd-loser/opencode-bionic/main/repo-setup.sh \
  | TERMUX_PACKAGE=camoufox bash
camoufox --version        # Camoufox Camoufox 159.0-beta.35
```

`x11-repo` is needed because Camoufox links GTK3 — enable it first on a fresh
Termux. Updates: `pkg upgrade camoufox`. Full guide + fresh-Termux troubleshooting:
[docs/INSTALL.md](docs/INSTALL.md).

<details>
<summary>Fallbacks (pacman / zip / tar.xz, or CI artifacts)</summary>

Release downloads (no login, permanent) live on the rolling `bionic-latest`
release and per-version `bionic-v<ver>` tags:
<https://github.com/bd-loser/camoufox-termux/releases>

```bash
BASE=https://github.com/bd-loser/camoufox-termux/releases/download/bionic-latest
VER=159.0b35
# zip
curl -fLO $BASE/camoufox-$VER-aarch64.zip && unzip camoufox-$VER-aarch64.zip -d ~/browsers/camoufox && ~/browsers/camoufox/install.sh
# tar.xz tree (verify first)
curl -fLO $BASE/camoufox-$VER-aarch64-tree.tar{,.sha256} && sha256sum -c camoufox-$VER-aarch64-tree.tar.sha256
mkdir -p ~/browsers/camoufox-test && tar -xf camoufox-$VER-aarch64-tree.tar -C ~/browsers/camoufox-test
```

CI artifacts ([camofox-build](https://github.com/bd-loser/camoufox-termux/actions/workflows/camofox-build.yml))
also exist but need a GitHub login and expire.

</details>


## Use with Playwright (Juggler)

```js
const { firefox } = require('playwright-core');
const b = await firefox.launch({
  executablePath: '~/browsers/camoufox/camoufox/camoufox-bin',
  headless: true,
});
const page = await b.newPage();
await page.goto('https://example.org');
```

> **Termux/Android only:** playwright-core hard-rejects `process.platform === "android"` — start Node with a 3-line preload (`NODE_OPTIONS="--require pw-linux.cjs"`) that reports the platform as linux. Full snippet: [docs/INSTALL.md](docs/INSTALL.md#playwright-on-termux).

## Known issues

- Stock CLI `--screenshot` used to hang on juggler builds (double teardown in `Helper.js`) — reported and **fixed upstream** in the Firefox 159 juggler rework ([daijro/camoufox#909](https://github.com/daijro/camoufox/issues/909), PR #997). The current 159-based builds ship that fix; reopen upstream if it still reproduces.

## Documentation

| Doc | Content |
| --- | --- |
| [docs/INSTALL.md](docs/INSTALL.md) | Install, verify, Playwright snippet |
| [docs/BUILD.md](docs/BUILD.md) | Full build guide (patches, toolchain, CI) |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Every build error → root cause → fix |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Pipeline design and patch map |

## Related

- [daijro/camoufox](https://github.com/daijro/camoufox) — upstream engine
- [Thr45hx/camoufox-termux-native](https://github.com/Thr45hx/camoufox-termux-native) — alternative glibc-loader approach (non-native)
- [bd-loser/hermes-bionic](https://github.com/bd-loser/hermes-bionic) — same CI philosophy for [Hermes Agent](https://github.com/NousResearch/hermes-agent) on Termux

## License

Build scripts, patches, and CI configuration in this repository: **MIT**. The Camoufox engine (built from upstream sources) is **MPL-2.0**; Firefox trademarks apply. See [LICENSE](LICENSE).
