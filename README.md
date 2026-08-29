# AFTERIMAGE

AFTERIMAGE is a Windows/Linux desktop workspace for turning Guilty Gear -Strive-
replays into recordings with a clear setup checklist and safe preflight lock.

This repository is an independent successor project. The existing
`ggst-replay-recorder` repository remains the separate behavioral reference while
the desktop application is built out.

## Current status

Version `0.1.0+1` is an alpha desktop release:

- Material 3 dark desktop UI with responsive setup and recorder screens.
- Read-only checks for the supported OS, common GGST/Steam locations, the
  `GGST-Win64-Shipping.exe` process, localhost OBS WebSocket port `4455`, and
  `REP###.sav` replay files.
- Production startup selects the real Windows or Linux native backend. Start
  remains locked until the game, OBS, replay library, selected input mode, and
  output folder all pass their checks.
- Keyboard automation is implemented on Windows through `SendInput` and on
  Linux through targeted gamescope XTest events. Linux also supports an
  optional `uinput` virtual controller. Windows reports controller mode as
  unavailable instead of silently falling back to keyboard.
- No Python installation is needed. Release builds are intended to be
  self-contained.
- The replay batch engine is now ported behind testable Dart contracts. It waits
  for frame movement before starting a battle, requires a result event or a
  duration-derived run of missing reads to finish it, and treats frozen frames
  as an in-progress replay.
- Separate recording stops and organizes once per replay. Combined recording
  stops and organizes once per batch. Failures and stop requests preserve the
  current source output as a partial recording when possible.
- OBS WebSocket v5 control now supports localhost configuration discovery,
  Hello/Identify authentication, request timeouts, request failures, and safe
  close handling. Setup marks OBS ready only after this protocol and idle-state
  probe succeeds.
- Completed and partial outputs use collision-checked replay or combined names,
  preserve the OBS file extension, and leave the source recoverable when a move
  cannot be completed. `summary.json` is checkpointed after each replay and at
  terminal batch states through a temporary-file rename that is atomic where
  the platform supports replacement, with a durable backup/restore fallback
  elsewhere. A small hidden lock file prevents two active Afterimage batches
  from checkpointing into the same output folder at once.

No files are installed, modified, or deleted by the setup checks. The recorder
provides a native output-folder picker, live progress, safe Stop, terminal
results, and paths to preserved output.

The native adapters and UI are covered by automated tests, but live GGST input
and process-memory operation still need end-to-end verification on both target
operating systems before this should be called a stable release.

## Development

Use the project Flutter SDK through FVM:

```bash
fvm flutter pub get
fvm flutter run -d linux
```

The generated project contains Linux and Windows targets only. Native process,
memory, input, and recording contracts live under `lib/domain`. OBS control,
output organization, and summary persistence are implemented in pure Dart
services. Windows and Linux native monitors and keyboard adapters are
implemented behind those contracts, along with the optional Linux controller.
The OBS, discovery, setup-probe, organizer, summary, batch-engine, native
adapter, controller, and recorder UI behavior has dedicated automated coverage.

## Architecture

`lib/domain/replay_batch.dart` contains the immutable snapshots, completion
detector, timing, progress, events, and batch result types. The detector mirrors
the conservative behavior of the separate `ggst-replay-recorder` reference.

`lib/services/replay_batch_engine.dart` owns the batch state machine. It depends
only on `ReplayMonitorPort`, `MenuInputPort`, `ObsRecorderPort`, and
`OutputOrganizerPort` from `lib/domain/recorder_contracts.dart`, plus the
`SummaryWriterPort` checkpoint sink. A monotonic `ReplayClock` is injected so
timeout, polling, failure, and stop behavior can be tested without waiting in
real time. The engine explicitly connects and closes OBS in its lifecycle and
does not let close errors replace the primary batch result.

`lib/services/obs_websocket_recorder.dart` is a small OBS WebSocket v5 client.
`lib/services/obs_config_discovery.dart` reads native Linux, Flatpak Linux, and
Windows config locations without writing credentials to disk or logs.
`lib/services/output_organizer.dart` performs collision-checked moves, while
`lib/services/summary_writer.dart` writes durable JSON checkpoints.

The Linux adapter lives in `lib/services/linux_process_memory.dart`,
`linux_replay_monitor.dart`, `linux_menu_input.dart`, and
`linux_native_backend.dart`. It uses read-only process memory and targeted
gamescope XTest input, with optional uinput controller support in
`linux_uinput_controller.dart`. See
[`docs/linux-runtime.md`](docs/linux-runtime.md) and
[`docs/linux-controller.md`](docs/linux-controller.md) for runtime packages,
safe process-memory permission troubleshooting, and optional controller setup.

The Windows adapter lives in `windows_process_memory.dart`,
`windows_replay_monitor.dart`, `windows_menu_input.dart`, and
`windows_native_backend.dart`. See
[`docs/windows-runtime.md`](docs/windows-runtime.md). Native Windows builds are
compiled by GitHub Actions because this Linux development machine cannot
perform a real Windows build locally.
