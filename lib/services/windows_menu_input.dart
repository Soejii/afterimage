import 'dart:ffi';
import 'dart:io';

import '../domain/recorder_contracts.dart';
import 'windows_native_errors.dart';

/// The semantic-to-key mapping used by the replay batch engine.
class WindowsMenuInputMapping {
  WindowsMenuInputMapping({
    Map<ReplayMenuAction, Iterable<String>>? sequences,
  }) : sequences = _validateSequences(sequences ?? defaultSequences);

  static const Map<ReplayMenuAction, List<String>> defaultSequences = {
    ReplayMenuAction.openReplay: <String>['U', 'U'],
    ReplayMenuAction.exitToReplayList: <String>['U'],
    ReplayMenuAction.selectNextReplay: <String>['W'],
  };

  final Map<ReplayMenuAction, List<String>> sequences;

  List<String> sequenceFor(ReplayMenuAction action) {
    final sequence = sequences[action];
    if (sequence == null) {
      throw WindowsNativeException(
        WindowsNativeErrorCode.invalidKey,
        'No keyboard sequence is configured for ${action.name}.',
      );
    }
    return sequence;
  }

  static Map<ReplayMenuAction, List<String>> _validateSequences(
    Map<ReplayMenuAction, Iterable<String>> supplied,
  ) {
    final validated = <ReplayMenuAction, List<String>>{};
    for (final action in ReplayMenuAction.values) {
      final sequence = supplied[action];
      if (sequence == null || sequence.isEmpty) {
        throw WindowsNativeException(
          WindowsNativeErrorCode.invalidKey,
          'A non-empty keyboard sequence is required for ${action.name}.',
        );
      }
      validated[action] = List.unmodifiable(
        sequence.map(validateWindowsKey).toList(growable: false),
      );
    }
    if (supplied.keys
        .any((action) => !ReplayMenuAction.values.contains(action))) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.invalidKey,
        'The keyboard mapping contains an unknown replay action.',
      );
    }
    return Map.unmodifiable(validated);
  }
}

const Map<String, int> _windowsNamedVirtualKeys = {
  'ENTER': 0x0D,
  'BACKSPACE': 0x08,
  'SPACE': 0x20,
  'UP': 0x26,
  'DOWN': 0x28,
  'LEFT': 0x25,
  'RIGHT': 0x27,
};

/// Validates the small safe key vocabulary accepted by the Windows adapter.
String validateWindowsKey(String key) {
  final normalized = key.trim().toUpperCase();
  if (normalized.length == 1 && RegExp(r'^[A-Z0-9]$').hasMatch(normalized)) {
    return normalized;
  }
  if (_windowsNamedVirtualKeys.containsKey(normalized)) {
    return normalized;
  }
  throw WindowsNativeException(
    WindowsNativeErrorCode.invalidKey,
    'Invalid Windows keyboard key "$key". Use one letter, one digit, or a supported named key such as ENTER.',
  );
}

int windowsVirtualKeyFor(String key) {
  final normalized = validateWindowsKey(key);
  final named = _windowsNamedVirtualKeys[normalized];
  if (named != null) {
    return named;
  }
  final code = normalized.codeUnitAt(0);
  if ((code >= 0x41 && code <= 0x5A) || (code >= 0x30 && code <= 0x39)) {
    return code;
  }
  // [validateWindowsKey] makes this unreachable, but retaining a typed error
  // keeps this helper safe if its vocabulary changes later.
  throw WindowsNativeException(
    WindowsNativeErrorCode.invalidKey,
    'Windows has no virtual-key mapping for "$normalized".',
  );
}

abstract interface class WindowsKeyboardNativeApi {
  void open();

  /// Sends one key event. [inputSize] is forwarded as SendInput's `cbSize`.
  void sendKey(
    int virtualKey, {
    required bool keyDown,
    required int inputSize,
  });

  void close();
}

abstract interface class WindowsKeyboardDriver {
  Future<void> open();

  Future<void> press(String key);

  Future<void> close();
}

typedef WindowsKeyboardDriverFactory = WindowsKeyboardDriver Function();
typedef WindowsInputDelay = Future<void> Function(Duration duration);

/// Sends keyboard input through the Win32 SendInput API.
///
/// The API is injected in tests. The default implementation binds user32 and
/// kernel32 only from [open], and therefore constructing this driver on Linux
/// does not load or call a Windows DLL.
class WindowsSendInputDriver implements WindowsKeyboardDriver {
  WindowsSendInputDriver({
    WindowsKeyboardNativeApi? api,
    this.keyHold = const Duration(milliseconds: 80),
  }) : api = api ?? SystemWindowsKeyboardNativeApi() {
    if (keyHold < Duration.zero) {
      throw ArgumentError.value(keyHold, 'keyHold', 'must not be negative');
    }
  }

  final WindowsKeyboardNativeApi api;
  final Duration keyHold;
  bool _opened = false;
  bool _closed = false;

  @override
  Future<void> open() async {
    if (_closed) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.closed,
        'The Windows keyboard input driver is closed.',
      );
    }
    if (_opened) {
      return;
    }
    try {
      api.open();
      _opened = true;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_inputError(error), stackTrace);
    }
  }

  @override
  Future<void> press(String key) async {
    if (_closed) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.closed,
        'The Windows keyboard input driver is closed.',
      );
    }
    if (!_opened) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.inputUnavailable,
        'The Windows keyboard input driver is not open.',
      );
    }
    final normalized = validateWindowsKey(key);
    final virtualKey = windowsVirtualKeyFor(normalized);
    var keyDown = false;
    Object? failure;
    StackTrace? failureStack;
    try {
      api.sendKey(
        virtualKey,
        keyDown: true,
        inputSize: windowsInputSize,
      );
      keyDown = true;
      await Future<void>.delayed(keyHold);
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      if (keyDown) {
        try {
          api.sendKey(
            virtualKey,
            keyDown: false,
            inputSize: windowsInputSize,
          );
        } catch (error, stackTrace) {
          failure ??= error;
          failureStack ??= stackTrace;
        }
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(
        _inputError(failure),
        failureStack ?? StackTrace.current,
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _opened = false;
    try {
      api.close();
    } on Object {
      // Native handles are not retained by SendInput. Closing is best effort.
    }
  }

  WindowsNativeException _inputError(Object error) {
    if (error is WindowsNativeException) {
      return error;
    }
    return WindowsNativeException(
      WindowsNativeErrorCode.inputUnavailable,
      'Windows could not send keyboard input to GGST.',
      cause: error,
    );
  }
}

/// Maps semantic actions to SendInput key presses.
class WindowsKeyboardMenuInput implements MenuInputPort, ClosableMenuInputPort {
  WindowsKeyboardMenuInput({
    WindowsKeyboardDriver? driver,
    WindowsMenuInputMapping? mapping,
    this.keyDelay = const Duration(milliseconds: 800),
    WindowsInputDelay? delay,
  })  : driver = driver ?? WindowsSendInputDriver(),
        mapping = mapping ?? WindowsMenuInputMapping(),
        delay = delay ?? Future<void>.delayed {
    if (keyDelay < Duration.zero) {
      throw ArgumentError.value(
        keyDelay,
        'keyDelay',
        'must not be negative',
      );
    }
  }

  final WindowsKeyboardDriver driver;
  final WindowsMenuInputMapping mapping;
  final Duration keyDelay;
  final WindowsInputDelay delay;
  bool _driverOpened = false;
  bool _closed = false;

  @override
  Future<void> perform(ReplayMenuAction action) async {
    if (_closed) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.closed,
        'The Windows keyboard input port is closed.',
      );
    }
    try {
      if (!_driverOpened) {
        await driver.open();
        _driverOpened = true;
      }
      final sequence = mapping.sequenceFor(action);
      for (var index = 0; index < sequence.length; index++) {
        await driver.press(sequence[index]);
        if (index + 1 < sequence.length) {
          await delay(keyDelay);
        }
      }
    } catch (error, stackTrace) {
      await _closeDriver();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _closeDriver();
  }

  Future<void> _closeDriver() async {
    try {
      await driver.close();
    } catch (_) {
      // Close is best effort. The primary input failure remains visible.
    }
    _driverOpened = false;
  }
}

class SystemWindowsKeyboardNativeApi implements WindowsKeyboardNativeApi {
  SystemWindowsKeyboardNativeApi();

  bool _bound = false;
  late final int Function(int, Pointer<_WindowsInput>, int) _sendInput;
  late final Pointer<Void> Function() _getProcessHeap;
  late final Pointer<Void> Function(Pointer<Void>, int, int) _heapAlloc;
  late final int Function(Pointer<Void>, int, Pointer<Void>) _heapFree;
  late final int Function() _getLastError;

  @override
  void open() {
    _bind();
  }

  @override
  void sendKey(
    int virtualKey, {
    required bool keyDown,
    required int inputSize,
  }) {
    _bind();
    if (virtualKey < 0 || virtualKey > 0xFFFF) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.invalidKey,
        'The requested virtual key is outside the Windows keyboard range.',
      );
    }
    if (inputSize != windowsInputSize) {
      throw WindowsNativeException(
        WindowsNativeErrorCode.inputUnavailable,
        'The Windows keyboard event has an invalid INPUT size ($inputSize).',
      );
    }
    final heap = _getProcessHeap();
    if (heap.address == 0) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'Windows did not provide a process heap for keyboard input.',
      );
    }
    final input = _heapAlloc(heap, 0, sizeOf<_WindowsInput>());
    if (input.address == 0) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.inputUnavailable,
        'Windows could not allocate a keyboard input event.',
      );
    }

    try {
      final value = input.cast<_WindowsInput>().ref;
      value.type = 1; // INPUT_KEYBOARD
      value.data.keyboard
        ..wVk = virtualKey
        ..wScan = 0
        ..flags = keyDown ? 0 : 0x0002 // KEYEVENTF_KEYUP
        ..time = 0
        ..extraInfo = Pointer<Void>.fromAddress(0);
      final sent = _sendInput(1, input.cast<_WindowsInput>(), inputSize);
      if (sent != 1) {
        final error = _getLastError();
        throw WindowsNativeException(
          WindowsNativeErrorCode.inputUnavailable,
          'Windows rejected the ${keyDown ? 'key-down' : 'key-up'} event. Run Afterimage at the same integrity level as GGST (Win32 error $error).',
          systemError: error,
        );
      }
    } finally {
      _heapFree(heap, 0, input);
    }
  }

  @override
  void close() {
    // SendInput does not leave a process or display handle open.
  }

  void _bind() {
    if (_bound) {
      return;
    }
    if (!Platform.isWindows) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'Windows keyboard input is available only in a Windows desktop build.',
      );
    }
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _sendInput = user32.lookupFunction<
          Uint32 Function(Uint32, Pointer<_WindowsInput>, Uint32),
          int Function(int, Pointer<_WindowsInput>, int)>('SendInput');
      _getProcessHeap = kernel32.lookupFunction<Pointer<Void> Function(),
          Pointer<Void> Function()>('GetProcessHeap');
      _heapAlloc = kernel32.lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Uint32, UintPtr),
          Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
      _heapFree = kernel32.lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
          int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');
      _getLastError = kernel32
          .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
      _bound = true;
    } on Object catch (error) {
      throw WindowsNativeException(
        WindowsNativeErrorCode.nativeApiUnavailable,
        'Afterimage could not load the Windows keyboard APIs. Reinstall the Windows desktop runtime and try again.',
        cause: error,
      );
    }
  }
}

final class _WindowsKeyboardInput extends Struct {
  @Uint16()
  external int wVk;

  @Uint16()
  external int wScan;

  @Uint32()
  external int flags;

  @Uint32()
  external int time;

  external Pointer<Void> extraInfo;
}

final class _WindowsMouseInput extends Struct {
  @Int32()
  external int dx;

  @Int32()
  external int dy;

  @Uint32()
  external int mouseData;

  @Uint32()
  external int flags;

  @Uint32()
  external int time;

  external Pointer<Void> extraInfo;
}

final class _WindowsHardwareInput extends Struct {
  @Uint32()
  external int message;

  @Uint16()
  external int paramL;

  @Uint16()
  external int paramH;
}

final class _WindowsInputData extends Union {
  external _WindowsMouseInput mouse;
  external _WindowsKeyboardInput keyboard;
  external _WindowsHardwareInput hardware;
}

final class _WindowsInput extends Struct {
  @Uint32()
  external int type;

  external _WindowsInputData data;
}

/// Size passed as the [SendInput] `cbSize` argument.
///
/// This is exposed for ABI-focused tests without loading a Windows DLL.
int get windowsInputSize => sizeOf<_WindowsInput>();
