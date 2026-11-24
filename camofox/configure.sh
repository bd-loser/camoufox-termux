#!/data/data/com.termux/files/usr/bin/bash
# Phase 2a: configure-only run of Camoufox-on-Termux inside termux-docker.
# Builds nothing; proves `mach configure` accepts our termux.mozconfig over
# the fully patched tree (camoufox patches + camofox/termux-patches/*).
# Output: /out/configure.log (+ env dump on failure).

set -euo pipefail

: "${CAMOFOX_PIN:?CAMOFOX_PIN must be set}"
: "${TERMUX_PKGS_PIN:?TERMUX_PKGS_PIN must be set}"

OUT=/out
WORK="$HOME/camofox-build"
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
mkdir -p "$OUT" "$WORK"
cd "$WORK"

step() { printf '\n===== %s =====\n' "$*"; }
export TMPDIR="$HOME/tmp"; mkdir -p "$TMPDIR"

step "install toolchain + build deps (termux)"
echo "deb https://packages.termux.dev/apt/termux-main stable main" > "$PREFIX_DIR/etc/apt/sources.list"
apt update -y
# Compiler/rust/node from termux (no rustup anywhere in this pipeline).
pkg install -y make python git curl tar xz-utils clang rust nodejs-lts pkg-config \
  binutils cbindgen-bin ccache zip >/dev/null 2>&1 || \
  apt install -y make python git curl tar xz-utils clang rust nodejs-lts pkg-config binutils ccache zip
# System libs the configure-time checks need (mirrors TERMUX_PKG_DEPENDS/DEPENDS
# of x11-packages/firefox, trimmed to configure-relevant ones). gtk3/nspr/nss
# and friends live in the x11 repo.
pkg install -y x11-repo >/dev/null 2>&1 || true
apt update -y
apt install -y ndk-sysroot ndk-multilib gtk3 pulseaudio libvpx libicu libnspr libnss libwebp zlib libjpeg-turbo \
  libpng freetype fontconfig gdk-pixbuf glib libffi libevent ffmpeg libcairo \
  libx11 libxcb libice libsm libxext libandroid-shmem libandroid-spawn

# pyo3/uniffi wheels in the mach venvs are built by maturin, which refuses
# Android without an explicit API level (upstream never builds on Android).
export ANDROID_API_LEVEL=24

# --- termux rolling-repo repair: ccache vs libfmt ABI drift (seen 2026-10-19)
# Today's ccache deb links fmt::v11 while the repo may ship newer libfmt;
# then even `ccache --version` dies with CANNOT LINK EXECUTABLE ... vformat.
# Try repo-archive libfmt builds newest-first until ccache links; if none
# works, drop --with-ccache (mozconfig is generated later, CCACHE_OK set).
CCACHE_OK=0
if command -v ccache >/dev/null 2>&1; then
  if ccache --version >/dev/null 2>&1; then CCACHE_OK=1
  else
    echo "ccache broken (libfmt ABI drift) - repairing from repo archive"
    for deb in $(curl -fsSL https://packages.termux.dev/apt/termux-main/pool/main/libf/libfmt/ 2>/dev/null | grep -oE 'libfmt_[0-9.]+_aarch64\.deb' | sort -ruV); do
      curl -fsSL "https://packages.termux.dev/apt/termux-main/pool/main/libf/libfmt/$deb" -o "/tmp/$deb" && dpkg -i "/tmp/$deb" >/dev/null 2>&1 || continue
      if ccache --version >/dev/null 2>&1; then echo "repaired with $deb"; CCACHE_OK=1; break; fi
    done
    [ "$CCACHE_OK" = 1 ] || echo "WARNING: ccache unusable - build proceeds WITHOUT cache"
  fi
fi

step "fetch camoufox @ $CAMOFOX_PIN"
[ -d camoufox ] || {
  curl -fsSL -o camoufox.tar.gz \
    "https://codeload.github.com/daijro/camoufox/tar.gz/$CAMOFOX_PIN"
  mkdir camoufox && tar -xzf camoufox.tar.gz -C camoufox --strip-components=1
}
cd camoufox/browser
VERSION="$(sed -n 's/^version=//p' upstream.sh)"
RELEASE="$(sed -n 's/^release=//p' upstream.sh)"
SRC_DIR="camoufox-$VERSION-$RELEASE"

step "fetch Firefox $VERSION source + apply patches"
[ -f "$SRC_DIR/mozconfig" ] || {
  FF_TARBALL="firefox-$VERSION.source.tar.xz"
  [ -f "$FF_TARBALL" ] || curl -fsSL -C - -o "$FF_TARBALL" \
    "https://archive.mozilla.org/pub/firefox/releases/$VERSION/source/$FF_TARBALL"
  make setup-minimal
  # rustup stub: their patcher's cross-target step is replaced by the Termux
  # mozconfig (see NOTES.md). /out is a runner bind mount (exec+lock OK).
  RSHIM="$OUT/.rustup-shim"
  mkdir -p "$RSHIM" "$HOME/.cargo/bin"
  printf '#!/data/data/com.termux/files/usr/bin/bash\necho "rustup-stub: $*" >> /out/rustup-stub.log\nexit 0\n' \
    > "$RSHIM/rustup"
  chmod 0755 "$RSHIM/rustup"
  ln -sf "$RSHIM/rustup" "$HOME/.cargo/bin/rustup"
  export PATH="$HOME/.cargo/bin:$PATH"
  BUILD_TARGET="linux,arm64" python3 scripts/patch.py "$VERSION" "$RELEASE"
  cd "$SRC_DIR"

  git init -q -b main && git add -A
  git -c user.email=a@a -c user.name=a commit -qm "camoufox-patched tree"

  step "apply termux firefox patches (termux-packages set, minus replaced/no-op ones)"
TERMUX_PREFIX_UX="${PREFIX:-/data/data/com.termux/files/usr}"
  git config --global --add safe.directory "$(pwd)" || true
  TFP="$WORK/termux-firefox"
  if [ ! -d "$TFP" ]; then
    mkdir -p "$TFP" && cd "$TFP"
    git init -q
    git remote add origin https://github.com/termux/termux-packages.git
    git fetch -q --depth 1 origin "$TERMUX_PKGS_PIN"
    git checkout -q FETCH_HEAD -- x11-packages/firefox
    mv x11-packages/firefox/*.patch .
    rm -rf x11-packages .git
    cd "$WORK/camoufox/browser/$SRC_DIR"
  fi
  # 0003/0012/0023/0028 are replaced by rebased versions in
  # /work/camofox/termux-patches. The 0031 pair (webspeech-disabled fix,
  # ioprio-on-android) patches Firefox-157+ code absent at 156, so they are
  # skipped only on the 156 line; on 157+ they must apply.
  FAIL=0
  for p in "$TFP"/*.patch; do
    name="$(basename "$p")"
    case "$name" in
      0003-*|0012-*|0018-*|0023-*|0028-*) echo "SKIP $name (replaced by rebased camofox/termux-patches)"; continue;;
      0031-*) if [[ "$VERSION" == 156.* ]]; then
                echo "SKIP $name (fixes a Firefox-157+ regression absent at 156 - by design)"; continue;
              fi;;
    esac
    # Termux substitutes build variables (@TERMUX_PREFIX@ etc.) in patch
    # files before applying; raw placeholders would end up as literal paths
    # inside the binary (0009's shm_open("/@TERMUX_PREFIX@/tmp/...")!).
    sed -e "s|@TERMUX_PREFIX@|$TERMUX_PREFIX_UX|g" \
        -e "s|@TERMUX_HOST_PLATFORM@|aarch64-linux-android|g" \
        "$p" > "$WORK/termux-patch-$name"
    if git apply --check "$WORK/termux-patch-$name"; then
      git apply "$WORK/termux-patch-$name" && git add -A && echo "TERMUX-PATCH PASS $name"
    else
      echo "TERMUX-PATCH FAIL $name"; FAIL=1
    fi
  done

  if [ "${CAMOFOX_REGEN:-0}" = "1" ]; then
    # Port-support mode (not a build). The replaced termux patches
    # (0003/0012/0023/0028) are per-version rebases; on a new Firefox line
    # their contexts drift. Here the tree already carries upstream camoufox
    # + the clean termux set, so re-applying each ORIGINAL (substituted)
    # termux patch and diffing worktree-vs-index reproduces the
    # current-line-intent patch. Full-apply wins ("REGENERATED-*"); partial
    # rejects are saved for hand-rebase. Exits before configure.
    step "regen: rebuild replaced patches from termux originals"
    OUTR=/out/regen
    mkdir -p "$OUTR"
    for p in "$TFP"/*.patch; do
      name="$(basename "$p")"
      case "$name" in
        0003-*|0012-*|0018-*|0023-*|0028-*) ;;
        *) continue ;;
      esac
      sed -e "s|@TERMUX_PREFIX@|$TERMUX_PREFIX_UX|g" \
          -e "s|@TERMUX_HOST_PLATFORM@|aarch64-linux-android|g" \
          "$p" > "$WORK/regen-$name"
      cp "$WORK/regen-$name" "$OUTR/original-$name.subst"
      git checkout -q -- . 2>/dev/null || true
      git apply --reject "$WORK/regen-$name" 2> "$OUTR/$name.apply.err" || true
      if [ -z "$(find . -name '*.rej' -newer "$WORK/regen-$name" -print -quit)" ]; then
        git diff --binary > "$OUTR/REGENERATED-$name"
        echo "REGEN OK $name -> /out/regen/REGENERATED-$name"
      else
        echo "REGEN NEEDS-HAND-WORK $name (.rej + err saved)"
      fi
      find . -name '*.rej' -exec cp {} "$OUTR/" \; 2>/dev/null || true
      find . -name '*.rej' -delete 2>/dev/null || true
      git checkout -q -- . 2>/dev/null || true
    done
    echo "regen complete: artifacts under /out/regen/"
    exit 0
  fi

  step "apply our rebased camofox/termux-patches"
  for p in /work/camofox/termux-patches/*.patch; do
    name="$(basename "$p")"
    if git apply --check "$p"; then
      git apply "$p" && git add -A && echo "REBASED-PATCH PASS $name"
    else
      echo "REBASED-PATCH FAIL $name"; FAIL=1
    fi
  done
  [ "$FAIL" = 0 ] || { echo "error: termux-patches did not apply; aborting before configure" >&2; exit 1; }

  if [ "${CAMOFOX_DIAG:-0}" = "1" ]; then
    # Port-support diagnostic (not a build): dump the pkix TrustDomain
    # interface and its WebTransport subclass *as the patched tree sees them*
    # to explain vtable/abstract-class errors without a 50-min compile.
    step "diag: WebTransportCertificateVerifier vs TrustDomain"
    OUTD=/out/diag; mkdir -p "$OUTD"
    PKIX=security/nss/lib/mozpkix/include/pkix/pkixtypes.h
    WTCV=netwerk/protocol/http/WebTransportCertificateVerifier.cpp
    echo "--- base TrustDomain virtuals ($PKIX):" | tee "$OUTD/diag.txt"
    awk '/class TrustDomain/,/^};/' "$PKIX" \
      | grep -oE "virtual (Result|void) [A-Za-z0-9_]+\(" | sed 's/.* //;s/($//' \
      | sort > "$OUTD/base-virtuals.txt"
    tee -a "$OUTD/diag.txt" < "$OUTD/base-virtuals.txt"
    echo "--- overrides in $WTCV:" | tee -a "$OUTD/diag.txt"
    grep -oE "Result ServerCertHashesTrustDomain::[A-Za-z0-9_]+\(|void ServerCertHashesTrustDomain::[A-Za-z0-9_]+\(" "$WTCV" \
      | sed 's/.*:://;s/($//' | sort > "$OUTD/overrides.txt"
    tee -a "$OUTD/diag.txt" < "$OUTD/overrides.txt"
    echo "--- base virtuals NOT overridden (the abstract-class cause, if any):" | tee -a "$OUTD/diag.txt"
    comm -23 "$OUTD/base-virtuals.txt" "$OUTD/overrides.txt" | tee -a "$OUTD/diag.txt"
    echo "--- WTCV lines 225..236:" | tee -a "$OUTD/diag.txt"
    sed -n '225,236p' "$WTCV" | tee -a "$OUTD/diag.txt"
    echo "--- system nss/mozpkix layout:" | tee -a "$OUTD/diag.txt"
    find "${TERMUX_PREFIX_UX}/include/nss" -maxdepth 2 -name 'mozpkix*' 2>/dev/null | head | tee -a "$OUTD/diag.txt"
    echo "--- pkg-config nss cflags:" | tee -a "$OUTD/diag.txt"
    pkg-config --cflags nss 2>/dev/null | tee -a "$OUTD/diag.txt"
    echo "--- which pkixtypes.h does a bare include resolve to:" | tee -a "$OUTD/diag.txt"
    printf '#include "nss/mozpkix/pkixtypes.h"\n' > "$OUTD/probe.cpp"
    clang++ -E -H -c "$OUTD/probe.cpp" -o /dev/null > "$OUTD/probe.out" 2>&1 || true
    grep -m3 "pkixtypes.h" "$OUTD/probe.out" | tee -a "$OUTD/diag.txt" || true
    echo "--- in-tree mozpkix dir:" | tee -a "$OUTD/diag.txt"
    ls -la security/nss/lib/mozpkix/include/ 2>/dev/null | tee -a "$OUTD/diag.txt" || true
    ls -la security/nss/lib/mozpkix/include/pkix/ 2>/dev/null | head -5 | tee -a "$OUTD/diag.txt" || true
    echo "--- pkixtypes.h sha256 + guards:" | tee -a "$OUTD/diag.txt"
    sha256sum "$PKIX" | tee -a "$OUTD/diag.txt"
    grep -nE "define MOZ_NO_HTTPS_IMPL|#if|#ifdef" "$PKIX" | head -20 | tee -a "$OUTD/diag.txt"
    cp "$PKIX" "$OUTD/pkixtypes.h.full" 2>/dev/null || true
    cp "$WTCV" "$OUTD/WebTransportCertificateVerifier.cpp.full" 2>/dev/null || true
    echo "diag complete: artifacts under /out/diag/"
    exit 0
  fi

  step "refresh vendored cargo checksums (patches edit vendored crates)"
  # Cargo verifies every file listed in a vendored crate's
  # .cargo-checksum.json; patches that touch third_party/rust/* must update
  # those entries or the build dies ("directory sources are not intended to
  # be edited"). Recompute drift for all vendored crates in one sweep.
  python3 - <<'PYCS'
import hashlib, json
from pathlib import Path
for cc in Path(".").glob("third_party/rust/*/.cargo-checksum.json"):
    d = json.loads(cc.read_text())
    files = d.get("files", {})
    changed = False
    for rel, sha in list(files.items()):
        f = cc.parent / rel
        if f.is_file():
            h = hashlib.sha256(f.read_bytes()).hexdigest()
            if h != sha:
                files[rel] = h
                changed = True
    if changed:
        cc.write_text(json.dumps(d, separators=(",", ":")))
        print("checksums updated:", cc.parent.name)
PYCS
  git add -A
  git -c user.email=a@a -c user.name=a commit -qm "termux graft" || true
}
cd "$WORK/camoufox/browser/$SRC_DIR"

step "versioned-triple clang wrapper (termux toolchain emulation)"
# termux-packages compiles through versioned-triple wrappers
# ($TERMUX_HOST_PLATFORM-clang = aarch64-linux-android24). Bare "clang" calls
# from cargo/pip/mach would otherwise fail in cdefs ("Unversioned target
# triples are not supported"). Export the wrapped compiler on PATH so every
# consumer (cc-crate, pip sdists, mach) gets the versioned triple.
CWRAP="$HOME/clangwrap"
mkdir -p "$CWRAP"
for tool in clang clang++; do
  # Quoted delimiter: "$@" must survive verbatim into the wrapper script.
  # Incoming --target args are stripped: cargo/cc-crate passes the unversioned
  # host triple (aarch64-linux-android) which termux headers reject; the
  # versioned triple below must be the one clang sees.
  cat > "$CWRAP/$tool" <<'WEOF'
#!/data/data/com.termux/files/usr/bin/bash
args=()
for a in "$@"; do
  case "$a" in
    --target=*) ;;
    # Legacy cc-crate injection: flips vendored C code (glslopt et al.) into
    # NDK-only branches (#include <log/log.h>) that Termux cannot satisfy.
    # __ANDROID__ remains defined via the versioned triple.
    -DANDROID) ;;
    *) args+=("$a") ;;
  esac
done
# No --sysroot: this is the native Termux compiler; it resolves its own
# prefix include/lib dirs (the phone builds the same code without one).
# Forcing --sysroot shadows the baked-in include order (asm/types.h class).
exec "/data/data/com.termux/files/usr/bin/clang" --target=aarch64-unknown-linux-android24 "${args[@]}"
WEOF
  chmod 0755 "$CWRAP/$tool"
done
export PATH="$CWRAP:$PATH"
echo 'int main(){}' | clang -xc - -o /dev/null && echo "clang wrapper selftest ok"

step "build env (mirrors termux build.sh pre_configure)"
TERMUX_HOST_PLATFORM=aarch64-linux-android
CARGO_TARGET_NAME=aarch64-linux-android
# Absolute wrapper paths for TARGET and HOST alike: mach/pip/isolation stages
# can drop PATH or resolv raw compilers (evidence: venv bootstrap used raw
# /usr/bin/clang -> unversioned triple regression in standalone runs).
export CC="$HOME/clangwrap/clang" CXX="$HOME/clangwrap/clang++"
# Host tools (elfhack relrhack etc.) are compiled AND linked natively: use
# the absolute native compiler and add the libc++ library the host linker
# needs (ld.lld adds no default -lc++_shared; termux libc++ ABI is __ndk1).
export HOST_CC="$HOME/clangwrap/clang"
export HOST_CXX="$HOME/clangwrap/clang++"
export HOST_LDFLAGS="-L$PREFIX_DIR/lib -lc++_shared"
export BINDGEN_CFLAGS="--target=aarch64-unknown-linux-android24"
export BINDGEN_EXTRA_CLANG_ARGS_AARCH64_LINUX_ANDROID="$BINDGEN_CFLAGS"
export CXXFLAGS="-U__ANDROID__ -D_LIBCPP_HAS_NO_C11_ALIGNED_ALLOC"
# -lc++_shared: bare ld.lld links (small plugin .so's like gmp-clearkey)
# otherwise miss the termux libc++ runtime (ABI __ndk1).
# -lm: FF's android .so links assume NDK libm (sin/cos/exp in liblgpllibs etc.).
# Termux ships it inside ndk-multilib; Android's /system/lib64 provides it at runtime.
# -l:libm.a: static, because modern Android merged libm into libc and does
# not ship /system libm.so — a shared DT_NEEDED would break on real phones.
export LDFLAGS="-landroid-shmem -landroid-spawn -llog -L$PREFIX_DIR/lib -lc++_shared -L$PREFIX_DIR/opt/ndk-multilib/aarch64-linux-android/lib -l:libm.a"
# gkrust OOM guard, same as termux
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS+=" -C debuginfo=1 -A deprecated"
env | grep -E '^(CC|CXX|HOST_|BINDGEN|CXXFLAGS|LDFLAGS|CARGO)' | tee "$OUT/env.txt"
command -v cbindgen >/dev/null || cargo install --quiet cbindgen

step "write mozconfig (base + termux)"
sed -e "s|@TERMUX_HOST_PLATFORM@|${TERMUX_HOST_PLATFORM}|g" \
    -e "s|@TERMUX_PREFIX@|${TERMUX_PREFIX:-$PREFIX_DIR}|g" \
    -e "s|@CARGO_TARGET_NAME@|${CARGO_TARGET_NAME}|g" \
    /work/camofox/termux.mozconfig > "$WORK/termux-sub.mozconfig"
# base.mozconfig lives at browser/assets/base.mozconfig
cat ../assets/base.mozconfig "$WORK/termux-sub.mozconfig" > mozconfig
[ "$CCACHE_OK" = 1 ] || sed -i '/^ac_add_options --with-ccache/d' mozconfig
# 159's base.mozconfig always enables cross-PGO against Mozilla's x86_64
# profile ($CAMOUFOX_PGO_PROFILE via their scripts/pgo.py, which this pipeline
# never runs). A PGO profile is arch/ABI-specific; the x86_64-linux profile is
# meaningless for an aarch64-android/Bionic build and configure aborts on the
# missing path. Drop the profile options; keep the LTO/rust-simd lines.
sed -i -e '/^ac_add_options --enable-profile-use=/d' \
       -e '/^ac_add_options --with-pgo-profile-path=/d' \
       -e '/^ac_add_options --with-pgo-jarlog=/d' mozconfig
# System-NSS-vs-firefox mismatch: Termux's rolling libnss (>= 3.134) began
# shipping an /usr/include/nss/mozpkix directory whose headers add ML-DSA
# TrustDomain pure virtuals (NSS bug 2068282, 2026-11-12) and which is broken
# for Firefox's include form anyway ('nss/mozpkix/pkixtypes.h' then cannot find
# 'mozpkix/Input.h'). pkg-config nss gives '-I/usr/include/nss -I/usr/include',
# so '/usr/include' wins regardless of our -I ordering. Fix at the filesystem:
# replace the system dir with the in-tree 159-era interface (what this Firefox
# line was written against). No flag-ordering dependency.
SYS_NSS_MOZPKIX="${TERMUX_PREFIX_UX}/include/nss/mozpkix"
INTREE_MOZPKIX="$(pwd)/security/nss/lib/mozpkix/include/pkix"
if [ -d "$INTREE_MOZPKIX" ]; then
  if [ -e "$SYS_NSS_MOZPKIX" ] && [ ! -e "${SYS_NSS_MOZPKIX}.ecc-bak" ]; then
    mv "$SYS_NSS_MOZPKIX" "${SYS_NSS_MOZPKIX}.ecc-bak" 2>/dev/null || true
  fi
  rm -rf "$SYS_NSS_MOZPKIX"
  ln -s "$INTREE_MOZPKIX" "$SYS_NSS_MOZPKIX"
  echo "repointed $SYS_NSS_MOZPKIX -> in-tree 159 mozpkix" | tee -a "$OUT/configure.log"
else
  echo "WARN: in-tree mozpkix include dir not found; system NSS may be too new" >&2
fi
# Persist the objdir through the /ci-cache mount: warm runs skip recompiling
# everything (ccache replays into a live tree; rust fragments stay).
if [ -d /ci-cache ]; then
  mkdir -p /ci-cache/objdir
  echo "mk_add_options MOZ_OBJDIR=/ci-cache/objdir" >> mozconfig
fi

step "include-path debug (asm/types.h truth)"
ls -la /data/data/com.termux/files/usr/include/asm 2>/dev/null || echo "NO /usr/include/asm"
ls /data/data/com.termux/files/usr/include/asm-generic/types.h 2>/dev/null || echo "no asm-generic/types.h"
echo '#include <sys/types.h>' | clang -E - >/dev/null 2>&1 && echo "sys/types.h preprocess OK" || echo "sys/types.h preprocess FAILED"
echo '#include <asm/types.h>' | clang -E - >/dev/null 2>&1 && echo "asm/types.h OK" || echo "asm/types.h FAILED"
clang -v 2>&1 | grep -E 'Target|InstalledDir'

step "mach configure (log: $OUT/configure.log)"
set +e
# Termux's 0003 patch removes the set_config("RUSTFLAGS") handler from
# rust.configure (cargo reads CARGO_TARGET_*_RUSTFLAGS at build time). With
# that gone, a stray RUSTFLAGS env var becomes a configure error — unset it
# everywhere it could hide and show what is actually set.
env | grep -i rust || echo "(no rust env vars)"
unset RUSTFLAGS RUSTFLAGS_aarch64_linux_android CAMERA_RUSTFLAGS 2>/dev/null || true
# ./mach's '#!/usr/bin/env python3' shebang fails on the image (no /usr/bin/env);
# run it through the interpreter directly.
python3 ./mach configure 2>&1 | tee "$OUT/configure.log"
RC=${PIPESTATUS[0]}
set -e
echo "configure exit: $RC" | tee -a "$OUT/configure.log"
# Full mozbuild config.log (objdir) is essential for deep-diving failures.
OBJCFG="$(find "$HOME/.mozbuild/srcdirs" -name config.log -path '*obj-*' 2>/dev/null | head -1)"
[ -n "$OBJCFG" ] && cp "$OBJCFG" "$OUT/config-full.log" || echo "(no objdir config.log found)"
cd "$WORK/camoufox/browser/$SRC_DIR"
[ "$RC" = 0 ] \
  && step "CONFIGURE OK" \
  || { step "CONFIGURE FAILED (tail above; full log in artifact)"; exit "$RC"; }

if [ "${CAMOFOX_BUILD:-0}" != "1" ]; then
  step "configure-only run done (set CAMOFOX_BUILD=1 for mach build)"
  exit 0
fi

step "cargo-linker + maturin android env"
# Firefox routes cargo linking through objdir/build/cargo-linker (a symlink
# its cross-compile logic creates from NDK wrappers). With a native Android
# host/target pair the file is never created, but the linker reference is:
# create it ourselves, pointing at the versioned-triple wrapped clang.
# objdir is persisted at /ci-cache/objdir (MOZ_OBJDIR appended to mozconfig);
# ~/.mozbuild/srcdirs only holds the mach virtualenvs.
OBJDIR="$(ls -d /ci-cache/objdir 2>/dev/null | head -1)"
echo "objdir: ${OBJDIR:-MISSING}" | tee -a "$OUT/build.log"
[ -n "$OBJDIR" ] || { ls "$WORK/camoufox/browser/$SRC_DIR" >&2; echo "no objdir after configure" >&2; exit 1; }
# rust.mk references $SRC_DIR/build/cargo-linker (topsrcdir), created by the
# cross-compile logic at configure time — absent with our native host pair.
mkdir -p "$WORK/camoufox/browser/$SRC_DIR/build" "$OBJDIR/build"
ln -sf "$HOME/clangwrap/clang" "$WORK/camoufox/browser/$SRC_DIR/build/cargo-linker"
ln -sf "$HOME/clangwrap/clang" "$OBJDIR/build/cargo-linker"
ls -la "$WORK/camoufox/browser/$SRC_DIR/build/cargo-linker" | tee -a "$OUT/build.log"

step "mach build (this is the long one)"
# ccache placement for persistence across runs.
export CCACHE_DIR="/ci-cache/ccache"
mkdir -p "$CCACHE_DIR"
export CCacheGravity="1"
NPROC=$(nproc)
echo "building with -j$NPROC, CCACHE_DIR=$CCACHE_DIR"
time python3 ./mach build -j"$NPROC" 2>&1 | tee "$OUT/build.log"
RC_B=${PIPESTATUS[0]}
echo "build exit: $RC_B" | tee -a "$OUT/build.log"
OBJDIR="$(ls -d /ci-cache/objdir 2>/dev/null | head -1)"  # refresh
BIN="$(find /ci-cache/objdir/dist/bin -maxdepth 1 -name "camoufox*" -type f 2>/dev/null | head -1)"
HERMES_PKGVER="$(cat "$WORK/camoufox/browser/$SRC_DIR/browser/config/version.txt" 2>/dev/null || echo unknown)"
if [ "$RC_B" = 0 ] && [ -n "$BIN" ]; then
  echo "BUILD OK: $BIN" | tee -a "$OUT/build.log"
  ls -la "$BIN" | tee -a "$OUT/build.log"
  cp "$BIN"* "$OUT/" 2>/dev/null || true
  step "mach package (omni.ja + release layout)"
  python3 ./mach package 2>&1 | tail -20 | tee -a "$OUT/build.log"
  TARGET_TAR="$(ls -t /ci-cache/objdir/dist/*.tar.* 2>/dev/null | head -1)"
  [ -n "$TARGET_TAR" ] || { echo "package output missing" >&2; exit 1; }
  ls -la "$TARGET_TAR" | tee -a "$OUT/build.log"
  cp "$TARGET_TAR" "$OUT/native-tree.tar"
  ( cd "$OUT" && sha256sum native-tree.tar > native-tree.tar.sha256 )

  # ---- multi-format packaging (deb / pacman / zip / tree) ----
  step "build deb / pacman / zip packages"
  RAW="$OUT/debstage_raw"
  STAGE="$OUT/debstage"
  rm -rf "$RAW" "$STAGE"; mkdir -p "$RAW" "$STAGE"
  tar -xf "$OUT/native-tree.tar" -C "$RAW"
  # mach package wraps everything in ONE top dir (camoufox/) that WE keep as
  # the stage. Do NOT flatten: the tree legally contains a main binary also
  # named `camoufox` beside dirs (mv-flatten collided on exactly that).
  entries=("$RAW"/*)
  if [ "${#entries[@]}" = 1 ] && [ -d "${entries[0]}" ] && [ -f "${entries[0]}/application.ini" ]; then
    STAGE="${entries[0]}"
  fi
  [ -f "$STAGE/application.ini" ] || { echo "application.ini missing after extraction" >&2; ls -la "$RAW" >&2; exit 1; }
  VFILE="$STAGE/application.ini"
  DEBVER="$(grep -m1 '^Version=' "$VFILE" | cut -d= -f2 | sed 's/-beta\./b/')"
  [ -n "$DEBVER" ] || DEBVER="0.0"
  PKGBASE="$OUT/camoufox-$DEBVER-aarch64"

  # ---- derive runtime Depends from the ELF NEEDED set (issue #1) ----
  # The .deb once declared a too-small hardcoded list and a fresh Termux died
  # with "library libplds4.so not found" from libxul.so. Derive it instead so
  # it cannot drift: scan the engine + libxul.so NEEDED sonames, map each to a
  # Termux package, drop whatever gtk3 already pulls in transitively.
  ENGINE="$(find "$STAGE" -maxdepth 1 -type f -name 'camoufox*' | head -1)"
  LIBXUL="$(find "$STAGE" -name 'libxul.so' | head -1)"
  NEEDED="$( { readelf -d "$ENGINE" 2>/dev/null; readelf -d "$LIBXUL" 2>/dev/null; } \
             | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u )"
  echo "NEEDED sonames ($(echo "$NEEDED" | wc -w)):"; echo "$NEEDED" | tr '\n' ' '; echo
  # soname -> termux package. Anything absent here is either provided by the
  # gtk3 closure below or a bionic/ndk system lib we must not depend on.
  dep_pkg() {
    case "$1" in
      libnspr4.so|libplc4.so|libplds4.so)                 echo libnspr ;;
      libnss3.so|libnssutil3.so|libsmime3.so|libssl3.so) echo libnss ;;
      libevent-*.so*)                                     echo libevent ;;
      libvpx.so*)                                         echo libvpx ;;
      libwebp.so*|libwebpdemux.so*|libsharpyuv.so*)       echo libwebp ;;
      libgtk-3.so*|libgdk-3.so*|libgdk_pixbuf-2.0.so*)    echo gtk3 ;;
      libandroid-shmem.so*)                               echo libandroid-shmem ;;
      libandroid-spawn.so*|libandroid-support.so*)        echo libandroid-spawn ;;
      libc++_shared.so)                                   echo libc++ ;;
      # transitively inside the gtk3 closure -> intentionally not declared:
      libjpeg.so*|libxcb*.so*|libX11*.so*|libffi.so*|libz.so*|libcairo.so*|libpango*.so*|libatk*.so*) echo "" ;;
      *)                                                  echo "" ;;
    esac
  }
  DEPS_SET=""
  for so in $NEEDED; do
    p="$(dep_pkg "$so")"
    [ -n "$p" ] || continue
    case " $DEPS_SET " in *" $p "*) ;; *) DEPS_SET="$DEPS_SET $p";; esac
  done
  DEPS_SET="${DEPS_SET# }"
  # Fallback to the known-good closed set if readelf gave us nothing.
  [ -n "$DEPS_SET" ] || DEPS_SET="gtk3 libandroid-shmem libandroid-spawn libc++ libwebp libevent libnspr libnss"
  DEPS_DEB="x11-repo, $(echo "$DEPS_SET" | sed 's/ /, /g')"
  echo "derived Depends (deb): $DEPS_DEB"
  echo "derived Depends (pacman): $DEPS_SET"

  # deb payload tree: termux debs carry ABSOLUTE paths (./data/data/...),
  # dpkg does NOT remap '/' to $PREFIX (verified on-device: './opt' =>
  # "Read-only file system"). Engine: $PREFIX/opt/camoufox, launcher:
  # $PREFIX/bin/camoufox.
  DEBTREE="$OUT/debtree"
  PT="$DEBTREE/data/data/com.termux/files/usr"
  rm -rf "$DEBTREE"; mkdir -p "$PT/opt/camoufox" "$PT/bin" "$DEBTREE/DEBIAN"
  chmod 0755 "$DEBTREE/data" "$DEBTREE/data/data" "$DEBTREE/data/data/com.termux" \
    "$DEBTREE/data/data/com.termux/files" "$PT" "$DEBTREE/DEBIAN"
  cp -a "$STAGE/." "$PT/opt/camoufox/"
  cat > "$PT/bin/camoufox" <<'WEOF'
#!/data/data/com.termux/files/usr/bin/sh
exec "$PREFIX/opt/camoufox/camoufox-bin" "$@"
WEOF
  chmod 0755 "$PT/bin/camoufox"
  chmod 0755 "$PT/opt" "$PT/bin" "$PT/opt/camoufox"
  ISZ="$(du -sk "$PT/opt/camoufox" | cut -f1)"
  {
    echo "Package: camoufox"
    echo "Version: $DEBVER"
    echo "Architecture: aarch64"
    echo "Maintainer: bd-loser <bd-loser@users.noreply.github.com>"
    echo "Installed-Size: $ISZ"
    # Depends = what libxul.so's NEEDED set does not get from the gtk3
    # closure. Verified against `readelf -d libxul.so` plus a recursive
    # apt-cache depends walk of gtk3 (issue camoufox-termux#1: the .deb
    # declared only gtk3/libandroid-*/libc++, so a fresh Termux died with
    # "library libplds4.so not found" from libxul.so):
    #   x11-repo  gtk3 lives in the x11 repo; without it apt cannot even
    #             read a candidate for gtk3 and the install is unsatisfiable.
    #   libnspr   libnspr4/libplc4/libplds4
    #   libnss    libnss3/libnssutil3/libsmime3/libssl3
    #   libevent  libevent-2.1
    #   libvpx    libvpx.so.12
    #   libwebp   libwebp/libwebpdemux/libsharpyuv (gdk-pixbuf does NOT pull it)
    # libjpeg-turbo, libxcb, libx11, libffi, zlib, cairo, pango, gdk-pixbuf
    # and atk (via at-spi2-core) all arrive through gtk3 already.
    # Depends derived above from libxul.so's NEEDED set (issue camoufox-termux#1).
    # Fixed extra: x11-repo (gtk3 only exists once that repo is enabled).
    # Skipped as already-transitive via gtk3: libjpeg-turbo, libxcb, libx11,
    # libffi, zlib, cairo, pango, gdk-pixbuf, atk (via at-spi2-core).
    echo "Depends: $DEPS_DEB"
    echo "Section: web"
    echo "Homepage: https://github.com/bd-loser/camoufox-termux"
    echo "Description: Camoufox anti-fingerprint Firefox fork (Bionic native)"
    echo " Anti-detect Firefox engine built natively for Termux/Bionic aarch64."
    echo " Engine under $PREFIX/opt/camoufox; launcher: camoufox."
  } > "$DEBTREE/DEBIAN/control"
  DEB="$PKGBASE.deb"
  dpkg-deb --root-owner-group --build "$DEBTREE" "$DEB" >/dev/null
  ( cd "$OUT" && sha256sum "$(basename "$DEB")" > "$(basename "$DEB").sha256" )

  PAC="$PKGBASE.pkg.tar.xz"
  PRT="$OUT/pacstage"; rm -rf "$PRT"; mkdir -p "$PRT/opt/camoufox"
  cp -a "$STAGE/." "$PRT/opt/camoufox/"
  cat > "$PRT/.PKGINFO" <<EOF
pkgname = camoufox
pkgver = $DEBVER-1
pkgdesc = Camoufox anti-fingerprint Firefox fork (Bionic native)
url = https://github.com/bd-loser/camoufox-termux
builddate = $(date +%s)
packager = bd-loser
size = $(du -sk "$PRT/opt" | cut -f1)
arch = aarch64
# Mirror of the deb Depends above (pacman has no x11-repo dependency: the
# x11 repo must be enabled separately there).
$(for d in $DEPS_SET; do echo "depend = $d"; done)
EOF
  python3 - "$PRT" > "$PRT/.MTREE" <<'PYM'
import hashlib, os, sys, time
import gzip
root = sys.argv[1]
now = int(time.time())
out = []
for dp, dn, fn in os.walk(root):
    for f in fn:
        fp = os.path.join(dp, f)
        rel = "/" + os.path.relpath(fp, root)
        h = hashlib.sha256(open(fp, "rb").read()).hexdigest()
        out.append(f"{rel} time={now} size={os.path.getsize(fp)} sha256={h}")
sys.stdout.buffer.write(gzip.compress(("\n".join(out) + "\n").encode()))
PYM
  tar -cJf "$PAC" -C "$PRT" .PKGINFO .MTREE opt
  ( cd "$OUT" && sha256sum "$(basename "$PAC")" > "$(basename "$PAC").sha256" )

  ZIPB="$PKGBASE.zip"
  cat > "$STAGE/install.sh" <<'IEOF'
#!/data/data/com.termux/files/usr/bin/sh
chmod 755 camoufox-bin
echo "installed (zip). run: ./camoufox-bin"
IEOF
  chmod 755 "$STAGE/install.sh"
  # zip-format step needs the zip CLI; rolling images occasionally omit it
  command -v zip >/dev/null 2>&1 || { pkg install -y zip >/dev/null 2>&1 || apt install -y zip; }
  command -v zip >/dev/null 2>&1 || { echo "FATAL: zip CLI unavailable" >&2; ls -la "$OUT"/camoufox-*; exit 0; }
  ( cd "$STAGE" && zip -qr9 "$ZIPB" . )
  ( cd "$OUT" && sha256sum "$(basename "$ZIPB")" > "$(basename "$ZIPB").sha256" )

  ( cd "$OUT" && mv native-tree.tar "camoufox-$DEBVER-aarch64-tree.tar" && mv native-tree.tar.sha256 "camoufox-$DEBVER-aarch64-tree.tar.sha256" )
  ls -la "$OUT"/camoufox-* | tee -a "$OUT/build.log"
  exit 0
else
  echo "BUILD FAILED or binary missing (log preserved)" >&2
  exit "${RC_B:-1}"
fi | tee -a "$OUT/configure.log"
[ "$RC" = 0 ] \
  && step "CONFIGURE OK" \
  || { step "CONFIGURE FAILED (tail above; full log in artifact)"; exit "$RC"; }
