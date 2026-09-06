import 'dart:io';

import '../domain/obs_models.dart';
import '../domain/recorder_contracts.dart';
import '../domain/setup_models.dart';
import 'obs_readiness_probe.dart';
import 'setup_locations.dart';

abstract interface class SetupService {
  Future<SetupReport> inspect();
}

/// Performs the small set of local checks that can be honest before the native
/// recorder implementation is shipped. It never installs software or changes
/// machine state.
class LocalSetupService implements SetupService {
  const LocalSetupService({
    this.obsProbe = const LocalObsReadinessProbe(),
    this.nativeBackend,
    this.locations,
    this.locationProvider,
    this.replayRootCandidates,
    this.steamLibraryRootCandidates,
  });

  static const _gameAppId = '1384160';
  static const _gameExecutable = 'GGST-Win64-Shipping.exe';
  static const _gameInstallFolder = 'GUILTY GEAR STRIVE';
  final ObsReadinessProbe obsProbe;
  final NativeRecorderBackend? nativeBackend;
  final LocalSetupLocations? locations;
  final LocalSetupLocations? Function()? locationProvider;
  final Iterable<String>? replayRootCandidates;
  final Iterable<String>? steamLibraryRootCandidates;

  @override
  Future<SetupReport> inspect() async {
    final selectedLocations = locationProvider?.call() ?? locations;
    // Resolve Steam roots once and share the result between game and replay
    // discovery. Both scans use asynchronous filesystem APIs so a large Steam
    // library does not block the Flutter UI isolate while setup is refreshed.
    final steamLibraryRootsFuture = _steamLibraryRoots();
    final gamePathFuture = steamLibraryRootsFuture.then(
      (roots) => _findGameInstall(roots, selectedLocations),
    );
    final replayInventoryFuture = steamLibraryRootsFuture.then(
      (roots) => _inspectReplayLibrary(roots, selectedLocations),
    );
    final gameRunningFuture = _isGameRunning();
    final obsProbeFuture = _inspectObs();
    final nativeReadinessFuture = _inspectNativeBackend();

    final gamePath = await gamePathFuture;
    final replayInventory = await replayInventoryFuture;
    final gameRunning = await gameRunningFuture;
    final obsResult = await obsProbeFuture;
    final nativeReadiness = await nativeReadinessFuture;
    final keyboardReadiness = await _inspectInput(
      InputMode.keyboard,
      nativeReadiness,
    );
    final controllerReadiness = await _inspectInput(
      InputMode.controller,
      nativeReadiness,
    );
    final supported = Platform.isLinux || Platform.isWindows;
    final platformName = Platform.operatingSystem;

    return SetupReport(
      checkedAt: DateTime.now(),
      replayCount: replayInventory.count,
      checks: [
        SetupCheck(
          id: SetupCheckId.supportedPlatform,
          title: 'Desktop system',
          detail: supported
              ? 'Afterimage is running on $platformName, which is supported.'
              : 'Afterimage currently supports Linux and Windows desktop builds.',
          status: supported ? SetupCheckStatus.ready : SetupCheckStatus.blocked,
          required: true,
          value: platformName,
        ),
        SetupCheck(
          id: SetupCheckId.gameInstall,
          title: 'Game',
          detail: gamePath == null
              ? _missingGameDetail(selectedLocations)
              : 'Guilty Gear -Strive- was found${_hasGameOverride(selectedLocations) ? ' in the selected folder' : ''}.',
          status: gamePath == null
              ? SetupCheckStatus.blocked
              : SetupCheckStatus.ready,
          required: true,
          value: gamePath,
        ),
        SetupCheck(
          id: SetupCheckId.gameRunning,
          title: 'Game running',
          detail: gameRunning
              ? 'Guilty Gear -Strive- is open.'
              : 'Open Guilty Gear -Strive- before recording, then refresh checks.',
          status:
              gameRunning ? SetupCheckStatus.ready : SetupCheckStatus.blocked,
          required: true,
        ),
        SetupCheck(
          id: SetupCheckId.obsWebSocket,
          title: 'OBS connection',
          detail: obsResult.detail,
          status: obsResult.ready
              ? SetupCheckStatus.ready
              : SetupCheckStatus.blocked,
          required: true,
          value: obsResult.config?.sourcePath ??
              (obsResult.config == null
                  ? null
                  : '${obsResult.config!.host}:${obsResult.config!.port}'),
        ),
        SetupCheck(
          id: SetupCheckId.replayLibrary,
          title: 'Saved replays',
          detail: _replayDetail(replayInventory, selectedLocations),
          status: replayInventory.count > 0
              ? SetupCheckStatus.ready
              : SetupCheckStatus.blocked,
          required: true,
          value: replayInventory.root,
        ),
        SetupCheck(
          id: SetupCheckId.keyboardInput,
          title: 'Keyboard input',
          detail: keyboardReadiness.detail,
          status: keyboardReadiness.available
              ? SetupCheckStatus.ready
              : SetupCheckStatus.notice,
          required: false,
        ),
        SetupCheck(
          id: SetupCheckId.controllerInput,
          title: 'Controller',
          detail: controllerReadiness.detail,
          status: controllerReadiness.available
              ? SetupCheckStatus.ready
              : SetupCheckStatus.notice,
          required: false,
        ),
        SetupCheck(
          id: SetupCheckId.nativeRecorderBackend,
          title: 'Recording support',
          detail: nativeReadiness.detail,
          status: nativeReadiness.available
              ? SetupCheckStatus.ready
              : SetupCheckStatus.blocked,
          required: true,
        ),
      ],
    );
  }

  Future<String?> _findGameInstall(
    List<String> libraryRoots,
    LocalSetupLocations? selectedLocations,
  ) async {
    final explicitDirectory = _explicitGameDirectory(selectedLocations);
    if (explicitDirectory != null) {
      try {
        return await Directory(explicitDirectory).exists()
            ? explicitDirectory
            : null;
      } on FileSystemException {
        return null;
      }
    }

    for (final libraryRoot in libraryRoots) {
      final path = await _gameInstallFromManifest(libraryRoot);
      if (path != null) {
        return path;
      }
    }

    for (final libraryRoot in libraryRoots) {
      final path = _joinParts(
        libraryRoot,
        ['steamapps', 'common', _gameInstallFolder],
      );
      try {
        if (await Directory(path).exists()) {
          return path;
        }
      } on FileSystemException {
        // A malformed or inaccessible optional candidate should not stop the
        // remaining checks.
      }
    }
    return null;
  }

  Future<List<String>> _steamLibraryRoots() async {
    final suppliedRoots = steamLibraryRootCandidates;
    final roots = suppliedRoots == null
        ? await _defaultSteamLibraryRoots()
        : _unique(suppliedRoots);
    final discoveredRoots = <String>[...roots];

    for (final root in roots) {
      final libraryFolders = File(
        _joinParts(root, ['steamapps', 'libraryfolders.vdf']),
      );
      discoveredRoots.addAll(await _readVdfValues(libraryFolders, 'path'));
    }

    return _unique(discoveredRoots);
  }

  Future<List<String>> _defaultSteamLibraryRoots() async {
    final environment = Platform.environment;
    final home = environment['HOME'] ?? environment['USERPROFILE'] ?? '';

    if (Platform.isWindows) {
      final programFiles = environment['ProgramFiles'] ?? r'C:\Program Files';
      final programFilesX86 =
          environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      final environmentRoots = [
        environment['STEAM_ROOT'],
        environment['STEAM_PATH'],
        environment['ProgramW6432'] == null
            ? null
            : _joinParts(environment['ProgramW6432']!, ['Steam']),
        _joinParts(programFilesX86, ['Steam']),
        _joinParts(programFiles, ['Steam']),
        environment['LOCALAPPDATA'] == null
            ? null
            : _joinParts(environment['LOCALAPPDATA']!, ['Steam']),
        environment['APPDATA'] == null
            ? null
            : _joinParts(environment['APPDATA']!, ['Steam']),
      ].whereType<String>();
      return _unique([
        ...environmentRoots,
        ...await _readWindowsSteamRegistryRoots(),
      ]);
    }

    return _unique([
      _joinParts(home, ['.steam', 'steam']),
      _joinParts(home, ['.local', 'share', 'Steam']),
      _joinParts(home, [
        '.var',
        'app',
        'com.valvesoftware.Steam',
        '.local',
        'share',
        'Steam',
      ]),
      _joinParts(home, [
        '.var',
        'app',
        'com.valvesoftware.Steam',
        'data',
        'Steam',
      ]),
      _joinParts(home, ['Games']),
    ]);
  }

  Future<String?> _gameInstallFromManifest(String libraryRoot) async {
    final manifest = File(
      _joinParts(
        libraryRoot,
        ['steamapps', 'appmanifest_$_gameAppId.acf'],
      ),
    );
    final installDirectories = await _readVdfValues(manifest, 'installdir');
    if (installDirectories.isEmpty) {
      return null;
    }

    final installDirectory = installDirectories.first;
    if (!_isSafeInstallDirectory(installDirectory)) {
      return null;
    }

    final path = _joinParts(
      libraryRoot,
      ['steamapps', 'common', installDirectory],
    );
    try {
      return await Directory(path).exists() ? path : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<List<String>> _readVdfValues(File file, String requestedKey) async {
    final values = <String>[];
    final entryPattern = RegExp(
      r'^\s*"([^"]+)"\s*"((?:\\.|[^"])*)"\s*$',
    );

    try {
      for (final line in await file.readAsLines()) {
        final match = entryPattern.firstMatch(line);
        if (match == null || match.group(1) != requestedKey) {
          continue;
        }
        values.add(_decodeVdfValue(match.group(2)!));
      }
    } on FileSystemException {
      return const [];
    } on FormatException {
      return const [];
    }

    return values;
  }

  Future<List<String>> _readWindowsSteamRegistryRoots() async {
    if (!Platform.isWindows) {
      return const [];
    }

    // `reg query` only reads the registry. Query both the per-user Steam key
    // and the machine keys used by 32-bit and 64-bit Steam installations.
    final keys = [
      r'HKEY_CURRENT_USER\Software\Valve\Steam',
      r'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam',
      r'HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam',
    ];
    final valuePattern = RegExp(
      r'^\s*(?:SteamPath|InstallPath)\s+REG_\w+\s+(.+?)\s*$',
      caseSensitive: false,
    );
    final roots = <String>[];

    for (final key in keys) {
      try {
        final result = await Process.run('reg', ['query', key]);
        if (result.exitCode != 0) {
          continue;
        }
        final output = '${result.stdout}\n${result.stderr}';
        for (final line in output.split(RegExp(r'\r?\n'))) {
          final match = valuePattern.firstMatch(line);
          if (match != null) {
            roots.add(match.group(1)!);
          }
        }
      } on ProcessException {
        // Registry discovery is optional. Environment and standard paths still
        // provide useful candidates when `reg.exe` is unavailable.
      }
    }

    return _unique(roots);
  }

  String _decodeVdfValue(String value) {
    return value.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
  }

  bool _isSafeInstallDirectory(String value) {
    return value.isNotEmpty &&
        value != '.' &&
        value != '..' &&
        !value.contains('/') &&
        !value.contains('\\');
  }

  Future<_ReplayInventory> _inspectReplayLibrary(
    List<String> steamLibraryRoots,
    LocalSetupLocations? selectedLocations,
  ) async {
    final roots = <String>[];

    final explicitDirectory = _explicitReplayDirectory(selectedLocations);
    if (explicitDirectory != null) {
      roots.add(explicitDirectory);
    } else if (replayRootCandidates != null) {
      roots.addAll(replayRootCandidates!);
    } else {
      final environment = Platform.environment;

      if (Platform.isWindows) {
        final localAppData = environment['LOCALAPPDATA'] ?? '';
        final appData = environment['APPDATA'] ?? '';
        for (final base in [localAppData, appData]) {
          if (base.isNotEmpty) {
            roots.add(_joinParts(base, [
              'GGST',
              'Saved',
              'SaveGames',
            ]));
          }
        }
      } else {
        // Steam's configured library roots are the source of truth. This
        // includes libraries declared by Flatpak Steam's libraryfolders.vdf,
        // as well as libraries outside the usual home directories.
        for (final steamHome in steamLibraryRoots) {
          roots.add(_joinParts(steamHome, [
            'steamapps',
            'compatdata',
            '1384160',
            'pfx',
            'drive_c',
            'users',
            'steamuser',
            'AppData',
            'Local',
            'GGST',
            'Saved',
            'SaveGames',
          ]));
        }
      }
    }

    _ReplayInventory? firstEmptyInventory;
    for (final root in _unique(roots)) {
      final directory = Directory(root);
      try {
        if (!await directory.exists()) {
          continue;
        }

        var count = 0;
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File &&
              RegExp(r'^REP\d{3}\.sav$', caseSensitive: false)
                  .hasMatch(entity.uri.pathSegments.last)) {
            count++;
          }
        }
        if (count > 0) {
          return _ReplayInventory(root: root, count: count);
        }
        firstEmptyInventory ??= _ReplayInventory(root: root);
      } on FileSystemException {
        // Keep checking the other known Steam roots.
      }
    }

    return firstEmptyInventory ?? const _ReplayInventory();
  }

  Future<bool> _isGameRunning() async {
    if (Platform.isLinux) {
      return _isLinuxGameRunning();
    }

    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(
          'tasklist',
          ['/FI', 'IMAGENAME eq $_gameExecutable', '/NH'],
        );
      } else {
        return false;
      }

      final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
      return result.exitCode == 0 &&
          output.contains(_gameExecutable.toLowerCase());
    } on ProcessException {
      return false;
    }
  }

  Future<bool> _isLinuxGameRunning() async {
    try {
      await for (final entity in Directory('/proc').list(followLinks: false)) {
        if (entity is! Directory ||
            int.tryParse(entity.uri.pathSegments
                    .where((segment) => segment.isNotEmpty)
                    .last) ==
                null) {
          continue;
        }
        try {
          final commandLine =
              await File('${entity.path}/cmdline').readAsBytes();
          if (String.fromCharCodes(commandLine).contains(_gameExecutable)) {
            return true;
          }
        } on FileSystemException {
          // Processes can exit or reject access while /proc is scanned.
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  Future<ObsProbeResult> _inspectObs() async {
    try {
      return await obsProbe.probe();
    } catch (_) {
      return const ObsProbeResult.blocked(
        detail:
            'OBS WebSocket protocol check could not complete. Open OBS and verify its WebSocket server settings.',
      );
    }
  }

  Future<NativeBackendReadiness> _inspectNativeBackend() async {
    final backend = nativeBackend;
    if (backend == null) {
      return const NativeBackendReadiness(
        available: false,
        detail: 'The native recorder backend is not connected in this build.',
      );
    }
    try {
      return await backend.inspect();
    } catch (error) {
      return NativeBackendReadiness(
        available: false,
        detail: 'The native recorder readiness check failed: $error',
      );
    }
  }

  Future<NativeBackendReadiness> _inspectInput(
    InputMode inputMode,
    NativeBackendReadiness fallback,
  ) async {
    final backend = nativeBackend;
    final InputModeAwareNativeRecorderBackend? aware =
        backend is InputModeAwareNativeRecorderBackend
            ? backend as InputModeAwareNativeRecorderBackend
            : null;
    if (aware == null) {
      return fallback.available
          ? NativeBackendReadiness(
              available: false,
              detail:
                  'This platform backend does not report ${inputMode.label.toLowerCase()} readiness.',
            )
          : fallback;
    }
    try {
      return await aware.inspectForInput(inputMode);
    } catch (error) {
      return NativeBackendReadiness(
        available: false,
        detail: '${inputMode.label} readiness check failed: $error',
      );
    }
  }

  String _replayDetail(
    _ReplayInventory inventory,
    LocalSetupLocations? selectedLocations,
  ) {
    if (inventory.root == null) {
      if (_explicitReplayDirectory(selectedLocations) != null) {
        return 'The selected saved-replay folder was not found. Choose the folder containing your saved replays, then refresh checks.';
      }
      return 'No saved replays were found. Open GGST, save at least one replay, and refresh checks.';
    }
    if (inventory.count == 0) {
      return 'The saved-replay folder is empty. Save at least one replay in GGST, then refresh checks.';
    }
    final noun = inventory.count == 1 ? 'file' : 'files';
    return '${inventory.count} saved replay $noun found${_hasReplayOverride(selectedLocations) ? ' in the selected folder' : ''}.';
  }

  String? _explicitGameDirectory(LocalSetupLocations? selectedLocations) {
    final value = selectedLocations?.gameDirectory;
    return value == null || value.isEmpty ? null : value;
  }

  String? _explicitReplayDirectory(LocalSetupLocations? selectedLocations) {
    final value = selectedLocations?.replayDirectory;
    return value == null || value.isEmpty ? null : value;
  }

  bool _hasGameOverride(LocalSetupLocations? selectedLocations) =>
      _explicitGameDirectory(selectedLocations) != null;

  bool _hasReplayOverride(LocalSetupLocations? selectedLocations) =>
      _explicitReplayDirectory(selectedLocations) != null;

  String _missingGameDetail(LocalSetupLocations? selectedLocations) {
    if (_hasGameOverride(selectedLocations)) {
      return 'The selected game folder was not found. Choose the folder containing Guilty Gear -Strive-, then refresh checks.';
    }
    return 'Guilty Gear -Strive- was not found. Install it through Steam, then refresh checks.';
  }

  List<String> _unique(Iterable<String> values) {
    final unique = <String>[];
    final seen = <String>{};
    for (final value in values) {
      if (value.isEmpty) {
        continue;
      }
      final key = Platform.isWindows ? value.toLowerCase() : value;
      if (seen.add(key)) {
        unique.add(value);
      }
    }
    return unique;
  }

  String _joinParts(String base, List<String> parts) {
    var result = base;
    for (final part in parts) {
      if (result.isEmpty) {
        result = part;
      } else {
        result = '$result${Platform.pathSeparator}$part';
      }
    }
    return result;
  }
}

class _ReplayInventory {
  const _ReplayInventory({
    this.root,
    this.count = 0,
  });

  final String? root;
  final int count;
}
