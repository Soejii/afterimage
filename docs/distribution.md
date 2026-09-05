# Distribution

Afterimage is a self-contained Flutter desktop app. People using a release do
not need Python, Flutter, Dart, or a compiler.

## Automated bundles

The `Build desktop apps` GitHub Actions workflow tests and builds the project on
native Linux and Windows runners. Each successful run uploads:

- `afterimage-linux-x64.tar.gz`
- `afterimage-windows-x64.zip`

These are portable bundles. Extract the whole archive before starting the app,
because the executable needs the libraries and data beside it.

The public alpha downloads are available on the
[Releases](https://github.com/Soejii/afterimage/releases):

- Windows: extract `afterimage-windows-x64.zip`, then run `afterimage.exe`.
- Linux: extract `afterimage-linux-x64.tar.gz`, then run `./afterimage` from the
  extracted folder.

The release page publishes a SHA-256 digest for each asset. On Linux, compare it
with `sha256sum afterimage-linux-x64.tar.gz`. In Windows PowerShell, use:

```powershell
Get-FileHash .\afterimage-windows-x64.zip -Algorithm SHA256
```

## Runtime requirements

Everyone needs Guilty Gear -Strive-, OBS Studio, and at least one saved replay.
Afterimage guides the user through the local OBS connection. The term
"WebSocket" describes the local control link Afterimage uses to start and stop
OBS recordings; users only need to enable the server when the app asks them to.

Linux needs the GTK 3 desktop runtime. Linux keyboard automation additionally
needs X11, XTest, and a gamescope X display. The app reads Steam's app manifest
and configured library folders to locate GGST and its Proton save directory.
Native Steam, Flatpak Steam, and additional Steam library folders are checked
when their files are visible to the desktop app. Windows checks common Steam
locations, environment-provided locations, and read-only Steam registry values.
If automatic discovery fails, Setup provides a folder selection path.

The first recording is intended to be one replay. Confirm that the test video
has both picture and sound before recording a larger batch. Each batch is kept
in its own output folder, and the results screen provides the saved video and
folder paths.

## Updating and removing

Install an update by extracting the new archive into a new folder. Do not mix
files from different versions. Recordings stay in the output folder selected by
the user.

Remove Afterimage by closing the app and deleting the extracted folder. The
portable bundle does not install services, drivers, or language runtimes.
Optional Linux permission changes and the optional Windows ViGEmBus driver are
manual system changes outside the bundle and must be reverted separately.

Portable archives are the first distribution target. A signed Windows
installer and a Linux store package should be added only after the application
identity, publisher name, signing strategy, and release license are chosen.

## Verification boundary

Automated tests cover discovery, setup checks, and the portable application
contracts. A live GGST recording still needs verification on the named
operating system, with the user's OBS scene, audio sources, and display setup.
Linux process-memory, gamescope, XTest, and optional uinput checks remain
dependent on the local desktop policy. Windows native input and controller
drivers likewise require a native Windows run; a Linux build cannot prove that
behavior.
