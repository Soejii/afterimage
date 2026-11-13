import 'dart:ffi';

import '../domain/recorder_contracts.dart';
import 'windows_foreground_guard.dart';
import 'windows_menu_input.dart';
import 'windows_native_errors.dart';
import 'windows_window_message_input.dart';

/// Focus operations the keyboard route needs from the desktop.
abstract interface class WindowsGameFocusApi {
  /// Whether the foreground window belongs to the GGST process.
  bool isGameForeground();

  /// Asks Windows to bring the GGST main window to the front.
  void requestGameForeground();

  /// Detail from the most recent failed [isGameForeground] check, if any.
  String? get lastFocusFailure;
}

/// Brings GGST to the front before a key press and confirms that it got there.
///
/// GGST ignores keys posted to its window, so keyboard mode types real keys
/// into the desktop input queue. That is only safe while GGST is the active
/// window, so a press that cannot confirm this sends nothing.
class WindowsGameActivator {
  WindowsGameActivator({
    WindowsGameFocusApi? api,
    WindowsInputDelay? delay,
    this.timeout = const Duration(seconds: 3),
    this.pollInterval = const Duration(milliseconds: 100),
    this.settle = const Duration(milliseconds: 400),
  })  : api = api ?? SystemWindowsGameFocusApi(),
        delay = delay ?? Future<void>.delayed;

  final WindowsGameFocusApi api;
  final WindowsInputDelay delay;
  final Duration timeout;
  final Duration pollInterval;

  /// Time GGST gets to process its own activation before the first key.
  final Duration settle;

  Future<void> ensureGameForeground() async {
    if (api.isGameForeground()) return;
    api.requestGameForeground();
    var waited = Duration.zero;
    while (!api.isGameForeground()) {
      if (waited >= timeout) {
        final detail = api.lastFocusFailure;
        throw WindowsNativeException(
          WindowsNativeErrorCode.inputUnavailable,
          'Afterimage could not bring GGST to the front, so no key was sent. '
          'Keyboard mode needs GGST to be the active window each time a '
          'replay opens or closes. Click the GGST window and leave it in '
          'front, or use Controller mode.'
          '${detail == null ? '' : ' $detail'}',
        );
      }
      await delay(pollInterval);
      waited += pollInterval;
    }
    await delay(settle);
  }
}

/// Windows keyboard mode: activate GGST, then press real keys.
///
/// It is deliberately not an [InputSafetyPort]. Focus only matters at the
/// moment of a key press, and the driver checks it there, so the user may use
/// other windows while a replay plays.
class WindowsFocusedKeyboardMenuInput
    implements MenuInputPort, ClosableMenuInputPort {
  WindowsFocusedKeyboardMenuInput({WindowsKeyboardDriver? driver})
      : _menu = WindowsKeyboardMenuInput(
            driver: driver ?? createWindowsFocusedKeyboardDriver());
  final WindowsKeyboardMenuInput _menu;

  @override
  Future<void> perform(ReplayMenuAction action) => _menu.perform(action);

  @override
  Future<void> close() => _menu.close();
}

/// The production keyboard driver: SendInput behind a foreground activation.
WindowsKeyboardDriver createWindowsFocusedKeyboardDriver() {
  final activator = WindowsGameActivator();
  return WindowsSendInputDriver(beforePress: activator.ensureGameForeground);
}

class SystemWindowsGameFocusApi implements WindowsGameFocusApi {
  final WindowsForegroundGuard _guard =
      WindowsForegroundGuard(checkInterval: Duration.zero);
  final SystemWindowsWindowMessageApi _windows =
      SystemWindowsWindowMessageApi();
  late final DynamicLibrary _user = DynamicLibrary.open('user32.dll');
  late final DynamicLibrary _kernel = DynamicLibrary.open('kernel32.dll');
  late final _setForeground = _user.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('SetForegroundWindow');
  late final _getForeground =
      _user.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetForegroundWindow');
  late final _bringToTop = _user.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('BringWindowToTop');
  late final _isIconic = _user.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('IsIconic');
  late final _showWindow = _user.lookupFunction<
      Int32 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)>('ShowWindow');
  late final _windowThread = _user.lookupFunction<
      Uint32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)>('GetWindowThreadProcessId');
  late final _attachThreadInput = _user.lookupFunction<
      Int32 Function(Uint32, Uint32, Int32),
      int Function(int, int, int)>('AttachThreadInput');
  late final _currentThread = _kernel
      .lookupFunction<Uint32 Function(), int Function()>('GetCurrentThreadId');

  String? _lastFocusFailure;

  @override
  String? get lastFocusFailure => _lastFocusFailure;

  @override
  bool isGameForeground() {
    try {
      _guard.assertGameForeground();
      _lastFocusFailure = null;
      return true;
    } on WindowsNativeException catch (error) {
      if (error.code != WindowsNativeErrorCode.inputUnavailable) rethrow;
      final marker = error.message.indexOf('Focus diagnostic');
      _lastFocusFailure =
          marker < 0 ? error.message : error.message.substring(marker);
      return false;
    }
  }

  @override
  void requestGameForeground() {
    final target = _windows.findGameWindow();
    final window = Pointer<Void>.fromAddress(target.handle);
    const swRestore = 9;
    if (_isIconic(window) != 0) _showWindow(window, swRestore);
    if (_setForeground(window) != 0) return;

    // Windows refuses a foreground change from a process that is not itself
    // in front. Sharing the input state of the thread that is in front lifts
    // that refusal without sending anything to that thread's window.
    final foreground = _getForeground();
    if (foreground.address == 0) return;
    final foregroundThread = _windowThread(foreground, nullptr);
    final currentThread = _currentThread();
    if (foregroundThread == 0 || foregroundThread == currentThread) return;
    if (_attachThreadInput(currentThread, foregroundThread, 1) == 0) return;
    try {
      _bringToTop(window);
      _setForeground(window);
    } finally {
      _attachThreadInput(currentThread, foregroundThread, 0);
    }
  }
}
