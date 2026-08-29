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

## Runtime requirements

Everyone needs Guilty Gear -Strive-, OBS Studio with its WebSocket server
enabled, and saved replays. Linux keyboard automation additionally needs X11,
XTest, and a gamescope X display. The app reports missing runtime requirements
before it enables recording.

Portable archives are the first distribution target. A signed Windows
installer and a Linux store package should be added only after the application
identity, publisher name, signing strategy, and release license are chosen.
