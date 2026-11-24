# Camoufox for Termux — native Bionic build for Android (aarch64)

**Run [Camoufox](https://github.com/daijro/camoufox) — the anti-fingerprinting Firefox fork — natively on Android/Termux.** No glibc layer, no proot, no root: a real Firefox-class engine compiled with the Termux toolchain, running straight in Termux on `aarch64`.

[![Build](https://github.com/bd-loser/camoufox-termux/actions/workflows/camofox-build.yml/badge.svg?branch=main)](https://github.com/bd-loser/camoufox-termux/actions/workflows/camofox-build.yml)
[![Release](https://img.shields.io/badge/release-159.0b35-blue.svg)](https://github.com/bd-loser/camoufox-termux/releases)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Termux%20aarch64-success.svg)](#requirements)

## Install (one command)

```bash
pkg install curl x11-repo
curl -fsSL https://raw.githubusercontent.com/bd-loser/opencode-bionic/main/repo-setup.sh | TERMUX_PACKAGE=camoufox bash
camoufox --version        # Camoufox Camoufox 159.0-beta.35
```

Updates: `pkg upgrade camoufox`. Fresh-Termux help, fallbacks, and troubleshooting: **[docs/INSTALL.md](docs/INSTALL.md)**.

> **Need `x11-repo`?** Yes — Camoufox links GTK3, which lives in the Termux x11 repo. The line above enables it for you.

## What you get

- **Bionic-native** — ELF with `/system/bin/linker64`; links Termux's own `libc`, `libc++_shared`, `libandroid-shmem`. No Debian loader, no `LD_LIBRARY_PATH` tricks.
- **Full Camoufox** — anti-fingerprint patches plus the Playwright **Juggler** automation protocol.
- **Verified on real hardware** — boot, DOM, JS, headless screenshots, and Playwright navigation.
- **Checksummed CI builds** — nothing compiles on your phone; every artifact ships a `sha256`.

## Requirements

- **Termux** (F-Droid or GitHub build — **not** the Play Store build), **aarch64** device
- ~150 MB free for the engine + GTK3 dependencies

## Why it exists

Every other Camoufox/Firefox build for Termux wraps a **glibc** Linux-ARM64 binary in a private Debian loader. Termux is **Bionic**, so this project crosses nothing and translates nothing — we build Firefox/Camoufox natively with the Termux toolchain in `termux/termux-docker:aarch64` CI:

```
Camoufox source (Firefox 159.0-beta.35 + anti-detect patches)
        │  termux-docker (aarch64) + Termux clang/rust + Termux firefox patches + 9 bionic patches
        ▼
Bionic ELF · /system/bin/linker64 · runs in Termux · no proot · no root
```

## Automation (Playwright)

```js
const { firefox } = require('playwright-core'); // pin ~1.62 (see docs)
const b = await firefox.launch({
  executablePath: process.env.PREFIX + '/opt/camoufox/camoufox-bin',
  headless: true,
});
const page = await b.newPage();
await page.goto('https://example.org');
console.log(await page.title());
```

> **Android note:** `playwright-core` rejects `process.platform === "android"`; start Node with a tiny preload that reports `linux`. Full snippet + a known-good version: **[docs/INSTALL.md](docs/INSTALL.md#playwright-on-termux)**.

## Documentation

| Page | What's inside |
| --- | --- |
| **[Install & Verify](docs/INSTALL.md)** | APT install, fallbacks, Playwright, fresh-Termux troubleshooting |
| **[Build](docs/BUILD.md)** | Reproduce the build: patches, toolchain, CI pipeline, release flow |
| **[Troubleshooting](docs/TROUBLESHOOTING.md)** | Every build error → root cause → fix |
| **[Architecture](docs/ARCHITECTURE.md)** | Pipeline design and patch map |

## Related

- [daijro/camoufox](https://github.com/daijro/camoufox) — the upstream engine
- [bd-loser/hermes-bionic](https://github.com/bd-loser/hermes-bionic) — same CI approach, for Hermes Agent on Termux

## License

Build scripts, patches, and CI in this repository: **MIT**. The Camoufox engine is **MPL-2.0**; Firefox trademarks apply. See [LICENSE](LICENSE).
