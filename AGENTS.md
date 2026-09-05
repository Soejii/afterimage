# Afterimage Agent Instructions

These instructions apply to the entire repository.

## Project scope

Afterimage is a Flutter desktop application for recording Guilty Gear -Strive-
saved replays through OBS. It targets 64-bit Linux and Windows. The separate
`ggst-replay-recorder` repository is a behavioral reference, not part of this
project.

The ports-and-adapters map and recording safety invariants are documented in
[`docs/architecture.md`](docs/architecture.md).

## Toolchain

- Use the Flutter version pinned in `.fvmrc`, currently Flutter `3.47.2`.
- Run Flutter and Dart commands through FVM. Do not use bare `flutter` or
  `dart` commands locally.
- Never run two Flutter builds concurrently.
- Keep Linux and Windows platform support intact unless a task explicitly
  changes the supported platforms.

## Required verification

Run the checks relevant to the change:

```bash
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
```

Changes to Flutter widgets, plugins, native APIs, packaging, or generated
platform integration also require a real Linux release build:

```bash
fvm flutter build linux --release
```

Windows release builds run on the native Windows GitHub Actions job. Do not
claim a Windows build was verified locally from Linux. A regression test must
be demonstrated failing for the expected reason before the fix, then passing
with the fix restored.

## Local Wofi deployment

**The installed application must never be older than the work.** Suji launches
Afterimage from Wofi with Super+R and expects that copy to contain whatever
changed. Finishing a session without updating it means he tests yesterday's
build and reports defects that were already fixed, so treat the redeploy as
part of the change, not as an optional follow-up.

- After every implementation or fix that changes runtime behavior, and again
  before reporting a session finished, run the required checks and
  `fvm flutter build linux --release`, then replace the complete portable
  bundle at `/home/suji/.local/opt/afterimage`. Wofi launches
  `/home/suji/.local/opt/afterimage/afterimage` through
  `/home/suji/.local/share/applications/io.github.soejii.afterimage.desktop`.
- When a release was cut from CI, deploy that artifact rather than a local
  build, so the installed copy is byte-identical to what users download.
- Replacing the bundle under a running process does not update that process.
  Say plainly that Afterimage must be relaunched, and never kill it yourself
  while a batch could be recording.
- Keep a rollback copy until the updated Wofi-launched app passes a live
  acceptance check. Replace the whole bundle, not only the executable, because
  its `data` and `lib` directories must stay synchronized.
- Afterimage has no icon of its own. The desktop entry uses the themed name
  `media-record`. Do not put an image back into the bundle without one that is
  good enough to ship.
- Restart only Afterimage when deploying. Do not stop or restart GGST or OBS.
- Keep the user-local bundle, rollback copy, and desktop entry out of Git.

## Safety boundaries

- Process-memory adapters are read-only. Never add game-memory writes, patches,
  or broad permission changes.
- Do not weaken Linux ptrace policy, make `/proc` broadly readable, or install
  privileged rules automatically.
- Do not silently fall back from controller input to keyboard input. Report
  unavailable input modes clearly and keep recording locked.
- Never overwrite existing recordings. Preserve partial output when stopping or
  recovering from a failure.
- Do not start a recording while OBS is already recording.
- Setup checks must remain read-only and must explain how the user can resolve
  each blocker.

## Documentation and releases

- Keep `README.md` and the matching file under `docs/` aligned with runtime,
  installation, controller, or packaging changes.
- Put architecture changes in `docs/architecture.md`, not `README.md`.
- Put release-status changes in `docs/status.md`, not `README.md`.
- Release archives are portable bundles. The executable must remain beside its
  bundled `data` and `lib` directories.
- Treat live GGST automation as unverified unless it was exercised end to end
  on the named operating system and hardware.
