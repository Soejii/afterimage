# AFTERIMAGE

Afterimage records Guilty Gear -Strive- saved replays through OBS Studio on
Windows and Linux. It guides setup checks and keeps recording locked until the
required checks pass.

## Requirements

Before you start, make sure you have:

- Windows 10 or 11, 64-bit, or a 64-bit Linux desktop.
- Guilty Gear -Strive- installed through Steam, with at least one saved replay.
- OBS Studio 28 or later. Version 28 is the first release that bundles the
  WebSocket server Afterimage uses to start and stop recording. The WebSocket
  server must be switched on once, in OBS, under **Tools > WebSocket Server
  Settings**.
- OBS already configured to capture the game picture and sound. Afterimage does
  not create or change OBS scenes or sources.
- On Linux, the GTK 3, X11, and XTest runtime libraries. See
  [`docs/linux-runtime.md`](docs/linux-runtime.md). Keyboard input requires GGST
  to be running through gamescope.
- On Linux, optional controller input, access to `/dev/uinput`. See
  [`docs/linux-controller.md`](docs/linux-controller.md).
- On Windows, optional controller input, the ViGEmBus driver installed
  separately. See [`docs/windows-controller.md`](docs/windows-controller.md).
- Free disk space for the recordings, which are full-length video files.
- No Python, Flutter, Dart, or compiler installation is required. The release
  archive is self-contained.

## Install

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

Afterimage is one screen that changes as you go. It tells you the next thing to
fix, then unlocks recording once nothing is left. You do not need to know what
an OBS WebSocket is.

1. Open OBS and Guilty Gear -Strive-. In GGST, open **Collection > Replay >
   Saved Replays**, and highlight the replay you want to start from. Afterimage
   works upward through the list from there.
2. Open Afterimage. It checks this computer without changing anything, then
   shows the next step. Work through the steps until it says **READY**.
3. If Afterimage cannot find the game or your saved replays, open **Details and
   troubleshooting** and use **Locate game** or **Locate saved replays**. Your
   choice is saved and can be changed later.
4. Choose how many replays to record, and the folder to save them in. The
   folder is remembered for next time.
5. Select **Start recording**. Afterimage shows every replay in the batch with
   its progress, so you can leave it running and check on it later.

Afterimage records the whole batch into one video file. Each batch gets its own
folder, so a second run cannot overwrite the first.

Keep Afterimage, OBS, and GGST open while a batch runs, and do not use the
replay menu yourself during recording. **Stop safely** keeps whatever has
already been recorded. Afterimage will not start while OBS is already
recording.

Afterimage never changes your OBS scenes, sources, or audio. If your video has
no picture or no sound, that is OBS's capture setup, not Afterimage. Record one
replay first to check it before starting a long batch.

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

## More information

- [System structure](docs/architecture.md)
- [Release status](docs/status.md)
- [Development commands](docs/development.md)
- [Linux runtime](docs/linux-runtime.md)
- [Linux controller](docs/linux-controller.md)
- [Windows runtime](docs/windows-runtime.md)
- [Windows controller](docs/windows-controller.md)
- [Distribution](docs/distribution.md)
