import 'dart:io';

import '../domain/obs_models.dart';
import '../domain/recorder_contracts.dart';
import '../domain/setup_models.dart';
import 'obs_readiness_probe.dart';

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
    this.replayRootCandidates,
  });

  static const _gameExecutable = 'GGST-Win64-Shipping.exe';
  final ObsReadinessProbe obsProbe;
  final NativeRecorderBackend? nativeBackend;
  final Iterable<String>? replayRootCandidates;

  @override
  Future<SetupReport> inspect() async {
    final gamePath = _findGameInstall();
    final replayInventory = _inspectReplayLibrary();
    final gameRunningFuture = _isGameRunning();
    final obsProbeFuture = _inspectObs();
    final nativeReadinessFuture = _inspectNativeBackend();

    final gameRunning = await gameRunningFuture;
    final obsResult = await obsProbeFuture;
    final nativeReadiness = await nativeReadinessFuture;
    final keyboardReadiness = await _inspectInput(
      InputMode.keyboard,
      nativeReadiness,
    );
    final controllerReadiness = await _inspectInput(
      InputMode.virtualController,
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
          title: 'Supported desktop OS',
          detail: supported
              ? 'Running on $platformName. Linux and Windows are supported targets.'
              : 'Afterimage currently supports Linux and Windows desktop builds.',
          status: supported ? SetupCheckStatus.ready : SetupCheckStatus.blocked,
          required: true,
          value: platformName,
        ),
        const SetupCheck(
          id: SetupCheckId.runtime,
          title: 'Self-contained runtime',
          detail:
              'No Python install is needed. Release builds will include the runtime dependencies they need.',
          status: SetupCheckStatus.ready,
          required: true,
        ),
        SetupCheck(
          id: SetupCheckId.gameInstall,
          title: 'GGST installation',
          detail: gamePath == null
              ? 'No installation was found in common Steam locations. Start by installing Guilty Gear -Strive- through Steam.'
              : 'Found at $gamePath.',
          status: gamePath == null
              ? SetupCheckStatus.blocked
              : SetupCheckStatus.ready,
          required: true,
          value: gamePath,
        ),
        SetupCheck(
          id: SetupCheckId.gameRunning,
          title: 'GGST process',
          detail: gameRunning
              ? '$_gameExecutable is running.'
              : 'Start GGST before recording. Afterimage looks for $_gameExecutable.',
          status:
              gameRunning ? SetupCheckStatus.ready : SetupCheckStatus.blocked,
          required: true,
        ),
        SetupCheck(
          id: SetupCheckId.obsWebSocket,
          title: 'OBS WebSocket protocol',
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
          title: 'Replay library',
          detail: _replayDetail(replayInventory),
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
          title: 'Virtual controller',
          detail: controllerReadiness.detail,
          status: controllerReadiness.available
              ? SetupCheckStatus.ready
              : SetupCheckStatus.notice,
          required: false,
        ),
        SetupCheck(
          id: SetupCheckId.nativeRecorderBackend,
          title: 'Native recorder backend',
          detail: nativeReadiness.detail,
          status: nativeReadiness.available
              ? SetupCheckStatus.ready
              : SetupCheckStatus.blocked,
          required: true,
        ),
      ],
    );
  }

  String? _findGameInstall() {
    final paths = _gameInstallCandidates();
    for (final path in paths) {
      try {
        if (Directory(path).existsSync()) {
          return path;
        }
      } on FileSystemException {
        // A malformed or inaccessible optional candidate should not stop the
        // remaining checks.
      }
    }
    return null;
  }

  List<String> _gameInstallCandidates() {
    final environment = Platform.environment;
    final home = environment['HOME'] ?? environment['USERPROFILE'] ?? '';
    const gameFolder = 'GUILTY GEAR -STRIVE-';

    if (Platform.isWindows) {
      final programFiles = environment['ProgramFiles'] ?? r'C:\Program Files';
      final programFilesX86 =
          environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      return _unique([
        _joinParts(
            programFilesX86, ['Steam', 'steamapps', 'common', gameFolder]),
        _joinParts(programFiles, ['Steam', 'steamapps', 'common', gameFolder]),
      ]);
    }

    return _unique([
      _joinParts(home, ['.steam', 'steam', 'steamapps', 'common', gameFolder]),
      _joinParts(home, [
        '.local',
        'share',
        'Steam',
        'steamapps',
        'common',
        gameFolder,
      ]),
      _joinParts(home, ['Games', 'steamapps', 'common', gameFolder]),
    ]);
  }

  _ReplayInventory _inspectReplayLibrary() {
    final roots = <String>[];

    final suppliedRoots = replayRootCandidates;
    if (suppliedRoots != null) {
      roots.addAll(suppliedRoots);
    } else {
      final environment = Platform.environment;
      final home = environment['HOME'] ?? environment['USERPROFILE'] ?? '';

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
        for (final steamHome in [
          _joinParts(home, ['.steam', 'steam']),
          _joinParts(home, ['.local', 'share', 'Steam']),
          _joinParts(home, ['Games']),
        ]) {
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
        if (!directory.existsSync()) {
          continue;
        }

        var count = 0;
        for (final entity in directory.listSync(recursive: true)) {
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

  String _replayDetail(_ReplayInventory inventory) {
    if (inventory.root == null) {
      return 'No replay save folder was found in common Steam locations. Afterimage looks for REP###.sav files.';
    }
    if (inventory.count == 0) {
      return 'Replay folder found at ${inventory.root}, but no REP###.sav files were found.';
    }
    final noun = inventory.count == 1 ? 'file' : 'files';
    return '${inventory.count} REP###.sav $noun found at ${inventory.root}.';
  }

  List<String> _unique(Iterable<String> values) {
    return values.where((value) => value.isNotEmpty).toSet().toList();
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
