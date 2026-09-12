import 'dart:ffi';
import 'dart:io';

import 'package:afterimage/services/windows_native_errors.dart';
import 'package:afterimage/services/windows_window_message_input.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Message extends Struct {
  external Pointer<Void> window;
  @Uint32()
  external int message;
  @UintPtr()
  external int wParam;
  @IntPtr()
  external int lParam;
  @Uint32()
  external int time;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Uint32()
  external int private;
}

void main() {
  test(
      'native window messages reach only the target with correct press and release flags',
      () {
    final user = DynamicLibrary.open('user32.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    final heap = kernel.lookupFunction<Pointer<Void> Function(),
        Pointer<Void> Function()>('GetProcessHeap')();
    final alloc = kernel.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
    final free = kernel.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');
    final className = alloc(heap, 8, 14).cast<Uint16>();
    final message = alloc(heap, 8, sizeOf<_Message>()).cast<_Message>();
    expect(className.address, isNonZero);
    expect(message.address, isNonZero);
    addTearDown(() {
      free(heap, 0, className.cast<Void>());
      free(heap, 0, message.cast<Void>());
    });
    className.asTypedList(7).setAll(0, [...'STATIC'.codeUnits, 0]);
    final create = user.lookupFunction<
        Pointer<Void> Function(
            Uint32,
            Pointer<Uint16>,
            Pointer<Uint16>,
            Uint32,
            Int32,
            Int32,
            Int32,
            Int32,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>),
        Pointer<Void> Function(
            int,
            Pointer<Uint16>,
            Pointer<Uint16>,
            int,
            int,
            int,
            int,
            int,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>)>('CreateWindowExW');
    final destroy = user.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('DestroyWindow');
    // Hidden, test-owned windows do not activate or alter any user's windows.
    final targetWindow = create(0, className, nullptr, 0x80000000, 0, 0, 20, 20,
        nullptr, nullptr, nullptr, nullptr);
    final otherWindow = create(0, className, nullptr, 0x80000000, 0, 0, 20, 20,
        nullptr, nullptr, nullptr, nullptr);
    expect(targetWindow.address, isNonZero);
    expect(otherWindow.address, isNonZero);
    addTearDown(() {
      destroy(targetWindow);
      destroy(otherWindow);
    });
    final pid = kernel.lookupFunction<Uint32 Function(), int Function()>(
        'GetCurrentProcessId')();
    final api = SystemWindowsWindowMessageApi();
    final target = WindowsGameWindow(targetWindow.address, pid);
    api.postKey(target, 0x55, down: true);
    api.postKey(target, 0x55, down: false);
    final peek = user.lookupFunction<
        Int32 Function(
            Pointer<_Message>, Pointer<Void>, Uint32, Uint32, Uint32),
        int Function(
            Pointer<_Message>, Pointer<Void>, int, int, int)>('PeekMessageW');
    expect(peek(message, otherWindow, 0x100, 0x101, 1), 0,
        reason: 'The other window must not receive replay keys');
    expect(peek(message, targetWindow, 0x100, 0x101, 1), isNonZero);
    expect(message.ref.message, 0x100);
    expect(message.ref.wParam, 0x55);
    expect(message.ref.lParam & 0xc0000000, 0);
    expect((message.ref.lParam >> 16) & 0xff, isNonZero);
    expect(peek(message, targetWindow, 0x100, 0x101, 1), isNonZero);
    expect(message.ref.message, 0x101);
    expect(message.ref.wParam, 0x55);
    expect(message.ref.lParam & 0xc0000000, 0xc0000000);
    expect(
        () => api.postKey(
            WindowsGameWindow(targetWindow.address, pid + 1), 0x55,
            down: true),
        throwsA(isA<WindowsNativeException>()));
    expect(peek(message, targetWindow, 0x100, 0x101, 1), 0);
  }, skip: !Platform.isWindows);
}
