# Architecture

Goal: a Firefox-fork engine (Camoufox) as a **first-class Bionic ELF**, built automatically, installable without a compiler, debuggable without archaeology.

## Components

| Path | Role |
| --- | --- |
| `camofox/configure.sh` | The single source of truth for the build environment + configure + build + package |
| `camofox/audit-on-runner.sh` | Runner-side docker wrapper (mounts workspace/out, passes pins as argv) |
| `camofox/termux.mozconfig` | Termux mozconfig overlay (appended after Camoufox base) |
| `camofox/termux-patches/*.patch` | Our tree patches (numbered; see BUILD.md table) |
| `camofox/patch-audit.sh` | Phase-1 evidence tool: applies upstream 46 + termux 31 patch sets, reports per-patch pass/fail + rejects |
| `.github/workflows/camofox-build.yml` | ccache-backed build + package + artifact (sha256) |
| `.github/workflows/camofox-audit.yml` | Patch-apply audit (no build) |
| `camofox/NOTES.md` | The full error→root cause→fix ledger (source of TROUBLESHOOTING.md) |

## Why "everything in one script"

The build environment is a lattice: toolchain flavor (Termux clang/rust), wrapper (versioned triple), patch-time substitutions, and mozconfig all interact — splitting them produced drift during development. One script = one environment definition = reproducible runs; the CI workflow only adds cache + docker plumbing.

## Decision record (the three hard choices)

1. **Bionic-native over glibc-loader.** The alternative (private Debian glibc tree, cf. camoufox-termux-native) works but carries a foreign libc into every process (CrashReporter symbols, sandbox interplay, update coupling). Bionic-native removes the layer at the cost of upstream's untested territory — taken deliberately, with the ledger to back it.
2. **Termux toolchain sources from Termux repos** (clang/rust via `pkg`), never rustup/proot. Matches termux-packages' proven firefox recipe and keeps the phone-side runtime pure Termux.
3. **Mach package output shipped directly** (official `camoufox-*.tar.xz` + sha256 sidecar) rather than ad-hoc trees: guarantees the omni.ja/resource layout the loader expects.

## Patch layers (in apply order)

```
1. upstream:  daijro/camoufox patches (46) — via their scripts/patch.py (pinned)
2. termux:    termux-packages firefox patches (28 of 32 apply at 158; the 0031 pair is skipped only on the 156 line; placeholders substituted)
3. ours:      camofox/termux-patches/ (bionic-module guards, mozinfo, endian, threading…)
```

Rule from CONTRIBUTING: patches assert-exactly-once, carry rationale, and go through the checksum sweep.
