# Security Policy

## Reporting a vulnerability

- **Engine vulnerabilities** (Firefox/Camoufox internals): report upstream first — [Mozilla Bug Bounty](https://www.mozilla.org/security/) for Firefox core, [daijro/camoufox](https://github.com/daijro/camoufox/security) for Camoufox-specific behavior.
- **This repository's scripts/patches/CI**: open a [GitHub Security Advisory](https://github.com/bd-loser/camoufox-bionic/security/advisories/new) (private disclosure). Do not open a public issue for exploitable problems.

## Supply-chain model used here

- Camoufox source is **hash-pinned** (repo commit `6f74fa06…`, sdist sha256 `82ba17b0…` for primp — see `ci/patch-primp`-style pins inside `camofox/` scripts; every external fetch in CI carries an explicit sha256 or pinned git SHA)
- Patches must apply **exactly once** against pinned sources; scripts fail loudly on drift (`assert`-based)
- Vendored cargo crate edits trigger an automated checksum reconciliation (`.cargo-checksum.json` sweep)
- Artifacts ship with `.sha256` sidecar files; the install instructions verify before extract

## Reporting a bug (non-security)

Public [issues](https://github.com/bd-loser/camoufox-bionic/issues) are welcome — include `camoufox-bin --version`, Android version, device model, and full logs.
