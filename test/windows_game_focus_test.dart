import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/services/windows_game_focus.dart';
import 'package:afterimage/services/windows_menu_input.dart';
import 'package:afterimage/services/windows_native_backend.dart';
import 'package:afterimage/services/windows_native_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keyboard backend selects the focused keyboard port', () async {
    final backend = WindowsNativeRecorderBackend(platformIsWindows: true);
    final input = await backend.openMenuInput(InputMode.keyboard);
    expect(input, isA<WindowsFocusedKeyboardMenuInput>(),
        reason:
            'GGST ignores posted window messages, so keyboard mode must press real keys');
    expect(input, isNot(isA<InputSafetyPort>()),
        reason: 'Focus matters only at a key press, not during playback');
    await (input as ClosableMenuInputPort).close();
  });

  test('leaves the desktop alone when GGST is already in front', () async {
    final focus = _FakeFocusApi(foreground: true);
    final delays = <Duration>[];
    await WindowsGameActivator(api: focus, delay: (d) async => delays.add(d))
        .ensureGameForeground();
    expect(focus.requests, 0);
    expect(delays, isEmpty);
  });

  test('brings GGST to the front, then presses and releases the key', () async {
    final log = <String>[];
    final focus = _FakeFocusApi(foreground: false, log: log)
      ..foregroundAfterChecks = 3;
    final keys = _FakeKeyboardApi(log);
    final activator = WindowsGameActivator(api: focus, delay: (_) async {});
    final driver = WindowsSendInputDriver(
      api: keys,
      keyHold: Duration.zero,
      beforePress: activator.ensureGameForeground,
    );
    await driver.open();
    await driver.press('U');
    expect(focus.requests, 1);
    expect(log, ['request-foreground', 'down 85', 'up 85']);
  });

  test('sends no key when GGST cannot be brought to the front', () async {
    final log = <String>[];
    final focus = _FakeFocusApi(foreground: false, log: log)
      ..failure = 'Focus diagnostic: foreground process differs from GGST';
    final keys = _FakeKeyboardApi(log);
    final waits = <Duration>[];
    final activator = WindowsGameActivator(
      api: focus,
      delay: (d) async => waits.add(d),
      timeout: const Duration(seconds: 1),
      pollInterval: const Duration(milliseconds: 250),
    );
    final driver = WindowsSendInputDriver(
      api: keys,
      keyHold: Duration.zero,
      beforePress: activator.ensureGameForeground,
    );
    await driver.open();
    await expectLater(
      driver.press('U'),
      throwsA(isA<WindowsNativeException>()
          .having(
              (e) => e.code, 'code', WindowsNativeErrorCode.inputUnavailable)
          .having(
              (e) => e.message,
              'message',
              allOf(
                  contains('no key was sent'), contains('differs from GGST')))),
    );
    expect(log, ['request-foreground'],
        reason: 'A key typed without GGST in front lands in another app');
    expect(waits.length, 4, reason: 'It waits the whole timeout, then stops');
  });

  test('a driver closed while GGST is coming to the front sends no key',
      () async {
    final log = <String>[];
    final keys = _FakeKeyboardApi(log);
    late final WindowsSendInputDriver driver;
    driver = WindowsSendInputDriver(
      api: keys,
      keyHold: Duration.zero,
      beforePress: () => driver.close(),
    );
    await driver.open();
    await expectLater(
      driver.press('U'),
      throwsA(isA<WindowsNativeException>()
          .having((e) => e.code, 'code', WindowsNativeErrorCode.closed)),
    );
    expect(log, isEmpty);
  });

  test('the menu port stops the sequence when focus is lost between keys',
      () async {
    final log = <String>[];
    final focus = _FakeFocusApi(foreground: true, log: log);
    final keys = _FakeKeyboardApi(log);
    final activator = WindowsGameActivator(
        api: focus, delay: (_) async {}, timeout: Duration.zero);
    final input = WindowsFocusedKeyboardMenuInput(
      driver: WindowsSendInputDriver(
        api: keys,
        keyHold: Duration.zero,
        beforePress: activator.ensureGameForeground,
      ),
    );
    await input.perform(ReplayMenuAction.openReplayMenu);
    focus.foreground = false;
    await expectLater(input.perform(ReplayMenuAction.confirmMenuItem),
        throwsA(isA<WindowsNativeException>()));
    expect(log, ['down 85', 'up 85', 'request-foreground']);
  });
}

class _FakeFocusApi implements WindowsGameFocusApi {
  _FakeFocusApi({required this.foreground, List<String>? log})
      : log = log ?? <String>[];
  bool foreground;
  final List<String> log;
  int requests = 0;
  int checks = 0;

  /// When set, GGST reaches the front on this numbered check.
  int? foregroundAfterChecks;
  String? failure;

  @override
  String? get lastFocusFailure => foreground ? null : failure;

  @override
  bool isGameForeground() {
    checks++;
    final after = foregroundAfterChecks;
    if (after != null && requests > 0 && checks >= after) foreground = true;
    return foreground;
  }

  @override
  void requestGameForeground() {
    requests++;
    log.add('request-foreground');
  }
}

class _FakeKeyboardApi implements WindowsKeyboardNativeApi {
  _FakeKeyboardApi(this.log);
  final List<String> log;

  @override
  void open() {}

  @override
  void sendKey(int virtualKey,
      {required bool keyDown, required int inputSize}) {
    log.add('${keyDown ? 'down' : 'up'} $virtualKey');
  }

  @override
  void close() {}
}
