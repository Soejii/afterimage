import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/services/linux_uinput_controller.dart';

void main() {
  group('Linux uinput mapping', () {
    test('maps GGST menu actions to clear gamepad controls', () {
      final mapping = LinuxUinputMenuMapping();

      expect(mapping.sequenceFor(ReplayMenuAction.openReplay), [
        LinuxUinputButton.south,
        LinuxUinputButton.south,
      ]);
      expect(
        mapping.sequenceFor(ReplayMenuAction.exitToReplayList),
        [LinuxUinputButton.south],
      );
      expect(
        mapping.sequenceFor(ReplayMenuAction.selectNextReplay),
        [LinuxUinputButton.dpadDown],
      );
    });

    test('rejects an incomplete mapping', () {
      expect(
        () => LinuxUinputMenuMapping(sequences: {
          ReplayMenuAction.openReplay: [LinuxUinputButton.south],
        }),
        throwsA(
          isA<LinuxUinputException>().having(
            (error) => error.code,
            'code',
            LinuxUinputErrorCode.invalidMapping,
          ),
        ),
      );
    });
  });

  group('Linux uinput input port', () {
    test('does not open a native device during construction', () {
      final factory = _FakeUinputFactory();
      LinuxUinputMenuInput(
        factory: factory,
        delay: (_) async {},
      );

      expect(factory.openedPaths, isEmpty);
    });

    test('configures, taps, releases, and waits between U,U buttons', () async {
      final factory = _FakeUinputFactory();
      final delays = <Duration>[];
      final input = LinuxUinputMenuInput(
        factory: factory,
        devicePaths: ['/fake/uinput'],
        delay: (duration) async => delays.add(duration),
      );

      await input.perform(ReplayMenuAction.openReplay);

      final device = factory.deviceForAssertions!;
      expect(factory.openedPaths, ['/fake/uinput']);
      expect(device.eventBits, [LinuxUinputEventType.key]);
      expect(
          device.keyBits,
          containsAll(<int>[
            LinuxUinputButton.south.code,
            LinuxUinputButton.dpadDown.code,
          ]));
      expect(device.actions, [
        'setup',
        'create',
        'press:${LinuxUinputButton.south.code}',
        'release:${LinuxUinputButton.south.code}',
        'press:${LinuxUinputButton.south.code}',
        'release:${LinuxUinputButton.south.code}',
      ]);
      expect(delays, [
        const Duration(seconds: 1),
        const Duration(milliseconds: 80),
        const Duration(milliseconds: 800),
        const Duration(milliseconds: 80),
      ]);
      expect(device.heldButtons, isEmpty);

      await input.close();
      expect(device.actions.last, 'close');
      expect(device.destroyed, isTrue);
    });

    test('closes and destroys the device after a failed sequence', () async {
      final factory = _FakeUinputFactory(
        device: _FakeUinputDevice(failOnPress: LinuxUinputButton.south.code),
      );
      final input = LinuxUinputMenuInput(
        factory: factory,
        devicePaths: ['/fake/uinput'],
        delay: (_) async {},
      );

      await expectLater(
        input.perform(ReplayMenuAction.openReplay),
        throwsA(
          isA<LinuxUinputException>().having(
            (error) => error.code,
            'code',
            LinuxUinputErrorCode.writeFailed,
          ),
        ),
      );
      expect(factory.deviceForAssertions!.destroyed, isTrue);
      expect(factory.deviceForAssertions!.closed, isTrue);
      expect(factory.deviceForAssertions!.heldButtons, isEmpty);
    });

    test('close releases a button left down by a native error', () async {
      final device = _FakeUinputDevice(failOnRelease: true);
      final factory = _FakeUinputFactory(device: device);
      final input = LinuxUinputMenuInput(
        factory: factory,
        devicePaths: ['/fake/uinput'],
        mapping: LinuxUinputMenuMapping(
          sequences: {
            ReplayMenuAction.openReplay: [LinuxUinputButton.south],
            ReplayMenuAction.exitToReplayList: [LinuxUinputButton.east],
            ReplayMenuAction.selectNextReplay: [LinuxUinputButton.dpadDown],
          },
        ),
        delay: (_) async {},
      );

      await expectLater(
        input.perform(ReplayMenuAction.openReplay),
        throwsA(isA<LinuxUinputException>()),
      );
      expect(device.destroyed, isTrue);
      expect(device.closed, isTrue);
      expect(device.releaseAttempts, contains(LinuxUinputButton.south.code));
    });

    test('waits for registration before the first event only once', () async {
      final factory = _FakeUinputFactory();
      final delays = <Duration>[];
      final actionsAtDelay = <List<String>>[];
      final input = LinuxUinputMenuInput(
        factory: factory,
        devicePaths: ['/fake/uinput'],
        registrationDelay: const Duration(seconds: 1),
        buttonHold: Duration.zero,
        buttonDelay: Duration.zero,
        delay: (duration) async {
          delays.add(duration);
          actionsAtDelay.add(
            List<String>.from(factory.deviceForAssertions?.actions ?? []),
          );
        },
      );

      await input.perform(ReplayMenuAction.openReplay);
      await input.perform(ReplayMenuAction.selectNextReplay);

      expect(delays, [
        const Duration(seconds: 1),
        Duration.zero,
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ]);
      expect(actionsAtDelay.first, ['setup', 'create']);
      expect(
        delays.where((duration) => duration == const Duration(seconds: 1)),
        hasLength(1),
      );
    });

    test('does not perform actions after close', () async {
      final factory = _FakeUinputFactory();
      final input = LinuxUinputMenuInput(factory: factory);
      await input.close();

      await expectLater(
        input.perform(ReplayMenuAction.exitToReplayList),
        throwsA(
          isA<LinuxUinputException>().having(
            (error) => error.code,
            'code',
            LinuxUinputErrorCode.closed,
          ),
        ),
      );
      expect(factory.openedPaths, isEmpty);
    });
  });

  group('Linux uinput readiness', () {
    test('reports a missing device distinctly', () {
      final probe = LinuxUinputReadinessProbe(
        factory: _FakeUinputFactory(
          openFailure: const LinuxUinputException(
            LinuxUinputErrorCode.deviceMissing,
            'missing',
          ),
        ),
        devicePaths: ['/dev/uinput'],
      );

      final readiness = probe.inspect();

      expect(readiness.ready, isFalse);
      expect(readiness.code, LinuxUinputErrorCode.deviceMissing);
    });

    test('reports permission denial distinctly', () {
      final probe = LinuxUinputReadinessProbe(
        factory: _FakeUinputFactory(
          openFailure: const LinuxUinputException(
            LinuxUinputErrorCode.permissionDenied,
            'denied',
          ),
        ),
        devicePaths: ['/dev/uinput'],
      );

      expect(probe.inspect().code, LinuxUinputErrorCode.permissionDenied);
    });

    test('reports an unsupported ioctl distinctly', () {
      final probe = LinuxUinputReadinessProbe(
        factory: _FakeUinputFactory(
          device: _FakeUinputDevice(
            eventBitFailure: const LinuxUinputException(
              LinuxUinputErrorCode.unsupportedIoctl,
              'old kernel',
            ),
          ),
        ),
        devicePaths: ['/dev/uinput'],
      );

      expect(probe.inspect().code, LinuxUinputErrorCode.unsupportedIoctl);
    });

    test('uses a second device path when the first is absent', () {
      final factory = _FakeUinputFactory(
        pathFailures: {
          '/dev/uinput': const LinuxUinputException(
            LinuxUinputErrorCode.deviceMissing,
            'missing',
          ),
        },
      );
      final probe = LinuxUinputReadinessProbe(
        factory: factory,
        devicePaths: ['/dev/uinput', '/dev/input/uinput'],
      );

      final readiness = probe.inspect();

      expect(readiness.ready, isTrue);
      expect(readiness.devicePath, '/dev/input/uinput');
      expect(factory.openedPaths, ['/dev/uinput', '/dev/input/uinput']);
    });
  }, skip: !Platform.isLinux);

  test('uses Linux generic ioctl encoding for uinput commands', () {
    expect(LinuxUinputIoctl.deviceCreate, 0x00005501);
    expect(LinuxUinputIoctl.deviceDestroy, 0x00005502);
    expect(LinuxUinputIoctl.deviceSetup, 0x405c5503);
    expect(LinuxUinputIoctl.setEventBit, 0x40045564);
    expect(LinuxUinputIoctl.setKeyBit, 0x40045565);
  });

  test(
    'the focused tests run on Linux without requiring /dev/uinput',
    () {
      expect(Platform.isLinux, isTrue);
    },
    skip: !Platform.isLinux,
  );
}

class _FakeUinputFactory implements LinuxUinputDeviceFactory {
  _FakeUinputFactory({
    this.device,
    this.openFailure,
    this.pathFailures = const <String, LinuxUinputException>{},
  });

  final _FakeUinputDevice? device;
  final LinuxUinputException? openFailure;
  final Map<String, LinuxUinputException> pathFailures;
  final List<String> openedPaths = <String>[];

  _FakeUinputDevice? _createdDevice;

  _FakeUinputDevice? get currentDevice => _createdDevice ?? device;

  @override
  LinuxUinputDevicePort open(String path) {
    openedPaths.add(path);
    final pathFailure = pathFailures[path];
    if (pathFailure != null) {
      throw pathFailure;
    }
    if (openFailure != null) {
      throw openFailure!;
    }
    _createdDevice = device ?? _FakeUinputDevice();
    return _createdDevice!;
  }

  _FakeUinputDevice? get deviceForAssertions => _createdDevice ?? device;
}

class _FakeUinputDevice implements LinuxUinputDevicePort {
  _FakeUinputDevice({
    this.failOnPress,
    this.failOnRelease = false,
    this.eventBitFailure,
  });

  final int? failOnPress;
  final bool failOnRelease;
  final LinuxUinputException? eventBitFailure;
  final List<int> eventBits = <int>[];
  final List<int> keyBits = <int>[];
  final List<String> actions = <String>[];
  final Set<int> heldButtons = <int>{};
  final List<int> releaseAttempts = <int>[];
  bool destroyed = false;
  bool closed = false;

  @override
  void setEventBit(int eventType) {
    if (eventBitFailure != null) {
      throw eventBitFailure!;
    }
    eventBits.add(eventType);
  }

  @override
  void setKeyBit(int keyCode) => keyBits.add(keyCode);

  @override
  void setup(LinuxUinputDeviceDescription description) {
    actions.add('setup');
  }

  @override
  void create() => actions.add('create');

  @override
  void press(int buttonCode) {
    actions.add('press:$buttonCode');
    heldButtons.add(buttonCode);
    if (buttonCode == failOnPress) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.writeFailed,
        'press failed after the button-down was attempted',
      );
    }
  }

  @override
  void release(int buttonCode) {
    actions.add('release:$buttonCode');
    releaseAttempts.add(buttonCode);
    if (failOnRelease) {
      throw const LinuxUinputException(
        LinuxUinputErrorCode.writeFailed,
        'release failed',
      );
    }
    heldButtons.remove(buttonCode);
  }

  @override
  void destroy() {
    actions.add('destroy');
    destroyed = true;
    heldButtons.clear();
  }

  @override
  void close() {
    if (!destroyed) {
      destroy();
    }
    actions.add('close');
    closed = true;
    heldButtons.clear();
  }
}
