import 'dart:ffi';
import 'dart:io';

import '../domain/recorder_contracts.dart';
import 'windows_native_errors.dart';

abstract final class WindowsControllerButton {
  static const int dpadUp = 0x0001;
  static const int dpadDown = 0x0002;
  static const int south = 0x1000;
}

class WindowsVirtualControllerMapping {
  WindowsVirtualControllerMapping({
    Map<ReplayMenuAction, Iterable<int>>? sequences,
  }) : sequences = _validateSequences(sequences ?? defaultSequences);

  static const Map<ReplayMenuAction, List<int>> defaultSequences = {
    ReplayMenuAction.openReplay: <int>[
      WindowsControllerButton.south,
      WindowsControllerButton.south,
    ],
    ReplayMenuAction.exitToReplayList: <int>[
      WindowsControllerButton.south,
    ],
    ReplayMenuAction.selectNextReplay: <int>[
      WindowsControllerButton.dpadUp,
    ],
  };

  final Map<ReplayMenuAction, List<int>> sequences;

  List<int> sequenceFor(ReplayMenuAction action) => sequences[action]!;

  static Map<ReplayMenuAction, List<int>> _validateSequences(
    Map<ReplayMenuAction, Iterable<int>> supplied,
  ) {
    final validated = <ReplayMenuAction, List<int>>{};
    for (final action in ReplayMenuAction.values) {
      final sequence = supplied[action];
      if (sequence == null || sequence.isEmpty) {
        throw WindowsNativeException(
          WindowsNativeErrorCode.invalidControllerMapping,
          'A non-empty virtual-controller sequence is required for ${action.name}.',
        );
      }
      final buttons = List<int>.unmodifiable(sequence);
      if (buttons.any((button) => button <= 0 || button > 0xFFFF)) {
        throw const WindowsNativeException(
          WindowsNativeErrorCode.invalidControllerMapping,
          'A Windows virtual-controller button is outside the XInput range.',
        );
      }
      validated[action] = buttons;
    }
    return Map<ReplayMenuAction, List<int>>.unmodifiable(validated);
  }
}

abstract interface class WindowsVirtualControllerNativeApi {
  int probe();

  Pointer<Void> create();

  int lastError();

  int update(Pointer<Void> controller, int buttons);

  int destroy(Pointer<Void> controller);
}

class SystemWindowsVirtualControllerNativeApi
    implements WindowsVirtualControllerNativeApi {
  SystemWindowsVirtualControllerNativeApi({DynamicLibrary? library})
      : _providedLibrary = library;

  final DynamicLibrary? _providedLibrary;
  DynamicLibrary? _library;

  late final int Function() _probe =
      _load().lookupFunction<Uint32 Function(), int Function()>(
    'afterimage_controller_probe',
  );
  late final Pointer<Void> Function() _create = _load()
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
    'afterimage_controller_create',
  );
  late final int Function() _lastError =
      _load().lookupFunction<Uint32 Function(), int Function()>(
    'afterimage_controller_last_error',
  );
  late final int Function(Pointer<Void>, int) _update = _load().lookupFunction<
      Uint32 Function(Pointer<Void>, Uint16),
      int Function(Pointer<Void>, int)>('afterimage_controller_update');
  late final int Function(Pointer<Void>) _destroy = _load().lookupFunction<
      Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('afterimage_controller_destroy');

  DynamicLibrary _load() {
    final existing = _library;
    if (existing != null) {
      return existing;
    }
    if (!Platform.isWindows && _providedLibrary == null) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'The Windows virtual-controller bridge is available only in a Windows desktop build.',
      );
    }
    try {
      final library = _providedLibrary ??
          DynamicLibrary.open(
            '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}afterimage_controller.dll',
          );
      _library = library;
      return library;
    } on Object catch (error) {
      throw WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'Afterimage could not load its Windows controller component. Re-extract the complete portable archive.',
        cause: error,
      );
    }
  }

  @override
  int probe() => _probe();

  @override
  Pointer<Void> create() => _create();

  @override
  int lastError() => _lastError();

  @override
  int update(Pointer<Void> controller, int buttons) =>
      _update(controller, buttons);

  @override
  int destroy(Pointer<Void> controller) => _destroy(controller);
}

const int windowsControllerSuccess = 0x20000000;
const int windowsControllerBusNotFound = 0xE0000001;
const int windowsControllerNoFreeSlot = 0xE0000002;

class WindowsVirtualControllerReadiness {
  const WindowsVirtualControllerReadiness({
    required this.ready,
    required this.detail,
    this.code,
  });

  final bool ready;
  final String detail;
  final WindowsNativeErrorCode? code;
}

class WindowsVirtualControllerReadinessProbe {
  WindowsVirtualControllerReadinessProbe({
    WindowsVirtualControllerNativeApi? api,
    bool? platformIsWindows,
  })  : api = api ?? SystemWindowsVirtualControllerNativeApi(),
        _platformIsWindows = platformIsWindows;

  final WindowsVirtualControllerNativeApi api;
  final bool? _platformIsWindows;

  WindowsVirtualControllerReadiness inspect() {
    if (!(_platformIsWindows ?? Platform.isWindows)) {
      return const WindowsVirtualControllerReadiness(
        ready: false,
        detail:
            'The Windows virtual controller is available only in a Windows desktop build.',
        code: WindowsNativeErrorCode.nativeApiUnavailable,
      );
    }
    try {
      final result = api.probe();
      if (result == windowsControllerSuccess) {
        return const WindowsVirtualControllerReadiness(
          ready: true,
          detail:
              'The Windows virtual-controller bus is ready. Xbox, DualShock, and DualSense users can keep their physical controller connected.',
        );
      }
      final error = windowsControllerException(result, operation: 'connect');
      return WindowsVirtualControllerReadiness(
        ready: false,
        detail: error.message,
        code: error.code,
      );
    } on WindowsNativeException catch (error) {
      return WindowsVirtualControllerReadiness(
        ready: false,
        detail: error.message,
        code: error.code,
      );
    } on Object {
      return const WindowsVirtualControllerReadiness(
        ready: false,
        detail: 'Afterimage could not inspect Windows controller support.',
        code: WindowsNativeErrorCode.controllerUnavailable,
      );
    }
  }
}

abstract interface class WindowsVirtualControllerDriver {
  Future<void> open();

  Future<void> setButtons(int buttons);

  Future<void> close();
}

typedef WindowsVirtualControllerDriverFactory = WindowsVirtualControllerDriver
    Function();

class WindowsViGEmControllerDriver implements WindowsVirtualControllerDriver {
  WindowsViGEmControllerDriver({WindowsVirtualControllerNativeApi? api})
      : api = api ?? SystemWindowsVirtualControllerNativeApi();

  final WindowsVirtualControllerNativeApi api;
  Pointer<Void>? _controller;
  bool _closed = false;

  @override
  Future<void> open() async {
    if (_closed) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.closed,
        'The Windows virtual-controller driver is closed.',
      );
    }
    if (_controller != null) {
      return;
    }
    final controller = api.create();
    if (controller == nullptr) {
      throw windowsControllerException(
        api.lastError(),
        operation: 'create a virtual Xbox controller',
      );
    }
    _controller = controller;
  }

  @override
  Future<void> setButtons(int buttons) async {
    final controller = _controller;
    if (controller == null) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.controllerUnavailable,
        'The Windows virtual controller is not open.',
      );
    }
    final result = api.update(controller, buttons);
    if (result != windowsControllerSuccess) {
      throw windowsControllerException(
        result,
        operation: 'send virtual-controller input',
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final controller = _controller;
    _controller = null;
    if (controller == null) {
      return;
    }
    final result = api.destroy(controller);
    if (result != windowsControllerSuccess) {
      throw windowsControllerException(
        result,
        operation: 'remove the virtual controller',
      );
    }
  }
}

class WindowsVirtualControllerMenuInput
    implements MenuInputPort, ClosableMenuInputPort {
  WindowsVirtualControllerMenuInput({
    WindowsVirtualControllerDriver? driver,
    WindowsVirtualControllerMapping? mapping,
    this.buttonHold = const Duration(milliseconds: 80),
    this.buttonDelay = const Duration(milliseconds: 800),
    Future<void> Function(Duration)? delay,
  })  : driver = driver ?? WindowsViGEmControllerDriver(),
        mapping = mapping ?? WindowsVirtualControllerMapping(),
        delay = delay ?? Future<void>.delayed;

  final WindowsVirtualControllerDriver driver;
  final WindowsVirtualControllerMapping mapping;
  final Duration buttonHold;
  final Duration buttonDelay;
  final Future<void> Function(Duration) delay;
  bool _opened = false;
  bool _closed = false;

  @override
  Future<void> perform(ReplayMenuAction action) async {
    if (_closed) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.closed,
        'The Windows virtual-controller input port is closed.',
      );
    }
    try {
      if (!_opened) {
        await driver.open();
        _opened = true;
      }
      final sequence = mapping.sequenceFor(action);
      for (var index = 0; index < sequence.length; index++) {
        await _tap(sequence[index]);
        if (index + 1 < sequence.length) {
          await delay(buttonDelay);
        }
      }
    } catch (error, stackTrace) {
      try {
        await close();
      } on Object {
        // Preserve the input failure instead of replacing it with cleanup.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _tap(int button) async {
    var pressed = false;
    try {
      await driver.setButtons(button);
      pressed = true;
      await delay(buttonHold);
    } finally {
      if (pressed) {
        await driver.setButtons(0);
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await driver.close();
  }
}

WindowsNativeException windowsControllerException(
  int result, {
  required String operation,
}) {
  return switch (result) {
    windowsControllerBusNotFound => const WindowsNativeException(
        WindowsNativeErrorCode.controllerDriverMissing,
        'Windows virtual-controller support is not installed. Install the ViGEmBus driver manually, then restart Afterimage.',
      ),
    windowsControllerNoFreeSlot => const WindowsNativeException(
        WindowsNativeErrorCode.controllerSlotsFull,
        'Windows has no free virtual-controller slot. Close controller remapping tools or disconnect an unused virtual controller.',
      ),
    _ => WindowsNativeException(
        WindowsNativeErrorCode.controllerUnavailable,
        'Afterimage could not $operation (controller error 0x${result.toRadixString(16).padLeft(8, '0')}).',
      ),
  };
}
