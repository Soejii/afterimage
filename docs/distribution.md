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
[`v0.1.0` release](https://github.com/Soejii/afterimage/releases/tag/v0.1.0):

- Windows: extract `afterimage-windows-x64.zip`, then run `afterimage.exe`.
- Linux: extract `afterimage-linux-x64.tar.gz`, then run `./afterimage` from the
  extracted folder.

The release page publishes a SHA-256 digest for each asset. On Linux, compare it
with `sha256sum afterimage-linux-x64.tar.gz`. In Windows PowerShell, use:

```powershell
Get-FileHash .\afterimage-windows-x64.zip -Algorithm SHA256
```

## Runtime requirements

Everyone needs Guilty Gear -Strive-, OBS Studio with its WebSocket server
enabled, and saved replays. Linux needs the GTK 3 desktop runtime. Linux
keyboard automation additionally needs X11, XTest, and a gamescope X display.
The app reads Steam's app manifest and configured library folders to locate
GGST. It reports missing recording requirements before it enables recording.

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
