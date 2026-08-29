import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../domain/recorder_contracts.dart';
import 'linux_native_errors.dart';
import 'linux_process_memory.dart';

const String _linuxDisplayPattern = r'^:[0-9]+(?:\.[0-9]+)?$';

/// The semantic-to-key mapping used by the replay batch engine.
class LinuxMenuInputMapping {
  LinuxMenuInputMapping({
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
      throw LinuxNativeException(
        LinuxNativeErrorCode.invalidKey,
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
        throw LinuxNativeException(
          LinuxNativeErrorCode.invalidKey,
          'A non-empty keyboard sequence is required for ${action.name}.',
        );
      }
      validated[action] = List.unmodifiable(
        sequence.map(validateLinuxKey).toList(growable: false),
      );
    }
    if (supplied.keys
        .any((action) => !ReplayMenuAction.values.contains(action))) {
      throw const LinuxNativeException(
        LinuxNativeErrorCode.invalidKey,
        'The keyboard mapping contains an unknown replay action.',
      );
    }
    return Map.unmodifiable(validated);
  }
}

String validateLinuxKey(String key) {
  final normalized = key.trim().toUpperCase();
  if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(normalized)) {
    throw LinuxNativeException(
      LinuxNativeErrorCode.invalidKey,
      'Invalid Linux keyboard key "$key". Use letters, digits, or underscore.',
    );
  }
  return normalized;
}

String validateGamescopeDisplay(String display) {
  if (!RegExp(_linuxDisplayPattern).hasMatch(display)) {
    throw LinuxNativeException(
      LinuxNativeErrorCode.invalidDisplay,
      'Invalid gamescope X display "$display". Expected a display such as :1 or :2.0.',
    );
  }
  return display;
}

class LinuxGamescopeDisplayDiscovery {
  const LinuxGamescopeDisplayDiscovery({
    this.processName = ggstLinuxExecutable,
    LinuxProcFileSystem? procFileSystem,
  }) : procFileSystem = procFileSystem ?? const SystemLinuxProcFileSystem();

  final String processName;
  final LinuxProcFileSystem procFileSystem;

  String discover() {
    final expected = _linuxProcessBasename(processName);
    var foundGame = false;
    try {
      for (final processId in procFileSystem.processIds()) {
        try {
          final commandLine = _decodeProc(
            procFileSystem.readFile(processId, 'cmdline'),
          );
          var comm = '';
          try {
            comm = _decodeProc(
              procFileSystem.readFile(processId, 'comm'),
            ).trim();
          } on FileSystemException {
            // cmdline is sufficient when comm is hidden by a procfs policy.
          }
          if (!_containsExecutable(commandLine, expected) && comm != expected) {
            continue;
          }
          foundGame = true;
          final environment = _parseEnvironment(
            procFileSystem.readFile(processId, 'environ'),
          );
          final display = environment['DISPLAY'];
          if (display == null || display.isEmpty) {
            continue;
          }
          try {
            return validateGamescopeDisplay(display);
          } on LinuxNativeException {
            rethrow;
          }
        } on FileSystemException {
          // A process can disappear while procfs is enumerated.
        } on OSError {
          // A restricted or disappearing proc entry should not abort the
          // search for another matching process.
        }
      }
    } on FileSystemException catch (error) {
      throw LinuxNativeException(
        LinuxNativeErrorCode.gamescopeDisplayMissing,
        'The Linux process list could not be read while looking for GGST.',
        cause: error,
      );
    }
    if (foundGame) {
      throw const LinuxNativeException(
        LinuxNativeErrorCode.gamescopeDisplayMissing,
        'GGST is running, but its gamescope DISPLAY was not found. Launch GGST through gamescope and try again.',
      );
    }
    throw const LinuxNativeException(
      LinuxNativeErrorCode.gameAbsent,
      'GGST is not running, so its gamescope DISPLAY cannot be discovered.',
    );
  }

  static Map<String, String> parseEnvironment(List<int> bytes) =>
      _parseEnvironment(bytes);

  static bool _containsExecutable(String commandLine, String expected) {
    return commandLine.split('\u0000').any((argument) =>
        _linuxProcessBasename(argument) == expected ||
        argument.contains(expected));
  }
}

String _decodeProc(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

Map<String, String> _parseEnvironment(List<int> bytes) {
  final values = <String, String>{};
  for (final item in _decodeProc(bytes).split('\u0000')) {
    final equals = item.indexOf('=');
    if (equals <= 0) {
      continue;
    }
    values[item.substring(0, equals)] = item.substring(equals + 1);
  }
  return values;
}

String _linuxProcessBasename(String value) {
  final normalized = value.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

abstract interface class LinuxKeyboardDriver {
  Future<void> open(String display);

  Future<void> press(String key);

  Future<void> close();
}

typedef LinuxInputDelay = Future<void> Function(Duration duration);

typedef LinuxKeyboardDriverFactory = LinuxKeyboardDriver Function();

/// Sends XTest events to gamescope's nested X server, without changing the
/// desktop's active window or focus.
class LinuxXTestKeyboardDriver implements LinuxKeyboardDriver {
  DynamicLibrary? _x11;
  DynamicLibrary? _xtst;
  Pointer<Void>? _display;
  bool _closed = false;
  bool _functionsBound = false;

  late final Pointer<Void> Function(Pointer<Int8>) _xOpenDisplay;
  int Function(Pointer<Void>)? _xCloseDisplay;
  late final int Function(Pointer<Int8>) _xStringToKeysym;
  late final int Function(Pointer<Void>, int) _xKeysymToKeycode;
  late final int Function(Pointer<Void>) _xFlush;
  late final int Function(Pointer<Void>, int, int, int) _xTestFakeKeyEvent;
  late final Pointer<Void> Function(int) _malloc;
  late final void Function(Pointer<Void>) _free;

  static const Map<String, String> keySymNames = {
    'ENTER': 'Return',
    'BACKSPACE': 'BackSpace',
    'SPACE': 'space',
    'UP': 'Up',
    'DOWN': 'Down',
    'LEFT': 'Left',
    'RIGHT': 'Right',
  };

  @override
  Future<void> open(String display) async {
    if (_display != null) {
      return;
    }
    validateGamescopeDisplay(display);
    _closed = false;
    if (_x11 == null) {
      try {
        _x11 = _openLibrary(<String>['libX11.so.6', 'libX11.so']);
      } on Object catch (error) {
        throw LinuxNativeException(
          LinuxNativeErrorCode.missingX11,
          'libX11 is missing. Install the Linux X11 runtime libraries.',
          cause: error,
        );
      }
    }
    if (_xtst == null) {
      try {
        _xtst = _openLibrary(<String>['libXtst.so.6', 'libXtst.so']);
      } on Object catch (error) {
        throw LinuxNativeException(
          LinuxNativeErrorCode.missingXTest,
          'libXtst is missing. Install the Linux XTest runtime library.',
          cause: error,
        );
      }
    }

    try {
      if (!_functionsBound) {
        _bindFunctions();
        _functionsBound = true;
      }
      final displayPointer = _withCString(
        display,
        (pointer) => _xOpenDisplay(pointer),
      );
      if (displayPointer.address == 0) {
        throw LinuxNativeException(
          LinuxNativeErrorCode.displayUnavailable,
          'Could not open gamescope display $display.',
        );
      }
      _display = displayPointer;
    } catch (error, stackTrace) {
      await close();
      if (error is LinuxNativeException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      Error.throwWithStackTrace(
        LinuxNativeException(
          LinuxNativeErrorCode.displayUnavailable,
          'Could not open gamescope display $display.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> press(String key) async {
    final display = _display;
    if (_closed || display == null) {
      throw const LinuxNativeException(
        LinuxNativeErrorCode.displayUnavailable,
        'The gamescope keyboard display is not open.',
      );
    }
    final normalized = validateLinuxKey(key);
    final keySymName = keySymNames[normalized] ?? normalized.toLowerCase();
    final keyCode = _withCString(
      keySymName,
      (pointer) => _xStringToKeysym(pointer),
    );
    if (keyCode == 0) {
      throw LinuxNativeException(
        LinuxNativeErrorCode.invalidKey,
        'gamescope does not know the X11 keysym for "$normalized".',
      );
    }
    final code = _xKeysymToKeycode(display, keyCode);
    if (code == 0) {
      throw LinuxNativeException(
        LinuxNativeErrorCode.invalidKey,
        'gamescope has no keycode for "$normalized".',
      );
    }

    var keyDown = false;
    Object? failure;
    StackTrace? failureStack;
    try {
      if (_xTestFakeKeyEvent(display, code, 1, 0) == 0) {
        throw LinuxNativeException(
          LinuxNativeErrorCode.displayUnavailable,
          'gamescope rejected the "$normalized" key-down event.',
        );
      }
      keyDown = true;
      _xFlush(display);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      if (keyDown) {
        try {
          if (_xTestFakeKeyEvent(display, code, 0, 0) == 0) {
            throw LinuxNativeException(
              LinuxNativeErrorCode.displayUnavailable,
              'gamescope rejected the "$normalized" key-up event.',
            );
          }
          _xFlush(display);
        } catch (error, stackTrace) {
          failure ??= error;
          failureStack ??= stackTrace;
        }
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(
        failure is LinuxNativeException
            ? failure
            : LinuxNativeException(
                LinuxNativeErrorCode.displayUnavailable,
                'The "$normalized" key event failed.',
                cause: failure,
              ),
        failureStack ?? StackTrace.current,
      );
    }
  }

  @override
  Future<void> close() async {
    final display = _display;
    _display = null;
    _closed = true;
    final closeDisplay = _xCloseDisplay;
    if (display != null && closeDisplay != null) {
      try {
        closeDisplay(display);
      } on Object {
        // The X server may disappear while the app is closing. Resources are
        // still considered closed locally.
      }
    }
  }

  void _bindFunctions() {
    final x11 = _x11;
    final xtst = _xtst;
    if (x11 == null || xtst == null) {
      throw const LinuxNativeException(
        LinuxNativeErrorCode.displayUnavailable,
        'The X11 keyboard libraries are not loaded.',
      );
    }
    _xOpenDisplay = x11.lookupFunction<Pointer<Void> Function(Pointer<Int8>),
        Pointer<Void> Function(Pointer<Int8>)>('XOpenDisplay');
    _xCloseDisplay = x11.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('XCloseDisplay');
    _xStringToKeysym = x11.lookupFunction<Uint64 Function(Pointer<Int8>),
        int Function(Pointer<Int8>)>('XStringToKeysym');
    _xKeysymToKeycode = x11.lookupFunction<
        Uint8 Function(Pointer<Void>, Uint64),
        int Function(Pointer<Void>, int)>('XKeysymToKeycode');
    _xFlush = x11.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('XFlush');
    _xTestFakeKeyEvent = xtst.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Int32, Uint64),
        int Function(Pointer<Void>, int, int, int)>('XTestFakeKeyEvent');

    final libc = DynamicLibrary.process();
    _malloc = libc.lookupFunction<Pointer<Void> Function(UintPtr),
        Pointer<Void> Function(int)>('malloc');
    _free = libc.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('free');
  }

  DynamicLibrary _openLibrary(List<String> names) {
    Object? lastError;
    for (final name in names) {
      try {
        return DynamicLibrary.open(name);
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('No library name was supplied.');
  }

  T _withCString<T>(String value, T Function(Pointer<Int8>) callback) {
    final bytes = utf8.encode(value);
    final pointer = _malloc(bytes.length + 1).cast<Uint8>();
    if (pointer.address == 0) {
      throw const LinuxNativeException(
        LinuxNativeErrorCode.displayUnavailable,
        'Could not allocate a temporary X11 string.',
      );
    }
    try {
      final target = pointer.asTypedList(bytes.length + 1);
      target.setAll(0, bytes);
      target[bytes.length] = 0;
      return callback(pointer.cast<Int8>());
    } finally {
      _free(pointer.cast<Void>());
    }
  }
}

/// Maps semantic actions to XTest key presses. A failed sequence closes the
/// display so no stale native resource survives into a later batch.
class LinuxKeyboardMenuInput implements MenuInputPort, ClosableMenuInputPort {
  LinuxKeyboardMenuInput({
    LinuxGamescopeDisplayDiscovery? discovery,
    LinuxKeyboardDriver? driver,
    LinuxMenuInputMapping? mapping,
    this.keyDelay = const Duration(milliseconds: 800),
    LinuxInputDelay? delay,
  })  : discovery = discovery ?? const LinuxGamescopeDisplayDiscovery(),
        driver = driver ?? LinuxXTestKeyboardDriver(),
        mapping = mapping ?? LinuxMenuInputMapping(),
        delay = delay ?? Future<void>.delayed {
    if (keyDelay < Duration.zero) {
      throw ArgumentError.value(
        keyDelay,
        'keyDelay',
        'must not be negative',
      );
    }
  }

  final LinuxGamescopeDisplayDiscovery discovery;
  final LinuxKeyboardDriver driver;
  final LinuxMenuInputMapping mapping;
  final Duration keyDelay;
  final LinuxInputDelay delay;

  String? _display;
  bool _driverOpened = false;
  bool _closed = false;

  @override
  Future<void> perform(ReplayMenuAction action) async {
    if (_closed) {
      throw const LinuxNativeException(
        LinuxNativeErrorCode.closed,
        'The Linux keyboard input port is closed.',
      );
    }
    final display = _display ??= discovery.discover();
    try {
      if (!_driverOpened) {
        await driver.open(display);
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
    _display = null;
    _driverOpened = false;
  }
}
