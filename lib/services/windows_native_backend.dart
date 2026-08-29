import 'dart:io';

import '../domain/obs_models.dart';
import '../domain/recorder_contracts.dart';
import '../domain/setup_models.dart';
import 'obs_config_discovery.dart';
import 'obs_websocket_recorder.dart';
import 'output_organizer.dart';
import 'windows_menu_input.dart';
import 'windows_native_errors.dart';
import 'windows_process_memory.dart';
import 'windows_replay_monitor.dart';

typedef WindowsObsRecorderFactory = ObsRecorderPort Function(
  ObsWebSocketConfig config,
);
typedef WindowsOutputOrganizerFactory = OutputOrganizerPort Function();

/// Windows assembly for the platform-neutral batch engine.
///
/// The optional platform override is a test seam. Production callers leave it
/// null, so the backend still refuses to open Windows adapters on another OS.
class WindowsNativeRecorderBackend
    implements NativeRecorderBackend, InputModeAwareNativeRecorderBackend {
  WindowsNativeRecorderBackend({
    this.obsDiscovery = const ObsWebSocketConfigDiscovery(),
    this.obsConfig,
    WindowsMemorySessionFactory? memoryFactory,
    WindowsKeyboardDriverFactory? keyboardDriverFactory,
    WindowsObsRecorderFactory? obsRecorderFactory,
    WindowsOutputOrganizerFactory? outputOrganizerFactory,
    bool? platformIsWindows,
  })  : memoryFactory = memoryFactory ?? _openWindowsMemorySession,
        keyboardDriverFactory =
            keyboardDriverFactory ?? WindowsSendInputDriver.new,
        obsRecorderFactory =
            obsRecorderFactory ?? ((config) => ObsWebSocketRecorder(config)),
        outputOrganizerFactory =
            outputOrganizerFactory ?? (() => const FileOutputOrganizer()),
        _platformIsWindows = platformIsWindows;

  final ObsWebSocketConfigDiscovery obsDiscovery;
  final ObsWebSocketConfig? obsConfig;
  final WindowsMemorySessionFactory memoryFactory;
  final WindowsKeyboardDriverFactory keyboardDriverFactory;
  final WindowsObsRecorderFactory obsRecorderFactory;
  final WindowsOutputOrganizerFactory outputOrganizerFactory;
  final bool? _platformIsWindows;

  bool get _isWindows => _platformIsWindows ?? Platform.isWindows;

  @override
  Future<NativeBackendReadiness> inspect() async {
    if (!_isWindows) {
      return const NativeBackendReadiness(
        available: false,
        detail: 'This backend is available only in a Windows desktop build.',
      );
    }
    final game = await _inspectGame();
    return NativeBackendReadiness(
      available: game.ready,
      detail: game.detail,
    );
  }

  @override
  Future<NativeBackendReadiness> inspectForInput(InputMode inputMode) async {
    final report = await inspectDetailed(inputMode: inputMode);
    return NativeBackendReadiness(
      available: report.ready,
      detail: report.detail,
    );
  }

  Future<WindowsReadinessReport> inspectDetailed({
    InputMode inputMode = InputMode.keyboard,
  }) async {
    if (!_isWindows) {
      return const WindowsReadinessReport(
        checks: <WindowsReadinessCheck>[
          WindowsReadinessCheck(
            code: WindowsNativeErrorCode.nativeApiUnavailable,
            title: 'Windows native backend',
            detail:
                'This backend is available only in a Windows desktop build.',
            ready: false,
          ),
        ],
      );
    }

    final checks = <WindowsReadinessCheck>[];
    checks.add(await _inspectGame());
    if (inputMode == InputMode.virtualController) {
      checks.add(const WindowsReadinessCheck(
        code: WindowsNativeErrorCode.unsupportedController,
        title: 'Virtual controller',
        detail:
            'Virtual controller mode is not available in the Windows adapter yet. Keyboard mode must be selected.',
        ready: false,
      ));
    } else {
      checks.add(const WindowsReadinessCheck(
        code: null,
        title: 'Keyboard input',
        detail: 'Windows SendInput keyboard input is selected.',
        ready: true,
      ));
    }
    return WindowsReadinessReport(checks: List.unmodifiable(checks));
  }

  @override
  Future<ReplayMonitorPort> openReplayMonitor() async {
    _ensureWindows();
    return WindowsReplayMonitor(memoryFactory: memoryFactory);
  }

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) async {
    if (mode == InputMode.virtualController) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.unsupportedController,
        'Virtual controller mode is not available in the Windows adapter yet. Keyboard mode must be selected.',
      );
    }
    _ensureWindows();
    return WindowsKeyboardMenuInput(driver: keyboardDriverFactory());
  }

  @override
  Future<ObsRecorderPort> openObsRecorder() async {
    _ensureWindows();
    final config = obsConfig ?? (await obsDiscovery.discover()).config;
    // Preserve the existing OBS behavior: when no local config is present,
    // try the documented localhost default and let the recorder's protocol
    // check return the actionable error.
    return obsRecorderFactory(config ?? const ObsWebSocketConfig());
  }

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() async {
    _ensureWindows();
    return outputOrganizerFactory();
  }

  Future<WindowsReadinessCheck> _inspectGame() async {
    final monitor = WindowsReplayMonitor(memoryFactory: memoryFactory);
    try {
      await monitor.attach();
      return const WindowsReadinessCheck(
        code: null,
        title: 'GGST memory monitor',
        detail: 'GGST is running and its supported GWorld signature was found.',
        ready: true,
      );
    } catch (error) {
      final typed = _asNativeError(error);
      return WindowsReadinessCheck(
        code: typed.code,
        title: _gameCheckTitle(typed.code),
        detail: typed.message,
        ready: false,
      );
    } finally {
      await monitor.close();
    }
  }

  void _ensureWindows() {
    if (!_isWindows) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'The Windows native backend cannot be opened on this operating system.',
      );
    }
  }

  WindowsNativeException _asNativeError(Object error) {
    if (error is WindowsNativeException) {
      return error;
    }
    return windowsMemoryException(error);
  }

  String _gameCheckTitle(WindowsNativeErrorCode code) {
    return switch (code) {
      WindowsNativeErrorCode.gameAbsent => 'GGST process',
      WindowsNativeErrorCode.processMemoryDenied => 'GGST process memory',
      WindowsNativeErrorCode.architectureMismatch => 'GGST architecture',
      WindowsNativeErrorCode.signatureMismatch => 'GGST game build',
      WindowsNativeErrorCode.gameModuleMissing => 'GGST module mapping',
      _ => 'GGST memory monitor',
    };
  }
}

class WindowsReadinessCheck {
  const WindowsReadinessCheck({
    required this.code,
    required this.title,
    required this.detail,
    required this.ready,
  });

  final WindowsNativeErrorCode? code;
  final String title;
  final String detail;
  final bool ready;
}

class WindowsReadinessReport {
  const WindowsReadinessReport({
    required this.checks,
  });

  final List<WindowsReadinessCheck> checks;

  bool get ready => checks.every((check) => check.ready);

  List<WindowsReadinessCheck> get blockingChecks =>
      checks.where((check) => !check.ready).toList(growable: false);

  String get detail {
    if (ready) {
      return 'Windows native replay monitor and keyboard input are ready.';
    }
    return blockingChecks.map((check) => check.detail).join(' ');
  }
}

WindowsMemorySession _openWindowsMemorySession(String processName) =>
    WindowsProcessMemory.open(processName);
