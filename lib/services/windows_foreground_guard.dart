import 'dart:ffi';

import 'windows_native_errors.dart';
import 'windows_process_memory.dart';

/// Verifies process identity instead of trusting a window title.
class WindowsForegroundGuard {
  WindowsForegroundGuard(
      {this.checkInterval = const Duration(milliseconds: 250)});
  final Duration checkInterval;
  final Stopwatch _sinceCheck = Stopwatch();
  final SystemWindowsNativeApi _api = SystemWindowsNativeApi();
  late final DynamicLibrary user = DynamicLibrary.open('user32.dll');
  late final DynamicLibrary kernel = DynamicLibrary.open('kernel32.dll');

  void assertGameForeground() {
    if (_sinceCheck.isRunning && _sinceCheck.elapsed < checkInterval) return;
    final gamePid = _api.findProcessId('GGST-Win64-Shipping.exe');
    final foreground =
        user.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'GetForegroundWindow');
    final windowPid = user.lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Uint32>),
        int Function(
            Pointer<Void>, Pointer<Uint32>)>('GetWindowThreadProcessId');
    final getHeap = kernel.lookupFunction<Pointer<Void> Function(),
        Pointer<Void> Function()>('GetProcessHeap');
    final alloc = kernel.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
    final free = kernel.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');
    final heap = getHeap();
    if (heap.address == 0) {
      throw const WindowsNativeException(
          WindowsNativeErrorCode.inputUnavailable,
          'Could not check the active game window. Stop and try again.');
    }
    final memory = alloc(heap, 0x00000008, sizeOf<Uint32>());
    if (memory.address == 0) {
      throw const WindowsNativeException(
          WindowsNativeErrorCode.inputUnavailable,
          'Could not check the active game window. Stop and try again.');
    }
    try {
      final window = foreground();
      final pid = memory.cast<Uint32>();
      if (window.address == 0 ||
          windowPid(window, pid) == 0 ||
          pid.value != gamePid) {
        throw const WindowsNativeException(
            WindowsNativeErrorCode.inputUnavailable,
            'GGST is no longer the active window. Recording stopped to avoid controlling another app. Return to Saved Replays before trying again.');
      }
      _sinceCheck
        ..reset()
        ..start();
    } finally {
      free(heap, 0, memory);
    }
  }
}
