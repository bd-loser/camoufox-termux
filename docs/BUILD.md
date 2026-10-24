# Build from source

Everything needed is inside this repository (`camofox/` — scripts, pins, patches; `.github/workflows/` — CI). A cold full build takes ~70–80 min on a 4-core ARM runner; warm (objdir persisted) is minutes.

## Pipeline

```
GitHub Actions (ubuntu-24.04-arm)
 └─ docker run termux/termux-docker:aarch64
     └─ ci steps in camofox/configure.sh:
        1. toolchain   (termux clang/rust/node, NO rustup)
        2. fetch       (camoufox @ pinned SHA → Firefox 158.0 sdist)
        3. apply       upstream patches (their scripts/patch.py, rustup stubbed)
        4. apply       termux patches (28 clean incl. 0031 pair + our rebased 4; the 0031 pair is
                       skipped only on the 156 line — code it fixes exists from 157 on)
        5. checksums   vendored .cargo-checksum.json sweep (must after any crate edit)
        6. wrapper     clang/clang++ → versioned triple (aarch64-unknown-linux-android24),
                       strips incoming --target= and -DANDROID
        7. mozconfig   base.mozconfig + termux.mozconfig (see below)
        8. configure   ./mach configure            (~1 min, exit 0)
        9. build       ./mach build -j4            (~35–70 min cold; ccache-assisted)
       10. package     ./mach package              (omni.ja + tar.xz + sha256)
```

## Pins

| Thing | Value |
| --- | --- |
| Camoufox repo | `c9ed439d49948cc8e4335aee6bea1a7b23dc4d2d` (v158.0-beta.40 → Firefox 158.0-beta.33) |
| termux-packages | `e2b25a170e34052eb30fdb64da0593bc69499ca9` (x11-packages/firefox @ 158.0 era + 0031 ioprio-android fix) |
| primp sdist | sha256 `82ba17b0…` (if building the ddgs stack) |

Update by editing the workflow env; the scripts refuse un-pinned fetches.

## Key mechanics (each was a real failure)

### Versioned triple wrapper
Termux clang's default triple lacks an API level; cargo/cc-crate pass the unversioned Rust triple. `configure.sh` installs `clangwrap/clang(+ garments for clang++)` that **strips incoming `--target=*` and `-DANDROID`**, then adds `--target=aarch64-unknown-linux-android24`. Without this: `sys/cdefs.h: Unversioned target triples are not supported`.

### Patch-apply with placeholder substitution
Termux patches contain `@TERMUX_PREFIX@`/`@TERMUX_HOST_PLATFORM@`; applied raw they become literal paths *inside the binary* (0009's `shm_open("/@TERMUX_PREFIX@/tmp/…")` → SharedPrefMap SIGSEGV). Scripts substitute before `git apply`.

### Vendored cargo checksums
Any edit under `third_party/rust/*` (0033 glslopt, etc.) invalidates `.cargo-checksum.json` → cargo refuses the vendor dir. A sweep recomputes drifted file hashes after patching.

### Patches (ours)
| Patch | Why |
| --- | --- |
| 0003 | `--custom-rust-target-triple` option + Android-host fallback (`rustc -vV` host = `aarch64-linux-android`) |
| 0012 | bionic lacks glibc adaptive mutex initializer (regenerated against 158; `ANDROID`→`__TERMUX__` intent unchanged) |
| 0023 | disable native HTTPS DNS (API-24) |
| 0028 | cc crate CFLAGS first-match (regenerated against 158's vendored cc, `getenv`→`get_env`) |
| 0032 | mozinfo: `platform.system()=="Android"` branch |
| 0033 | glslopt endian via `__BYTE_ORDER__` builtins (HAVE_ENDIAN_H unset when rust host is android) |
| 0034 | js posix thread name → `prctl(PR_GET_NAME)` (bionic API-24 lacks pthread_getname_np) |
| 0035 | nsLocalFile lutimes probe lies under `-D_GNU_SOURCE` + bionic (guard `!defined(__ANDROID_API__)`) |

### mozconfig
`termux.mozconfig` mirrors termux-packages' firefox template (system libs from Termux repos, `--target=@…@`, `--disable-jemalloc/…`, `--enable-mobile-optimize`) **minus** `--with-system-icu` (namespace rename breaks intl code; bundled ICU is upstream-default), **plus** a persistent objdir (`/ci-cache/objdir`) and `--disable-bootstrap`.

## Local iteration

```bash
bash camofox/audit-on-runner.sh        # quick sanity (patch matrix)
gh workflow run camofox-build.yml      # full build; artifacts carry build.log/config.log
```

Cold-first-run failures are normal for this port — the frontier moves one root-caused patch per run (see TROUBLESHOOTING.md for the ledger).
