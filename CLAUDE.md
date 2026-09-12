# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` holds the repository policy (toolchain, safety boundaries, deployment,
documentation rules) and applies here in full. This file adds the commands and the
architecture map.

## Commands

The Flutter SDK is pinned to `3.47.2` in `.fvmrc`. Always go through FVM; a bare
`flutter`/`dart` resolves to a newer machine-wide default.

```bash
fvm flutter pub get
fvm flutter run -d linux

# Gates, same as the GitHub Actions job
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test

# One file, or one test by name
fvm flutter test test/replay_batch_test.dart
fvm flutter test test/replay_batch_test.dart --plain-name 'stop request'

# Required for widget, plugin, native, or packaging changes
fvm flutter build linux --release
```

`fvm flutter analyze` is a usable gate here: the baseline is zero diagnostics, so
anything it prints is a regression from the current change. Do not substitute
`flutter-analyze-diff`; that tool exists for the noisy SIDIGS repos, not this one.

Windows is built only by the `Build desktop apps` workflow on a native Windows
runner. A Linux machine cannot verify a Windows build, and `windows/` links
ViGEmClient sources that CMake fetches at configure time.

After any change to runtime behavior, redeploy the whole portable bundle to
`/home/suji/.local/opt/afterimage` per `AGENTS.md`; the executable, `data/`, and
`lib/` must stay in sync.

## Release delivery

Every new change shipped to users must appear on GitHub's Tags and Releases
pages. Follow the full release policy in `AGENTS.md`: align the application
version, create a new version tag on the shipped commit, and publish a matching
GitHub Release with the complete Linux and Windows portable bundles from
successful builds of that exact commit. Never move an existing release tag
or replace older release assets.

An Actions artifact or automatic source archive does not complete delivery.
Verify the tag, published release, and both downloadable application assets,
then give Suji the release link. Keep the existing alpha/pre-release convention
and disclose unverified GGST behavior. Deploy the released Linux bundle to Wofi
as required by `AGENTS.md`.

Include publication when shipping changes unless Suji explicitly requests
local, unpublished, or build-only work. Report any publication blocker rather
than claiming the release is complete.

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for the ports-and-adapters
layer map, service responsibilities, and intentional recording-safety
invariants.

## Testing conventions

Tests inject seams rather than mock frameworks. Time is a `ReplayClock`, so
timeout, poll, and stop behavior is asserted without real waiting (see
`_FakeClock` in `test/replay_batch_test.dart`) rather than with real delays. OBS tests run
against a real local `FakeObsServer` in `test/support/obs_test_support.dart`,
which speaks the actual v5 Hello/Identify handshake and can inject protocol
faults. Widget tests drive `ValueKey`s (`phase-indicator`, `lead-blocker`,
`remaining-blockers`, `start-batch`, `stop-batch`, `replay-count-*`,
`output-folder`, `advanced-options`, `diagnostics-drawer`, `replay-timeline`,
`record-another-batch`) and often set an explicit surface size, since the
layout is responsive. There is no navigation; the single screen switches on
`RecorderController.phase`.

Platform suites stay portable: guard OS-only expectations with
`skip: !Platform.isLinux` rather than assuming the host, so the Windows CI job
runs the same files.

A regression test must be shown failing for the expected reason before the fix
and passing with it restored.
