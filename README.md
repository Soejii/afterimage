# AFTERIMAGE

AFTERIMAGE is a Windows/Linux desktop workspace for turning Guilty Gear -Strive-
replays into recordings with a clear setup checklist and safe preflight lock.

This repository is an independent successor project. The existing
`ggst-replay-recorder` repository remains the separate behavioral reference while
the desktop application is built out.

## Install

Afterimage is portable. You do not need to install Python, Flutter, Dart, or a
compiler.

Download the archive for your computer from the
[Releases](https://github.com/Soejii/afterimage/releases),
then follow the matching instructions below. Keep every extracted file together.

### Windows 10 or 11

1. Download `afterimage-windows-x64.zip` from the release page.
2. Right-click the ZIP file, select **Extract All**, and open the extracted
   folder.
3. Double-click `afterimage.exe`.

This alpha build is not code-signed, so Windows may show a security warning.
Only continue if the archive came from the official release page linked above.
Windows supports **Keyboard** input and an optional virtual controller. The
controller mode works alongside a physical Xbox, DualShock, or DualSense pad;
it requires a separately installed ViGEmBus driver. See
[`docs/windows-controller.md`](docs/windows-controller.md).

### 64-bit Linux

1. Install the GTK 3, X11, and XTest runtime libraries listed in
   [`docs/linux-runtime.md`](docs/linux-runtime.md).
2. Download `afterimage-linux-x64.tar.gz` from the release page.
3. Extract the archive with your file manager, or run:

   ```bash
   tar -xzf afterimage-linux-x64.tar.gz
   ```

4. Open the extracted folder and run `afterimage`, or run:

   ```bash
   ./afterimage
   ```

If Linux reports that the file is not executable, run
`chmod +x afterimage` once. Keyboard input requires GGST to be running through
gamescope. Optional controller input uses Linux `uinput`; see
[`docs/linux-controller.md`](docs/linux-controller.md).

## First recording

Afterimage is designed to guide the first recording from one screen. You do
not need to know what an OBS WebSocket is. Afterimage uses OBS as the recorder,
so it can start and stop each video for you.

1. Open OBS and Guilty Gear -Strive-. In GGST, open **Collection > Replay >
   Saved Replays** and leave the replay list visible.
2. Open Afterimage and follow **Setup**. It checks the game, saved replays,
   OBS, and the selected recording method without changing your computer.
3. If a game or replay folder is not found automatically, use **Locate game** or **Locate saved replays**
   in Setup. The selection is saved by the app and can be changed later.
4. Afterimage starts with **one replay**. Use this short test to confirm that
   the video shows the game and that its sound is present.
5. Choose a larger **Batch size** only after the test video looks and sounds
   right. **Replay controls** contains the keyboard or virtual-gamepad choice.
6. Choose an output folder and start the batch. Each batch gets its own folder
   so a second run cannot overwrite the first. The results screen can open the
   folder and the saved video.

Keep Afterimage and GGST open while a batch runs. Do not operate the replay
menu during recording. **Stop safely** keeps the current recording as a
partial output when OBS has already created it. Afterimage does not start when
OBS is already recording.

If OBS is not detected, open **Tools > WebSocket Server Settings** in OBS,
enable the server, and apply the change. The default local port is `4455`.
Password and port details are only needed when OBS uses settings different from
the usual local setup.

## Update or uninstall

To update, download the newer archive from the
[`Releases`](https://github.com/Soejii/afterimage/releases) page and extract it
into a new folder. Your recordings remain in the output folder you selected.

To uninstall, close Afterimage and delete its extracted folder. Afterimage does
not install Python, services, drivers, or system-wide files. A Linux controller
permission rule, if you added one manually, must be removed separately.

## Troubleshooting

- **The app does not start on Linux:** install the GTK 3 runtime and the X11
  packages from [`docs/linux-runtime.md`](docs/linux-runtime.md).
- **OBS is not ready:** open OBS, enable its WebSocket server, and select
  **Refresh checks**. If Afterimage asks for a password, enter the password
  shown in OBS's WebSocket Server Settings.
- **GGST or saved replays are not found:** start GGST and Afterimage as the
  same user, then use **Locate game** or **Locate saved replays** in Setup,
  or select **Refresh checks**.
- **Keyboard input does nothing on Windows:** run GGST and Afterimage at the same
  Windows integrity level. Normally, neither should be run as administrator.
- **Keyboard input is blocked on Linux:** launch GGST through gamescope and
  install `libX11` and `libXtst` for your distribution.
- **Controller input is unavailable on Linux:** Afterimage needs access to
  `/dev/uinput`. Keyboard remains available.
- **Controller input is unavailable on Windows:** install ViGEmBus manually,
  restart Afterimage, and refresh the setup checks. Afterimage never installs
  or changes a driver automatically.

For detailed platform diagnostics, see
[`docs/windows-runtime.md`](docs/windows-runtime.md) or
[`docs/linux-runtime.md`](docs/linux-runtime.md).

## Current status

Version `0.1.1+2` is an alpha desktop release:

- Material 3 dark desktop UI with responsive setup and recorder screens.
- Read-only checks for the supported OS, GGST Steam app manifests across
  configured library folders, the `GGST-Win64-Shipping.exe` process, the local
  OBS recording connection, and `REP###.sav` replay files. Linux discovery
  follows native and Flatpak Steam library folders; Windows also checks common
  environment paths and Steam's read-only registry entries.
- Production startup selects the real Windows or Linux native backend. Start
  remains locked until the game, OBS, replay library, selected input mode, and
  output folder all pass their checks.
- Keyboard automation is implemented on Windows through `SendInput` and on
  Linux through targeted gamescope XTest events. Linux also supports an
  optional `uinput` virtual controller. Windows supports an optional
  Xbox-compatible virtual controller through a separately installed ViGEmBus
  driver. Neither platform consumes the user's physical controller, and neither
  silently falls back to keyboard.
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
provides guided folder selection, a one-replay test path, an output-folder
picker, live progress, safe Stop, terminal results, and paths to preserved
output.

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
`lib/services/setup_service.dart` searches Steam manifests and configured
library folders, including Flatpak Steam on Linux, then scans the matching
Proton save locations. User-selected game and replay folders take precedence
without being modified by setup checks.
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
