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

## Architecture

Ports and adapters. `lib/domain/recorder_contracts.dart` is the seam: the batch
engine talks only to `ReplayMonitorPort`, `MenuInputPort`, `ObsRecorderPort`,
`OutputOrganizerPort`, `SummaryWriterPort`, and `ReplayClock`. Nothing in
`lib/domain` or `lib/services/replay_batch_engine.dart` touches `dart:ffi`,
process memory, or a socket. Add a capability by extending a contract, not by
reaching into an adapter from the engine.

**Domain** (`lib/domain/`) is pure data and one algorithm.
`replay_batch.dart` holds `ReplayCompletionDetector`, which decides a replay is
over from noisy snapshots: it requires observed frame movement before a battle
counts as started, then ends on match-result event `15` or on
`absentPollsRequired` consecutive missing reads. A frozen frame is a pause, not
an ending. This mirrors the separate `ggst-replay-recorder` reference and is
deliberately conservative; loosening it silently truncates recordings.

**Engine** (`lib/services/replay_batch_engine.dart`) is the state machine over
`ReplayBatchState`, driving per-replay recording (`VideoMode.separate`) or one
recording per batch (`VideoMode.combined`). It owns OBS connect/close in its own
lifecycle and never lets a close error replace the primary `ReplayBatchResult`.

**Platform adapters** implement the contracts twice, once per OS, and are chosen
at runtime by `createPlatformNativeRecorderBackend` in
`platform_native_backend.dart`. Each set is `*_process_memory.dart` (read-only
pattern scan for the `GWorld` pointer, then a fixed offset chain to frame and
event data), `*_replay_monitor.dart`, `*_menu_input.dart`, `*_native_backend.dart`.
Linux input is XTest against the gamescope X display, plus optional
`linux_uinput_controller.dart`; Windows is `SendInput`, plus optional
`windows_virtual_controller.dart` over the FFI shim built from
`windows/runner/afterimage_controller.cpp`.

**Pure-Dart services** (`lib/services/`) are platform-neutral and directly
testable: `obs_websocket_recorder.dart` (OBS WebSocket v5 client),
`obs_config_discovery.dart`, `setup_service.dart` (Steam manifests, library
folders, Flatpak, Proton save paths), `output_organizer.dart`,
`summary_writer.dart`, `batch_output_directory.dart`,
`output_directory_preflight.dart`, `recorder_preferences.dart`.

**Presentation** (`lib/presentation/`) is a `ChangeNotifier` view model plus
widgets. `RecorderController` is where the start/stop lifecycle guards live; the
screens read `canStart` and render `blockers` as text. Adding a new
precondition means adding a reason to `RecorderController.blockers`, not
disabling a button in a widget.

## Invariants that the code enforces on purpose

Several of these look like defensive noise until you change them and a test
turns red. They come from `AGENTS.md`'s safety boundaries.

- **Start stays locked** until every required `SetupCheck`, the OBS connection,
  the readiness of the *selected* input mode, and the output folder all pass.
  With `enforceGuidedChecks` (production, set in `main.dart`), a batch above one
  replay also requires the user to have confirmed picture and sound on a test
  recording.
- **Setup checks are read-only.** They locate the game, replays, and OBS without
  creating, editing, or deleting anything, and every blocked check must explain
  how to resolve it.
- **Process memory is read-only.** `process_vm_readv` first, `/proc/<pid>/mem`
  opened read-only as fallback; no write descriptor or write API is exposed.
- **No silent input fallback.** An unavailable controller reports itself and
  keeps recording locked. It never degrades to keyboard.
- **Nothing is overwritten.** The organizer moves with collision-checked names
  and leaves the source in place when a move cannot complete. A failure or a
  stop preserves whatever OBS already produced as a partial output. A batch
  never starts while OBS is already recording.
- **Each batch gets a fresh directory** reserved atomically by
  `BatchOutputDirectory`, so fixed `replay_NNN` names cannot collide across runs.
  `summary.json` is checkpointed by temp-file rename, guarded by an exclusive
  `summary.json.afterimage.lock` so two Afterimage batches cannot checkpoint
  into one folder.
- **Credentials never reach disk or logs.** `recorderPreferenceKeys` is an
  allowlist and excludes the OBS password; `ObsConnectionService` keeps it in
  memory only.

## Testing conventions

Tests inject seams rather than mock frameworks. Time is a `ReplayClock`, so
timeout, poll, and stop behavior is asserted without real waiting (see
`_FakeClock` in `test/replay_batch_test.dart`) rather than with real delays. OBS tests run
against a real local `FakeObsServer` in `test/support/obs_test_support.dart`,
which speaks the actual v5 Hello/Identify handshake and can inject protocol
faults. Widget tests drive `ValueKey`s (`nav-recorder`, `start-batch`,
`replay-count-*`, `output-folder`) and often set an explicit surface size, since
the layout is responsive.

Platform suites stay portable: guard OS-only expectations with
`skip: !Platform.isLinux` rather than assuming the host, so the Windows CI job
runs the same files.

A regression test must be shown failing for the expected reason before the fix
and passing with it restored.
