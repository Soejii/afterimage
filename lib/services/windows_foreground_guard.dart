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
      final threadId = window.address == 0 ? 0 : windowPid(window, pid);
      final lookupError = window.address != 0 && threadId == 0
          ? kernel.lookupFunction<Uint32 Function(), int Function()>(
              'GetLastError')()
          : null;
      if (window.address == 0 || threadId == 0 || pid.value != gamePid) {
        final reason = window.address == 0
            ? 'no foreground window'
            : threadId == 0
                ? 'foreground process lookup failed (Windows error $lookupError)'
                : 'foreground process differs from GGST';
        final details = _describeWindow(window, pid.value);
        throw WindowsNativeException(
            WindowsNativeErrorCode.inputUnavailable,
            'GGST is no longer the active window. Recording stopped to avoid controlling another app. Return to Saved Replays before trying again. '
            'Focus diagnostic at ${DateTime.now().toUtc().toIso8601String()}: '
            '$reason; GGST PID=$gamePid; foreground PID=${pid.value}; '
            'HWND=0x${window.address.toRadixString(16)}; $details');
      }
      _sinceCheck
        ..reset()
        ..start();
    } finally {
      free(heap, 0, memory);
    }
  }

  /// Failure-only, read-only metadata. Failure to collect it never permits input.
  String _describeWindow(Pointer<Void> window, int pid) {
    final getHeap = kernel.lookupFunction<Pointer<Void> Function(),
        Pointer<Void> Function()>('GetProcessHeap');
    final alloc = kernel.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
    final free = kernel.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');
    final heap = getHeap();
    if (heap.address == 0) return 'window metadata unavailable';
    final buffer = alloc(heap, 0x00000008, 32768 * sizeOf<Uint16>());
    final length = alloc(heap, 0x00000008, sizeOf<Uint32>());
    try {
      if (buffer.address == 0 || length.address == 0) {
        return 'window metadata allocation failed';
      }
      final text = buffer.cast<Uint16>();
      final getTitle = user.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint16>, Int32),
          int Function(Pointer<Void>, Pointer<Uint16>, int)>('GetWindowTextW');
      final count = window.address == 0 ? 0 : getTitle(window, text, 512);
      final title = count > 0
          ? String.fromCharCodes(text.asTypedList(count))
              .replaceAll(RegExp(r'[\r\n\t]'), ' ')
          : '(unavailable)';
      var processName = '(unavailable)';
      final open = kernel.lookupFunction<
          Pointer<Void> Function(Uint32, Int32, Uint32),
          Pointer<Void> Function(int, int, int)>('OpenProcess');
      final close = kernel.lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('CloseHandle');
      final process = pid == 0 ? nullptr : open(0x1000, 0, pid);
      if (process.address != 0) {
        try {
          final size = length.cast<Uint32>()..value = 32768;
          final query = kernel.lookupFunction<
              Int32 Function(
                  Pointer<Void>, Uint32, Pointer<Uint16>, Pointer<Uint32>),
              int Function(Pointer<Void>, int, Pointer<Uint16>,
                  Pointer<Uint32>)>('QueryFullProcessImageNameW');
          if (query(process, 0, text, size) != 0) {
            processName = String.fromCharCodes(text.asTypedList(size.value))
                .split('\\')
                .last;
          }
        } finally {
          close(process);
        }
      }
      return 'process=$processName; window title="$title"';
    } catch (_) {
      return 'window metadata unavailable';
    } finally {
      if (buffer.address != 0) free(heap, 0, buffer);
      if (length.address != 0) free(heap, 0, length);
    }
  }
}
