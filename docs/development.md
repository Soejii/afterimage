# Development

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
