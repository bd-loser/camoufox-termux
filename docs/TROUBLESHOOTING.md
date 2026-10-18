# Troubleshooting — the complete ledger

Every build/runtime error encountered while making this port, with verified root cause and fix. If you hit a new one, add it here.

## Build-time

| Symptom | Root cause | Fix |
| --- | --- | --- |
| `sys/cdefs.h:365: Unversioned target triples are not supported` | cargo/cc-crate passes the unversioned Rust triple (`aarch64-linux-android`) to clang | clangwrap strips `--target=*`, injects `-android24` |
| `failed to run custom build command … zstd-sys` (inside maturin) | same unversioned triple, via cc-crate defaults | same wrapper |
| `Please make sure the libxml2 and libxslt …` | `ddgs`→lxml needs system headers | `apt install libxml2 libxslt` (termux pkg names) |
| `error: the listed checksum of …/third_party/rust/cc/src/lib.rs has changed` | vendored-crate enforcement vs patched sources | checksum sweep (`pic`, see configure.sh) |
| `Option ‘RUSTFLAGS’ is not handled` | termux 0003 removes the only `@depends` reference at 156 | our 0003 keeps `set_config` |
| `Don't know how to translate aarch64-unknown-linux-android for rustc` | FF never hosts builds on Android; no autoconf→rust mapping | 0003 host fallback → `aarch64-linux-android` |
| `maturin failed … Please set the ANDROID_API_LEVEL` | pyo3/uniffi wheels in mach's venv build from source on an Android host | `export ANDROID_API_LEVEL=24` before mach |
| `error: linker …/build/cargo-linker not found` | FF's cross-compile contract unreachable with a native host pair | create `$SRC/build/cargo-linker` + objdir equivalent → wrapped clang |
| `undefined symbol: std::__ndk1::…` (host tools) | ld.lld links host tools without libc++ | `HOST_LDFLAGS=-L$PREFIX/lib -lc++_shared`; native `HOST_CXX` |
| `undefined symbol: __hash_memory`-class, link of libmozgtk | elf-hack inject objects are glibc-built | `--disable-elf-hack` |
| `undefined symbol: operator new/delete` (gmp-clearkey) | bare ld.lld plugin .so links miss libc++ | target `LDFLAGS += -lc++_shared` |
| `undefined symbol: sin/cos/exp2` (liblgpllibs) | FF android links assume NDK `libm`; Termux keeps it in ndk-multilib | `apt install ndk-multilib`; `LDFLAGS += -L… -l:libm.a` (static — modern Android has no system libm.so) |
| `undefined symbol: lutimes` (libxul) | `-D_GNU_SOURCE` makes Bionic *declare* lutimes (probe lies: HAVE_LUTIMES) but libc-24 doesn't export it | 0035: `#if HAVE_LUTIMES && !defined(__ANDROID_API__)` (prctl/utimes fallback in FF) |
| `error: use of undeclared identifier 'pthread_getname_np'` | Bionic API-24 header hides declaration; HAVE_ probe still defined | 0034: prctl(`PR_GET_NAME`) path |
| `no member named 'Locale' in namespace 'icu_78'` | system-ICU renames namespaces; FF intl expects bundled layout | drop `--with-system-icu` (bundled ICU = upstream default) |
| `SharedPrefMap` SIGSEGV at socket-process launch | termux patch 0009 applied **raw**: literal `/@TERMUX_PREFIX@/tmp/…` shm path | substitute `@TERMUX_PREFIX@` at patch-apply time |
| `Redirect has exceeded the redirect limit` / maturin re-checksum | upstream patch placeholders applied raw — generalization of the above | same substitution step |

## Runtime

| Symptom | Root cause | Fix |
| --- | --- | --- |
| `Couldn't load XPCOM` (launcher starts, no engine) | layout wrong: `omni.ja`/`libxul.so` not beside the binary | install the **mach package** tar (has omni.ja), not raw dist/bin |
| `Missing chrome or resource URL: resource:///modules/…` | unpackaged dev layout (no omni.ja) | same — use packaged tar |
| SIGSEGV in `SharedPrefMap::SharedPrefMap` | broken shm fd (termux patch applied raw — see build table) | fixed pipeline; repackage |
| `playwright-core: Unsupported platform: android` | playwright refuses `process.platform` != linux | Node preload forcing platform (docs/INSTALL.md) |
| CLI `--screenshot` hangs (`Helper.js:83`) | juggler double-teardown, **upstream** | use juggler/playwright automation; reported [daijro/camoufox#909](https://github.com/daijro/camoufox/issues/909) |

## Environment quirks (termux-docker container)

- `/tmp` missing; use `$HOME/tmp` (`TMPDIR`)
- `/data` mount: **noexec**, `flock` unsupported → never exec/rustup there
- `docker run -e` forwarding is unreliable → pass config as positional args
- No rustup package in Termux repos (by design; scripts stub it for configure-time probes only — phase 2 uses Termux rust.)
