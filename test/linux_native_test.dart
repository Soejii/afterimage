import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/obs_models.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/services/linux_menu_input.dart';
import 'package:afterimage/services/linux_native_backend.dart';
import 'package:afterimage/services/linux_native_errors.dart';
import 'package:afterimage/services/linux_process_memory.dart';
import 'package:afterimage/services/linux_replay_monitor.dart';
import 'package:afterimage/services/linux_uinput_controller.dart';
import 'package:afterimage/services/output_organizer.dart';

void main() {
  group('Linux proc maps and module selection', () {
    test('parses mappings and ignores malformed lines', () {
      final mappings = parseLinuxMappings('''
      not a mapping
      00001000-00002000 r--p 00000000 00:00 1 /game/GGST-Win64-Shipping.exe
      00002000-00003000 r-xp 00001000 00:00 1
      00004000-00005000 rw-p 00002000 00:00 1 /other.so
      ''');

      expect(mappings, hasLength(3));
      expect(mappings[0].start, 0x1000);
      expect(mappings[1].path, isEmpty);
      expect(mappings[2].permissions, 'rw-p');
    });

    test('selects contiguous Wine image mappings and computes its image size',
        () {
      final all = <LinuxMapping>[
        const LinuxMapping(
          start: 0x4000,
          end: 0x5000,
          permissions: 'r--p',
          path: '/game/GGST-Win64-Shipping.exe (deleted)',
        ),
        const LinuxMapping(
          start: 0x5000,
          end: 0x7000,
          permissions: 'r-xp',
        ),
        const LinuxMapping(
          start: 0x8000,
          end: 0x9000,
          permissions: 'rw-p',
          path: '/game/GGST-Win64-Shipping.exe',
        ),
      ];

      final module = LinuxModule.fromMappings(
        all,
        ggstLinuxExecutable,
      );

      expect(module, isNotNull);
      expect(module!.mappings, hasLength(3));
      expect(module.baseAddress, 0x4000);
      expect(module.sizeOfImage, 0x4000);
      expect(LinuxModule.fromMappings(all, 'missing.exe'), isNull);
    });
  });

  group('Linux pattern scanning', () {
    test('matches wildcards and resolves a signed RIP-relative address', () {
      final pattern = LinuxBytePattern(
        bytes: <int>[0x48, 0x8b, 0x1d, 0xaa],
        mask: 'xxx?',
      );
      expect(pattern.find(<int>[0, 0x48, 0x8b, 0x1d, 0xff]), 1);
      expect(pattern.matchesAt(<int>[0x48, 0x00, 0x1d, 0x01], 0), isFalse);
      expect(decodeSignedInt32(<int>[0xfc, 0xff, 0xff, 0xff]), -4);
      expect(resolveRipRelativeAddress(0x1000, -4), 0x1008);
    });

    test('finds a pattern across a bounded read chunk', () {
      final mapping = LinuxModule(<LinuxMapping>[
        const LinuxMapping(
          start: 0x1000,
          end: 0x1008,
          permissions: 'r-xp',
        ),
      ]);
      final memory = <int, int>{
        0x1003: 0xaa,
        0x1004: 0xbb,
        0x1005: 0xcc,
      };
      final result = const LinuxPatternScanner(chunkSize: 4).scan(
        module: mapping,
        pattern: LinuxBytePattern(
          bytes: <int>[0xaa, 0xbb, 0xcc],
          mask: 'xxx',
        ),
        read: (address, length) => List<int>.generate(
          length,
          (index) => memory[address + index] ?? 0,
        ),
      );

      expect(result.address, 0x1003);
      expect(result.inaccessibleReads, 0);
    });

    test('records permission failures without hiding other mappings', () {
      final module = LinuxModule(<LinuxMapping>[
        const LinuxMapping(
          start: 0x1000,
          end: 0x1100,
          permissions: 'r-xp',
        ),
      ]);
      final result = const LinuxPatternScanner().scan(
        module: module,
        pattern: LinuxBytePattern(bytes: <int>[1], mask: 'x'),
        read: (_, __) => throw const OSError('denied', 13),
      );

      expect(result.address, isNull);
      expect(result.permissionDeniedReads, 1);
    });
  });

  group('Linux replay monitor', () {
    test('decodes the GWorld pointer chain, frame, and bounded events',
        () async {
      final fake = _FakeMemorySession.withGWorldSignature();
      final monitor = LinuxReplayMonitor(memoryFactory: (_) => fake);

      await monitor.attach();
      final snapshot = await monitor.snapshot();

      expect(snapshot.enginePresent, isTrue);
      expect(snapshot.frame, 1234);
      expect(snapshot.events, contains(15));
      expect(snapshot.events, contains(7));
      expect(fake.closed, isFalse);
      await monitor.close();
      expect(fake.closed, isTrue);
      await monitor.close();
      expect(
        () => monitor.snapshot(),
        throwsA(
          isA<LinuxNativeException>().having(
            (error) => error.code,
            'code',
            LinuxNativeErrorCode.notAttached,
          ),
        ),
      );
    });

    test('turns an inaccessible sample into an empty snapshot', () async {
      final fake = _FakeMemorySession.withGWorldSignature();
      final monitor = LinuxReplayMonitor(memoryFactory: (_) => fake);

      await monitor.attach();
      fake.throwOnSnapshotReads = true;
      final snapshot = await monitor.snapshot();

      expect(snapshot, isA<BattleSnapshot>());
      expect(snapshot.enginePresent, isFalse);
    });

    test('propagates persistent process-memory denial', () async {
      final fake = _FakeMemorySession.withGWorldSignature();
      final monitor = LinuxReplayMonitor(memoryFactory: (_) => fake);

      await monitor.attach();
      fake.snapshotError = const LinuxNativeException(
        LinuxNativeErrorCode.processMemoryDenied,
        'persistent denial',
      );

      await expectLater(
        monitor.snapshot(),
        throwsA(_nativeCode(LinuxNativeErrorCode.processMemoryDenied)),
      );
    });

    test('reports signature mismatch and closes a failed attach', () async {
      final fake = _FakeMemorySession(
        module: LinuxModule(<LinuxMapping>[
          const LinuxMapping(
            start: 0x1000,
            end: 0x1100,
            permissions: 'r-xp',
          ),
        ]),
      );
      final monitor = LinuxReplayMonitor(memoryFactory: (_) => fake);

      await expectLater(
        monitor.attach(),
        throwsA(
          isA<LinuxNativeException>().having(
            (error) => error.code,
            'code',
            LinuxNativeErrorCode.signatureMismatch,
          ),
        ),
      );
      expect(fake.closed, isTrue);
    });

    test('reports denied pattern reads as process memory denied', () async {
      final fake = _FakeMemorySession.withGWorldSignature()
        ..throwOnPatternReads = true;
      final monitor = LinuxReplayMonitor(memoryFactory: (_) => fake);

      await expectLater(
        monitor.attach(),
        throwsA(
          isA<LinuxNativeException>().having(
            (error) => error.code,
            'code',
            LinuxNativeErrorCode.processMemoryDenied,
          ),
        ),
      );
      expect(fake.closed, isTrue);
    });
  });

  group('Linux gamescope input', () {
    test('discovers DISPLAY from the matching GGST process environment', () {
      final proc = _FakeProcFileSystem({
        42: {
          'cmdline': utf8.encode('/games/GGST-Win64-Shipping.exe\u0000'),
          'comm': utf8.encode('wine-preloader\u0000'),
          'environ': utf8.encode('HOME=/tmp\u0000DISPLAY=:7.0\u0000'),
        },
      });
      final discovery = LinuxGamescopeDisplayDiscovery(
        procFileSystem: proc,
      );

      expect(discovery.discover(), ':7.0');
      expect(
        LinuxGamescopeDisplayDiscovery.parseEnvironment(
          utf8.encode('A=1\u0000DISPLAY=:2\u0000'),
        ),
        containsPair('DISPLAY', ':2'),
      );
    });

    test('distinguishes absent, missing, and invalid displays', () {
      final absent = LinuxGamescopeDisplayDiscovery(
        procFileSystem: _FakeProcFileSystem(const {}),
      );
      expect(
        () => absent.discover(),
        throwsA(_nativeCode(LinuxNativeErrorCode.gameAbsent)),
      );

      final missing = LinuxGamescopeDisplayDiscovery(
        procFileSystem: _FakeProcFileSystem({
          1: {
            'cmdline': utf8.encode('GGST-Win64-Shipping.exe\u0000'),
            'comm': utf8.encode('GGST-Win64-Shipping.exe\u0000'),
            'environ': utf8.encode('HOME=/tmp\u0000'),
          },
        }),
      );
      expect(
        () => missing.discover(),
        throwsA(_nativeCode(LinuxNativeErrorCode.gamescopeDisplayMissing)),
      );

      final invalid = LinuxGamescopeDisplayDiscovery(
        procFileSystem: _FakeProcFileSystem({
          1: {
            'cmdline': utf8.encode('GGST-Win64-Shipping.exe\u0000'),
            'comm': utf8.encode('GGST-Win64-Shipping.exe\u0000'),
            'environ': utf8.encode('DISPLAY=desktop\u0000'),
          },
        }),
      );
      expect(
        () => invalid.discover(),
        throwsA(_nativeCode(LinuxNativeErrorCode.invalidDisplay)),
      );
    });

    test('maps semantic actions, validates keys, and closes on failure',
        () async {
      final driver = _FakeKeyboardDriver()..failOnPress = 'W';
      final input = LinuxKeyboardMenuInput(
        discovery: LinuxGamescopeDisplayDiscovery(
          procFileSystem: _gameProc(':4'),
        ),
        driver: driver,
      );

      await input.perform(ReplayMenuAction.openReplay);
      expect(driver.openedDisplays, [':4']);
      expect(driver.pressed, ['U', 'U']);
      await input.perform(ReplayMenuAction.exitToReplayList);
      expect(driver.pressed, ['U', 'U', 'U']);

      await expectLater(
        input.perform(ReplayMenuAction.selectNextReplay),
        throwsA(isA<StateError>()),
      );
      expect(driver.closeCount, 1);

      expect(
        () => validateLinuxKey('A;rm'),
        throwsA(_nativeCode(LinuxNativeErrorCode.invalidKey)),
      );
      expect(
        () => validateGamescopeDisplay('wayland-1'),
        throwsA(_nativeCode(LinuxNativeErrorCode.invalidDisplay)),
      );
    });

    test('waits between keys in a multi-key replay action', () async {
      final driver = _FakeKeyboardDriver();
      final delays = <Duration>[];
      final input = LinuxKeyboardMenuInput(
        discovery: LinuxGamescopeDisplayDiscovery(
          procFileSystem: _gameProc(':4'),
        ),
        driver: driver,
        delay: (duration) async => delays.add(duration),
      );

      await input.perform(ReplayMenuAction.openReplay);

      expect(driver.pressed, ['U', 'U']);
      expect(delays, [const Duration(milliseconds: 800)]);
    });

    test('rejects empty or incomplete configurable mappings', () {
      expect(
        () => LinuxMenuInputMapping(
          sequences: <ReplayMenuAction, Iterable<String>>{
            ReplayMenuAction.openReplay: const <String>[],
          },
        ),
        throwsA(_nativeCode(LinuxNativeErrorCode.invalidKey)),
      );
    });
  });

  group('Linux native backend', () {
    test('does not silently fall back from controller mode', () async {
      final backend = LinuxNativeRecorderBackend(
        displayDiscovery: LinuxGamescopeDisplayDiscovery(
          procFileSystem: _gameProc(':5'),
        ),
        memoryFactory: (_) => _FakeMemorySession.withGWorldSignature(),
        keyboardDriverFactory: _FakeKeyboardDriver.new,
      );

      expect(
        await backend.openMenuInput(InputMode.controller),
        isA<LinuxUinputMenuInput>(),
      );
    });

    test('exposes detailed readiness failures for absent game', () async {
      final backend = LinuxNativeRecorderBackend(
        displayDiscovery: LinuxGamescopeDisplayDiscovery(
          procFileSystem: _FakeProcFileSystem(const {}),
        ),
        memoryFactory: (_) => throw const LinuxNativeException(
          LinuxNativeErrorCode.gameAbsent,
          'game absent',
        ),
        keyboardDriverFactory: _FakeKeyboardDriver.new,
      );

      final report = await backend.inspectDetailed();

      expect(report.ready, isFalse);
      expect(
        report.blockingChecks,
        contains(isA<LinuxReadinessCheck>().having(
          (check) => check.code,
          'code',
          LinuxNativeErrorCode.gameAbsent,
        )),
      );
      expect(report.detail, contains('game absent'));
    });

    test('input readiness does not depend on replay monitor attachment',
        () async {
      final backend = LinuxNativeRecorderBackend(
        libraryProbe: _FakeLibraryProbe(
          <String>{'libX11.so.6', 'libXtst.so.6'},
        ),
        displayDiscovery: LinuxGamescopeDisplayDiscovery(
          procFileSystem: _gameProc(':5'),
        ),
        memoryFactory: (_) => throw const LinuxNativeException(
          LinuxNativeErrorCode.processMemoryDenied,
          'memory monitor unavailable',
        ),
        keyboardDriverFactory: _FakeKeyboardDriver.new,
      );

      final readiness = await backend.inspectForInput(InputMode.keyboard);

      expect(readiness.available, isTrue);
      expect(readiness.detail, isNot(contains('memory monitor unavailable')));
    });

    test('assembles monitor, keyboard, OBS, and output ports', () async {
      final fakeDriver = _FakeKeyboardDriver();
      final fakeObs = _FakeObsRecorder();
      final backend = LinuxNativeRecorderBackend(
        obsConfig: const ObsWebSocketConfig(port: 4455),
        obsRecorderFactory: (_) => fakeObs,
        outputOrganizerFactory: () => const FileOutputOrganizer(),
        displayDiscovery: LinuxGamescopeDisplayDiscovery(
          procFileSystem: _gameProc(':6'),
        ),
        memoryFactory: (_) => _FakeMemorySession.withGWorldSignature(),
        keyboardDriverFactory: () => fakeDriver,
      );

      expect(await backend.openReplayMonitor(), isA<LinuxReplayMonitor>());
      expect(
        await backend.openMenuInput(InputMode.keyboard),
        isA<LinuxKeyboardMenuInput>(),
      );
      expect(await backend.openObsRecorder(), same(fakeObs));
      expect(
        await backend.openOutputOrganizer(),
        isA<FileOutputOrganizer>(),
      );
    });

    test('reports missing X11 and XTest separately', () async {
      final backend = LinuxNativeRecorderBackend(
        libraryProbe: _FakeLibraryProbe(<String>{'libX11.so.6'}),
        memoryFactory: (_) => throw const LinuxNativeException(
          LinuxNativeErrorCode.gameAbsent,
          'game absent',
        ),
        displayDiscovery: LinuxGamescopeDisplayDiscovery(
          procFileSystem: _FakeProcFileSystem(const {}),
        ),
      );

      final report = await backend.inspectDetailed();

      expect(
        report.blockingChecks,
        contains(isA<LinuxReadinessCheck>().having(
          (check) => check.code,
          'code',
          LinuxNativeErrorCode.missingXTest,
        )),
      );
      expect(
        report.blockingChecks.where(
          (check) => check.code == LinuxNativeErrorCode.missingX11,
        ),
        isEmpty,
      );
    });
  }, skip: !Platform.isLinux);
}

Matcher _nativeCode(LinuxNativeErrorCode code) =>
    isA<LinuxNativeException>().having((error) => error.code, 'code', code);

_FakeProcFileSystem _gameProc(String display) => _FakeProcFileSystem({
      10: {
        'cmdline': utf8.encode('/game/GGST-Win64-Shipping.exe\u0000'),
        'comm': utf8.encode('wine-preloader\u0000'),
        'environ': utf8.encode('DISPLAY=$display\u0000'),
      },
    });

class _FakeProcFileSystem implements LinuxProcFileSystem {
  _FakeProcFileSystem(this.files);

  final Map<int, Map<String, List<int>>> files;

  @override
  Iterable<int> processIds() => files.keys;

  @override
  String memoryPath(int processId) => '/fake/$processId/mem';

  @override
  List<int> readFile(int processId, String name) {
    final file = files[processId]?[name];
    if (file == null) {
      throw const FileSystemException('missing fake proc file');
    }
    return file;
  }
}

class _FakeMemorySession implements LinuxMemorySession {
  _FakeMemorySession({required this.module});

  factory _FakeMemorySession.withGWorldSignature() {
    final bytes = <int, int>{};
    final module = LinuxModule(<LinuxMapping>[
      const LinuxMapping(
        start: 0x1000,
        end: 0x1100,
        permissions: 'r-xp',
        path: '/game/GGST-Win64-Shipping.exe',
      ),
    ]);
    const hit = 0x1020;
    const pattern = <int>[
      0x0F,
      0x2E,
      0xAA,
      0x74,
      0xBB,
      0x48,
      0x8B,
      0x1D,
      0xD4,
      0x0F,
      0x00,
      0x00,
      0x48,
      0x85,
      0xDB,
      0x74,
    ];
    for (var index = 0; index < pattern.length; index++) {
      bytes[hit + index] = pattern[index];
    }
    _putPointer(bytes, 0x2000, 0x3000);
    _putPointer(bytes, 0x3130, 0x4000);
    _putPointer(bytes, 0x4C38, 0x5000);
    _putUint32(bytes, 0x8E7C, 1234);
    _putPointer(bytes, 0x4C58, 0x6000);
    _putUint32(bytes, 0x60A8, 2);
    _putUint32(bytes, 0x6008, 15);
    _putUint32(bytes, 0x6018, 7);
    return _FakeMemorySession(module: module)..memory.addAll(bytes);
  }

  final LinuxModule module;
  final Map<int, int> memory = <int, int>{};
  bool closed = false;
  bool throwOnPatternReads = false;
  bool throwOnSnapshotReads = false;
  LinuxNativeException? snapshotError;

  @override
  int get processId => 99;

  @override
  LinuxModule moduleFromName(String moduleName) => module;

  @override
  List<int> readBytes(int address, int length) {
    if (throwOnPatternReads && address == 0x1000) {
      throw const OSError('denied', 13);
    }
    if (snapshotError != null && address != 0x1000) {
      throw snapshotError!;
    }
    if (throwOnSnapshotReads && address != 0x1000) {
      throw const OSError('read failed', 5);
    }
    return List<int>.generate(
      length,
      (index) => memory[address + index] ?? 0,
    );
  }

  @override
  void close() {
    closed = true;
  }
}

void _putPointer(Map<int, int> memory, int address, int value) {
  for (var index = 0; index < 8; index++) {
    memory[address + index] = (value >> (index * 8)) & 0xff;
  }
}

void _putUint32(Map<int, int> memory, int address, int value) {
  for (var index = 0; index < 4; index++) {
    memory[address + index] = (value >> (index * 8)) & 0xff;
  }
}

class _FakeKeyboardDriver implements LinuxKeyboardDriver {
  final List<String> openedDisplays = <String>[];
  final List<String> pressed = <String>[];
  String? failOnPress;
  int closeCount = 0;

  @override
  Future<void> open(String display) async {
    openedDisplays.add(display);
  }

  @override
  Future<void> press(String key) async {
    if (key == failOnPress) {
      throw StateError('fake input failure');
    }
    pressed.add(key);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class _FakeLibraryProbe implements LinuxNativeLibraryProbe {
  _FakeLibraryProbe(this.available);

  final Set<String> available;

  @override
  bool canOpen(Iterable<String> names) => names.any(available.contains);
}

class _FakeObsRecorder implements ObsRecorderPort {
  @override
  Future<void> connect() async {}

  @override
  Future<void> assertIdle() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<RecordedOutput> stopRecording() async =>
      const RecordedOutput('/tmp/fake.mp4');

  @override
  Future<void> close() async {}
}
