# Contributing to camoufox-bionic

Thanks for helping make a native Termux/Firefox port better. This repo has one unusual property that shapes contribution rules:

> **Firefox has (before this project) never been built natively on Bionic.** Every build failure lands in unexplored territory. The value of this repo is *as much the recorded root-cause knowledge as the code* — please preserve that property.

## Ground rules

1. **Every behavioral change ships with evidence.** A fix must state: error, root cause (file:line or mechanism), and the fix. If it cannot be explained that way, it isn't understood yet.
2. **Patch discipline.** Tree patches live in `camofox/termux-patches/` (numbered). Each must:
   - match exactly one location (the patch scripts `assert`-fail on drift),
   - carry a comment stating *why* (which termux/bionic limitation it addresses),
   - be validated locally against the pristine source before a CI run.
3. **No drive-by flag changes.** mozconfig options affect the whole graph; changes need a stated reason and a build run.
4. **Ports over filters.** Don't "fix" a Bionic issue by disabling unrelated features silently. Document in `docs/TROUBLESHOOTING.md` instead.

## Workflow

1. Fork → branch `experiment/<topic>`
2. For CI experiments use the `experimental=true` input or a branch — the default publish path updates the release artifact users install
3. CI: `camofox-build.yml` (configure + build + package + sha256)
4. PRs must include: the run URL, and for failures the new root-cause entry for `docs/TROUBLESHOOTING.md`

## Testing on-device

Minimum bar before "works": `--version`, XPCOM boot (chrome resources load), Playwright juggler launch + navigate + DOM read + screenshot. Prefer testing in a `~/browsers/camoufox-test` dir first.

## Report upstream too

If a bug is in juggler/intl/platform code (not our patches), file it upstream (`daijro/camoufox`) and mention the Bionic rebuild — see `docs/TROUBLESHOOTING.md` for the example format ([#909](https://github.com/daijro/camoufox/issues/909)).
