import 'dart:ffi';
import 'dart:io';

import '../domain/obs_models.dart';
import '../domain/recorder_contracts.dart';
import '../domain/setup_models.dart';
import 'linux_menu_input.dart';
import 'linux_native_errors.dart';
import 'linux_process_memory.dart';
import 'linux_replay_monitor.dart';
import 'linux_evdev_controller.dart';
import 'obs_config_discovery.dart';
import 'obs_websocket_recorder.dart';
import 'output_organizer.dart';

typedef LinuxObsRecorderFactory = ObsRecorderPort Function(
  ObsWebSocketConfig config,
);
typedef LinuxOutputOrganizerFactory = OutputOrganizerPort Function();

abstract interface class LinuxNativeLibraryProbe {
  bool canOpen(Iterable<String> names);
}

class SystemLinuxNativeLibraryProbe implements LinuxNativeLibraryProbe {
  const SystemLinuxNativeLibraryProbe();

  @override
  bool canOpen(Iterable<String> names) {
    for (final name in names) {
      try {
        final library = DynamicLibrary.open(name);
        if (library.handle.address != 0) {
          return true;
        }
      } on Object {
        // Try the next soname.
      }
    }
    return false;
  }
}

/// Linux assembly for the platform-neutral batch engine.
///
/// The backend deliberately does not alter the existing setup service. The
/// desktop Start action remains locked until the app wires a complete
/// platform backend into its setup report.
class LinuxNativeRecorderBackend
    implements NativeRecorderBackend, InputModeAwareNativeRecorderBackend {
  LinuxNativeRecorderBackend({
    this.obsDiscovery = const ObsWebSocketConfigDiscovery(),
    this.obsConfig,
    this.obsConfigProvider,
    LinuxMemorySessionFactory? memoryFactory,
    LinuxGamescopeDisplayDiscovery? displayDiscovery,
    LinuxKeyboardDriverFactory? keyboardDriverFactory,
    LinuxObsRecorderFactory? obsRecorderFactory,
    LinuxOutputOrganizerFactory? outputOrganizerFactory,
    LinuxNativeLibraryProbe? libraryProbe,
    LinuxEvdevControllerDiscovery? controllerDiscovery,
    LinuxEvdevReadinessProbe? controllerProbe,
    LinuxEvdevDeviceFactory? controllerFactory,
  })  : memoryFactory = memoryFactory ?? _openLinuxMemorySession,
        displayDiscovery =
            displayDiscovery ?? const LinuxGamescopeDisplayDiscovery(),
        keyboardDriverFactory =
            keyboardDriverFactory ?? LinuxXTestKeyboardDriver.new,
        obsRecorderFactory =
            obsRecorderFactory ?? ((config) => ObsWebSocketRecorder(config)),
        outputOrganizerFactory =
            outputOrganizerFactory ?? (() => const FileOutputOrganizer()),
        libraryProbe = libraryProbe ?? const SystemLinuxNativeLibraryProbe(),
        controllerDiscovery =
            controllerDiscovery ?? const LinuxEvdevControllerDiscovery(),
        controllerFactory =
            controllerFactory ?? const LinuxEvdevNativeDeviceFactory(),
        controllerProbe = controllerProbe ??
            LinuxEvdevReadinessProbe(
              discovery:
                  controllerDiscovery ?? const LinuxEvdevControllerDiscovery(),
              factory:
                  controllerFactory ?? const LinuxEvdevNativeDeviceFactory(),
            );

  final ObsWebSocketConfigDiscovery obsDiscovery;
  final ObsWebSocketConfig? obsConfig;
  final Future<ObsWebSocketConfig> Function()? obsConfigProvider;
  final LinuxMemorySessionFactory memoryFactory;
  final LinuxGamescopeDisplayDiscovery displayDiscovery;
  final LinuxKeyboardDriverFactory keyboardDriverFactory;
  final LinuxObsRecorderFactory obsRecorderFactory;
  final LinuxOutputOrganizerFactory outputOrganizerFactory;
  final LinuxNativeLibraryProbe libraryProbe;
  final LinuxEvdevControllerDiscovery controllerDiscovery;
  final LinuxEvdevReadinessProbe controllerProbe;
  final LinuxEvdevDeviceFactory controllerFactory;

  @override
  Future<NativeBackendReadiness> inspect() async {
    if (!Platform.isLinux) {
      return const NativeBackendReadiness(
        available: false,
        detail: 'This backend is available only in a Linux desktop build.',
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
    if (!Platform.isLinux) {
      return const NativeBackendReadiness(
        available: false,
        detail: 'This backend is available only in a Linux desktop build.',
      );
    }

    final checks = switch (inputMode) {
      InputMode.keyboard => <LinuxReadinessCheck>[
          _inspectX11(),
          _inspectXTest(),
          _inspectDisplay(),
          const LinuxReadinessCheck(
            code: null,
            title: 'Keyboard input',
            detail: 'Linux XTest keyboard input is selected.',
            ready: true,
          ),
        ],
      InputMode.controller => <LinuxReadinessCheck>[
          () {
            final controller = controllerProbe.inspect();
            return LinuxReadinessCheck(
              code: controller.ready
                  ? null
                  : LinuxNativeErrorCode.unsupportedController,
              title: 'Controller',
              detail: controller.detail,
              ready: controller.ready,
            );
          }(),
        ],
    };
    final report = LinuxReadinessReport(checks: List.unmodifiable(checks));
    return NativeBackendReadiness(
      available: report.ready,
      detail: report.ready
          ? '${inputMode.label} is ready.'
          : report.blockingChecks.map((check) => check.detail).join(' '),
    );
  }

  Future<LinuxReadinessReport> inspectDetailed({
    InputMode inputMode = InputMode.keyboard,
  }) async {
    if (!Platform.isLinux) {
      return const LinuxReadinessReport(
        checks: <LinuxReadinessCheck>[
          LinuxReadinessCheck(
            code: LinuxNativeErrorCode.memoryReadFailed,
            title: 'Linux native backend',
            detail: 'This backend is available only in a Linux desktop build.',
            ready: false,
          ),
        ],
      );
    }

    final checks = <LinuxReadinessCheck>[];
    checks.add(await _inspectGame());
    if (inputMode == InputMode.controller) {
      final controller = controllerProbe.inspect();
      checks.add(LinuxReadinessCheck(
        code: controller.ready
            ? null
            : LinuxNativeErrorCode.unsupportedController,
        title: 'Controller',
        detail: controller.detail,
        ready: controller.ready,
      ));
    } else {
      checks.add(_inspectX11());
      checks.add(_inspectXTest());
      checks.add(_inspectDisplay());
      checks.add(const LinuxReadinessCheck(
        code: null,
        title: 'Keyboard input',
        detail: 'Linux XTest keyboard input is selected.',
        ready: true,
      ));
    }
    return LinuxReadinessReport(checks: List.unmodifiable(checks));
  }

  @override
  Future<ReplayMonitorPort> openReplayMonitor() async {
    _ensureLinux();
    return LinuxReplayMonitor(memoryFactory: memoryFactory);
  }

  @override
  Future<MenuInputPort> openMenuInput(InputMode mode) async {
    _ensureLinux();
    if (mode == InputMode.controller) {
      return LinuxEvdevMenuInput(
        discovery: controllerDiscovery,
        factory: controllerFactory,
      );
    }
    return LinuxKeyboardMenuInput(
      discovery: displayDiscovery,
      driver: keyboardDriverFactory(),
    );
  }

  @override
  Future<ObsRecorderPort> openObsRecorder() async {
    _ensureLinux();
    final config = obsConfigProvider != null
        ? await obsConfigProvider!()
        : obsConfig ?? (await obsDiscovery.discover()).config;
    // Preserve the existing OBS behavior: when no local config is present,
    // try the documented localhost default and let the recorder's protocol
    // check return the actionable error.
    return obsRecorderFactory(config ?? const ObsWebSocketConfig());
  }

  @override
  Future<OutputOrganizerPort> openOutputOrganizer() async {
    _ensureLinux();
    return outputOrganizerFactory();
  }

  Future<LinuxReadinessCheck> _inspectGame() async {
    final monitor = LinuxReplayMonitor(memoryFactory: memoryFactory);
    try {
      await monitor.attach();
      return const LinuxReadinessCheck(
        code: null,
        title: 'GGST memory monitor',
        detail: 'GGST is running and its supported GWorld signature was found.',
        ready: true,
      );
    } catch (error) {
      final typed = _asNativeError(error);
      return LinuxReadinessCheck(
        code: typed.code,
        title: _gameCheckTitle(typed.code),
        detail: typed.message,
        ready: false,
      );
    } finally {
      await monitor.close();
    }
  }

  LinuxReadinessCheck _inspectDisplay() {
    try {
      final display = displayDiscovery.discover();
      return LinuxReadinessCheck(
        code: null,
        title: 'Gamescope DISPLAY',
        detail: 'GGST gamescope display $display was found.',
        ready: true,
      );
    } catch (error) {
      final typed = _asNativeError(error);
      return LinuxReadinessCheck(
        code: typed.code,
        title: 'Gamescope DISPLAY',
        detail: typed.message,
        ready: false,
      );
    }
  }

  LinuxReadinessCheck _inspectX11() => _inspectLibrary(
        names: <String>['libX11.so.6', 'libX11.so'],
        code: LinuxNativeErrorCode.missingX11,
        title: 'libX11',
        detail: 'libX11 is available for targeted gamescope input.',
        missingDetail:
            'libX11 is missing. Install the Linux X11 runtime libraries.',
      );

  LinuxReadinessCheck _inspectXTest() => _inspectLibrary(
        names: <String>['libXtst.so.6', 'libXtst.so'],
        code: LinuxNativeErrorCode.missingXTest,
        title: 'libXtst / XTest',
        detail: 'libXtst is available for targeted gamescope input.',
        missingDetail:
            'libXtst is missing. Install the Linux XTest runtime library.',
      );

  LinuxReadinessCheck _inspectLibrary({
    required List<String> names,
    required LinuxNativeErrorCode code,
    required String title,
    required String detail,
    required String missingDetail,
  }) {
    if (libraryProbe.canOpen(names)) {
      return LinuxReadinessCheck(
        code: null,
        title: title,
        detail: detail,
        ready: true,
      );
    }
    return LinuxReadinessCheck(
      code: code,
      title: title,
      detail: missingDetail,
      ready: false,
    );
  }

  void _ensureLinux() {
    if (!Platform.isLinux) {
      throw const LinuxNativeException(
        LinuxNativeErrorCode.memoryReadFailed,
        'The Linux native backend cannot be opened on this operating system.',
      );
    }
  }

  LinuxNativeException _asNativeError(Object error) {
    if (error is LinuxNativeException) {
      return error;
    }
    return linuxMemoryException(error);
  }

  String _gameCheckTitle(LinuxNativeErrorCode code) {
    return switch (code) {
      LinuxNativeErrorCode.gameAbsent => 'GGST process',
      LinuxNativeErrorCode.processMemoryDenied => 'GGST process memory',
      LinuxNativeErrorCode.signatureMismatch => 'GGST game build',
      LinuxNativeErrorCode.gameModuleMissing => 'GGST module mapping',
      _ => 'GGST memory monitor',
    };
  }
}

LinuxMemorySession _openLinuxMemorySession(String processName) =>
    LinuxProcessMemory.open(processName);
