import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/services/windows_native_backend.dart';
import 'package:afterimage/services/windows_native_errors.dart';
import 'package:afterimage/services/windows_window_message_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keyboard backend selects a game-window port without a foreground gate',
      () async {
    final backend = WindowsNativeRecorderBackend(platformIsWindows: true);
    final input = await backend.openMenuInput(InputMode.keyboard);
    expect(input, isA<WindowsWindowMessageMenuInput>(),
        reason:
            'Windows keyboard mode must address GGST instead of the foreground desktop input queue');
    expect(input, isNot(isA<InputSafetyPort>()));
    await (input as ClosableMenuInputPort).close();
  });

  test(
      'a key release keeps the original target when focus changes during a tap',
      () async {
    final api = _FakeWindowApi();
    final driver = WindowsWindowMessageDriver(
        api: api,
        delay: (_) async {
          api.foreground = 99;
        });
    await driver.open();
    await driver.press('U');
    expect(api.foreground, 99);
    expect(api.messages, [(42, 0x55, true), (42, 0x55, false)]);
    expect(api.findCalls, 1);
    await driver.close();
    await expectLater(
        driver.press('U'), throwsA(isA<WindowsNativeException>()));
    expect(api.messages.length, 2);
  });

  test('releases the target key when the hold fails', () async {
    final api = _FakeWindowApi();
    final driver = WindowsWindowMessageDriver(
        api: api, delay: (_) async => throw StateError('interrupted'));
    await driver.open();
    await expectLater(driver.press('W'), throwsStateError);
    expect(api.messages, [(42, 0x57, true), (42, 0x57, false)]);
  });

  test('never falls back to desktop input after a target failure', () async {
    final api = _FakeWindowApi()..reject = true;
    final driver = WindowsWindowMessageDriver(api: api);
    await driver.open();
    await expectLater(
        driver.press('U'), throwsA(isA<WindowsNativeException>()));
    expect(api.messages, isEmpty);
  });

  test(
      'native adapter refuses broadcast and null targets before accessing Windows',
      () {
    final api = SystemWindowsWindowMessageApi();
    for (final handle in [0, -1, 0xffff]) {
      expect(() => api.postKey(WindowsGameWindow(handle, 42), 0x55, down: true),
          throwsA(isA<WindowsNativeException>()));
    }
  });
}

class _FakeWindowApi implements WindowsWindowMessageApi {
  int foreground = 42;
  int findCalls = 0;
  bool reject = false;
  final messages = <(int, int, bool)>[];

  @override
  WindowsGameWindow findGameWindow() {
    findCalls++;
    return const WindowsGameWindow(42, 100);
  }

  @override
  void postKey(WindowsGameWindow target, int virtualKey, {required bool down}) {
    if (reject) {
      throw const WindowsNativeException(
          WindowsNativeErrorCode.inputUnavailable, 'Window closed');
    }
    messages.add((target.handle, virtualKey, down));
  }
}
