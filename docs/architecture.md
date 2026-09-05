# Architecture

Afterimage uses a ports-and-adapters pattern. `lib/domain/recorder_contracts.dart`
is the seam: the batch engine talks only to `ReplayMonitorPort`, `MenuInputPort`,
`ObsRecorderPort`, `OutputOrganizerPort`, `SummaryWriterPort`, and `ReplayClock`.
Nothing in `lib/domain` or `lib/services/replay_batch_engine.dart` touches
`dart:ffi`, process memory, or a socket. Add a capability by extending a
contract, not by reaching into an adapter from the engine.

## Domain

The Domain (`lib/domain/`) is pure data and one algorithm.
`lib/domain/replay_batch.dart` holds immutable snapshots, timing, progress, event,
and batch result types, plus `ReplayCompletionDetector`.

The detector decides whether a replay is over from noisy snapshots. It requires
observed frame movement before a battle counts as started, then ends on
match-result event `15` or on `absentPollsRequired` consecutive missing reads. A
frozen frame is a pause, not an ending. This mirrors the separate
`ggst-replay-recorder` reference and is deliberately conservative; loosening it
silently truncates recordings.

## Engine

`lib/services/replay_batch_engine.dart` owns the batch state machine over
`ReplayBatchState`. It drives per-replay recording (`VideoMode.separate`) or one
recording per batch (`VideoMode.combined`). The interface always requests
`VideoMode.combined`; the separate path remains a supported engine capability
with its own tests, but nothing in the UI selects it. `SummaryWriterPort` is its checkpoint
sink.

The engine injects a monotonic `ReplayClock`, so timeout, polling, failure, and
stop behavior can be tested without waiting in real time. It explicitly connects
and closes OBS in its lifecycle and does not let close errors replace the
primary `ReplayBatchResult`.

## Platform adapters

The platform adapters implement the contracts twice, once per operating system.
`createPlatformNativeRecorderBackend` in
`lib/services/platform_native_backend.dart` selects the runtime backend. Each
set includes `*_process_memory.dart`, `*_replay_monitor.dart`,
`*_menu_input.dart`, and `*_native_backend.dart`.

The process-memory adapters use a read-only pattern scan for the `GWorld`
pointer, then a fixed offset chain to frame and event data.

The Linux adapter lives in `lib/services/linux_process_memory.dart`,
`linux_replay_monitor.dart`, `linux_menu_input.dart`, and
`linux_native_backend.dart`. It uses read-only process memory and targeted
gamescope XTest input, with optional uinput controller support in
`linux_uinput_controller.dart`. See
[`linux-runtime.md`](linux-runtime.md) and
[`linux-controller.md`](linux-controller.md) for runtime packages, safe
process-memory permission troubleshooting, and optional controller setup.

The Windows adapter lives in `lib/services/windows_process_memory.dart`,
`windows_replay_monitor.dart`, `windows_menu_input.dart`, and
`windows_native_backend.dart`. Windows input uses `SendInput`, plus an optional
Xbox-compatible virtual controller in `windows_virtual_controller.dart` over the
FFI shim built from `windows/runner/afterimage_controller.cpp`. See
[`windows-runtime.md`](windows-runtime.md). Native Windows builds are compiled
by GitHub Actions because this Linux development machine cannot perform a real
Windows build locally.

## Pure-Dart services

Platform-neutral services live in `lib/services/` and are directly testable:

- `lib/services/obs_websocket_recorder.dart` is a small OBS WebSocket v5 client.
- `lib/services/obs_config_discovery.dart` reads native Linux, Flatpak Linux, and
  Windows config locations without writing credentials to disk or logs.
- `lib/services/setup_service.dart` searches Steam manifests and configured library folders,
  including Flatpak Steam on Linux, then scans the matching Proton save
  locations. User-selected game and replay folders take precedence and setup
  checks do not modify them.
- `lib/services/output_organizer.dart` performs collision-checked moves.
- `lib/services/summary_writer.dart` writes durable JSON checkpoints.
- `lib/services/batch_output_directory.dart`,
  `lib/services/output_directory_preflight.dart`, and
  `lib/services/recorder_preferences.dart` provide platform-neutral output and
  preference services.

## Presentation

The Presentation layer (`lib/presentation/`) is a `ChangeNotifier` view model
plus widgets. `RecorderController` is where the start and stop lifecycle guards
live.

There is one screen. `WorkspaceScreen` switches on `RecorderController.phase`,
which is `checking`, `blocked`, `ready`, `running`, or `done`, and renders the
matching view from `lib/presentation/views/`. Readiness is stated in exactly one
place, `PhaseIndicator`. It used to be derived independently in eight, which is
how the same fact came to be displayed three different ways.

`RecorderController.blockers` returns typed `RecorderBlocker` values, not
strings. Each one carries an id, a short label, a sentence, and the single
action that resolves it, and `RecorderBlockerId` declaration order is the
priority order that decides which blocker leads. Adding a new precondition means
adding a blocker there, never disabling a button in a widget.

`lib/presentation/replay_timeline.dart` turns the engine events the controller
already collects into a row per replay, and collapses the twelve
`ReplayBatchState` values into the four phases a person needs to see.

## Invariants that the code enforces on purpose

Several of these look like defensive noise until you change them and a test
turns red. They come from `AGENTS.md`'s safety boundaries.

- **Start stays locked** until every required `SetupCheck`, the OBS connection,
  the readiness of the selected input mode, and the output folder all pass.
  There is deliberately no default output folder, so an empty one keeps
  recording locked rather than Afterimage choosing where to write video.
- **The interface never records a promise as a fact.** Confirmation checkboxes
  that only stored what the user claimed, about picture and sound and about the
  highlighted replay, were removed. Afterimage cannot read the game's menu
  cursor and does not measure OBS audio, so it states what the Start action will
  do and lets the engine's `startTimeout` catch a wrong cursor on the first
  replay.
- **Setup checks are read-only.** They locate the game, replays, and OBS without
  creating, editing, or deleting anything, and every blocked check must explain
  how to resolve it.
- **Process memory is read-only.** `process_vm_readv` first, then
  `/proc/<pid>/mem` opened read-only as fallback; no write descriptor or write
  API is exposed.
- **No silent input fallback.** An unavailable controller reports itself and
  keeps recording locked. It never degrades to keyboard.
- **Nothing is overwritten.** The organizer moves with collision-checked names
  and leaves the source in place when a move cannot complete. A failure or a
  stop preserves whatever OBS already produced as a partial output. A batch
  never starts while OBS is already recording.
- **Each batch gets a fresh directory** reserved atomically by
  `BatchOutputDirectory`, so fixed `replay_NNN` names cannot collide across
  runs. `summary.json` is checkpointed by temp-file rename, guarded by an
  exclusive `summary.json.afterimage.lock` so two Afterimage batches cannot
  checkpoint into one folder.
- **Credentials never reach disk or logs.** `recorderPreferenceKeys` is an
  allowlist and excludes the OBS password; `ObsConnectionService` keeps it in
  memory only.
