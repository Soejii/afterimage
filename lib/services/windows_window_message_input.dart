import 'dart:ffi';
import 'dart:io';

import '../domain/recorder_contracts.dart';
import 'windows_menu_input.dart';
import 'windows_native_errors.dart';
import 'windows_process_memory.dart';

class WindowsGameWindow {
  const WindowsGameWindow(this.handle, this.processId);
  final int handle;
  final int processId;
}

abstract interface class WindowsWindowMessageApi {
  WindowsGameWindow findGameWindow();
  void postKey(WindowsGameWindow target, int virtualKey, {required bool down});
}

/// Targets a specific game window. It never injects into the desktop input queue.
class WindowsWindowMessageDriver implements WindowsKeyboardDriver {
  WindowsWindowMessageDriver({
    WindowsWindowMessageApi? api,
    this.keyHold = const Duration(milliseconds: 80),
    WindowsInputDelay? delay,
  })  : api = api ?? SystemWindowsWindowMessageApi(),
        delay = delay ?? Future<void>.delayed {
    if (keyHold < Duration.zero) {
      throw ArgumentError.value(keyHold, 'keyHold', 'must not be negative');
    }
  }

  final WindowsWindowMessageApi api;
  final Duration keyHold;
  final WindowsInputDelay delay;
  WindowsGameWindow? _target;
  bool _closed = false;

  @override
  Future<void> open() async {
    if (_closed) throw _unavailable('The game-window input driver is closed.');
    _target ??= api.findGameWindow();
  }

  @override
  Future<void> press(String key) async {
    final target = _target;
    if (_closed || target == null) {
      throw _unavailable('The game-window input driver is not open.');
    }
    final virtualKey = windowsVirtualKeyFor(key);
    api.postKey(target, virtualKey, down: true);
    try {
      await delay(keyHold);
    } finally {
      // Release the same window, even if the desktop focus changes during a tap.
      api.postKey(target, virtualKey, down: false);
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _target = null;
  }
}

/// Reuses the menu mapping and timings without the SendInput foreground policy.
/// Ownership checks happen in the native driver before each message instead.
class WindowsWindowMessageMenuInput
    implements MenuInputPort, ClosableMenuInputPort {
  WindowsWindowMessageMenuInput({WindowsKeyboardDriver? driver})
      : _menu = WindowsKeyboardMenuInput(
            driver: driver ?? WindowsWindowMessageDriver());
  final WindowsKeyboardMenuInput _menu;

  @override
  Future<void> perform(ReplayMenuAction action) => _menu.perform(action);

  @override
  Future<void> close() => _menu.close();
}

WindowsNativeException _unavailable(String message) =>
    WindowsNativeException(WindowsNativeErrorCode.inputUnavailable, message);

typedef _WindowCallback = Int32 Function(Pointer<Void>, IntPtr);

class SystemWindowsWindowMessageApi implements WindowsWindowMessageApi {
  late final DynamicLibrary _user = DynamicLibrary.open('user32.dll');
  late final DynamicLibrary _kernel = DynamicLibrary.open('kernel32.dll');
  late final _processId = _user.lookupFunction<
      Uint32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)>('GetWindowThreadProcessId');
  late final _isWindow = _user.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('IsWindow');
  late final _visible = _user.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('IsWindowVisible');
  late final _owner = _user.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Uint32),
      Pointer<Void> Function(Pointer<Void>, int)>('GetWindow');
  late final _lastError =
      _kernel.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  T _withPidBuffer<T>(T Function(Pointer<Uint32>) action) {
    final heap = _kernel.lookupFunction<Pointer<Void> Function(),
        Pointer<Void> Function()>('GetProcessHeap')();
    if (heap.address == 0) {
      throw _unavailable('Windows did not provide a process heap.');
    }
    final alloc = _kernel.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
    final free = _kernel.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');
    final buffer = alloc(heap, 8, sizeOf<Uint32>());
    if (buffer.address == 0) {
      throw _unavailable('Windows could not allocate a process lookup buffer.');
    }
    try {
      return action(buffer.cast<Uint32>());
    } finally {
      free(heap, 0, buffer);
    }
  }

  @override
  WindowsGameWindow findGameWindow() {
    if (!Platform.isWindows) {
      throw _unavailable('Game-window keyboard input requires Windows.');
    }
    final pid =
        SystemWindowsNativeApi().findProcessId('GGST-Win64-Shipping.exe');
    return _withPidBuffer((buffer) {
      final matches = <int>[];
      Object? callbackFailure;
      final callback = NativeCallable<_WindowCallback>.isolateLocal(
          (Pointer<Void> window, int _) {
        try {
          buffer.value = 0;
          if (_processId(window, buffer) != 0 &&
              buffer.value == pid &&
              _visible(window) != 0 &&
              _owner(window, 4).address == 0) {
            matches.add(window.address);
          }
          return 1;
        } catch (error) {
          callbackFailure = error;
          return 0;
        }
      }, exceptionalReturn: 0);
      try {
        final enumerate = _user.lookupFunction<
            Int32 Function(Pointer<NativeFunction<_WindowCallback>>, IntPtr),
            int Function(
                Pointer<NativeFunction<_WindowCallback>>, int)>('EnumWindows');
        if (enumerate(callback.nativeFunction, 0) == 0) {
          throw _unavailable(
              'Could not enumerate the game window (Windows error ${_lastError()}).');
        }
        if (callbackFailure != null) throw callbackFailure!;
      } finally {
        callback.close();
      }
      if (matches.length != 1) {
        throw _unavailable(
            'Expected one visible GGST main window, found ${matches.length}. '
            'Close extra game windows and return to Saved Replays.');
      }
      return WindowsGameWindow(matches.single, pid);
    });
  }

  @override
  void postKey(WindowsGameWindow target, int virtualKey, {required bool down}) {
    // Refuse NULL and HWND_BROADCAST, which have system-wide meanings.
    if (target.handle <= 0 ||
        target.handle == 0xffff ||
        target.processId <= 0) {
      throw _unavailable('Refusing an invalid game-window target.');
    }
    final window = Pointer<Void>.fromAddress(target.handle);
    _withPidBuffer((buffer) {
      if (_isWindow(window) == 0 ||
          _processId(window, buffer) == 0 ||
          buffer.value != target.processId) {
        throw _unavailable(
            'The original GGST window closed or changed owner. No input was sent.');
      }
      final mapKey = _user.lookupFunction<Uint32 Function(Uint32, Uint32),
          int Function(int, int)>('MapVirtualKeyW');
      final scanCode = mapKey(virtualKey, 0);
      if (scanCode == 0) {
        throw _unavailable('Windows could not map the replay menu key.');
      }
      final extended = virtualKey >= 0x25 && virtualKey <= 0x28;
      final flags = 1 |
          ((scanCode & 0xff) << 16) |
          (extended ? 1 << 24 : 0) |
          (down ? 0 : 0xc0000000);
      final post = _user.lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, UintPtr, IntPtr),
          int Function(Pointer<Void>, int, int, int)>('PostMessageW');
      if (post(window, down ? 0x100 : 0x101, virtualKey, flags) == 0) {
        throw _unavailable(
            'Windows rejected the GGST menu message (error ${_lastError()}). '
            'Run Afterimage and GGST at the same permission level.');
      }
    });
  }
}
