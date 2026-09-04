import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/obs_models.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/services/windows_menu_input.dart';
import 'package:afterimage/services/windows_native_backend.dart';
import 'package:afterimage/services/windows_native_errors.dart';
import 'package:afterimage/services/windows_process_memory.dart';
import 'package:afterimage/services/windows_replay_monitor.dart';
import 'package:afterimage/services/windows_virtual_controller.dart';
import 'package:afterimage/services/output_organizer.dart';

void main() {
  group('Windows SendInput ABI', () {
    test('matches the native x64 INPUT size', () {
      if (sizeOf<IntPtr>() != 8) {
        return;
      }
      expect(windowsInputSize, 40);
    });
  });

  group('Windows process memory seam', () {
    test('matches the native PROCESSENTRY32W layout', () {
      expect(
        windowsProcessEntrySize,
        sizeOf<IntPtr>() == 8 ? 568 : 556,
      );
    });

    test('opens a named process, reads through the injected API, and closes',
        () {
      final api = _FakeWindowsApi(
        module: const WindowsModule(
          name: ggstWindowsExecutable,
          baseAddress: 0x1000,
          sizeOfImage: 0x100,
        ),
      );
      api.bytes[0x2000] = 0xAB;
      api.bytes[0x2001] = 0xCD;

      final memory = WindowsProcessMemory.open(
        ggstWindowsExecutable,
        api: api,
      );
      expect(memory.processId, 42);
      expect(memory.moduleFromName(ggstWindowsExecutable).baseAddress, 0x1000);
      expect(memory.readBytes(0x2000, 2), [0xAB, 0xCD]);
      memory.close();
      memory.close();
      expect(api.closedHandles, [api.handle]);
      expect(
        () => memory.readBytes(0x2000, 1),
        throwsA(_windowsCode(WindowsNativeErrorCode.closed)),
      );
    });

    test('does not attempt Windows DLL access on Linux when unconfigured', () {
      if (Platform.isWindows) {
        return;
      }
      final api = SystemWindowsNativeApi();
      expect(
        () => api.findProcessId(ggstWindowsExecutable),
        throwsA(_windowsCode(WindowsNativeErrorCode.nativeApiUnavailable)),
      );
    });
  });

  group('Windows pattern scanning', () {
    test('matches wildcards and resolves a signed RIP-relative address', () {
      final pattern = WindowsBytePattern(
        bytes: <int>[0x48, 0x8B, 0x1D, 0xAA],
        mask: 'xxx?',
      );
      expect(pattern.find(<int>[0, 0x48, 0x8B, 0x1D, 0xFF]), 1);
      expect(
        pattern.matchesAt(<int>[0x48, 0x00, 0x1D, 0x01], 0),
        isFalse,
      );
      expect(decodeWindowsSignedInt32(<int>[0xFC, 0xFF, 0xFF, 0xFF]), -4);
      expect(resolveWindowsRipRelativeAddress(0x1000, -4), 0x1008);
    });

    test('finds a pattern across a bounded module read chunk', () {
      const module = WindowsModule(
        name: ggstWindowsExecutable,
        baseAddress: 0x1000,
        sizeOfImage: 8,
      );
      final memory = <int, int>{
        0x1003: 0xAA,
        0x1004: 0xBB,
        0x1005: 0xCC,
      };
      final result = const WindowsPatternScanner(chunkSize: 4).scan(
        module: module,
        pattern: WindowsBytePattern(
          bytes: <int>[0xAA, 0xBB, 0xCC],
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

    test('records denied reads and continues scanning', () {
      const module = WindowsModule(
        name: ggstWindowsExecutable,
        baseAddress: 0x1000,
        sizeOfImage: 0x100,
      );
      final result = const WindowsPatternScanner().scan(
        module: module,
        pattern: WindowsBytePattern(bytes: <int>[1], mask: 'x'),
        read: (_, __) => throw const WindowsNativeException(
          WindowsNativeErrorCode.processMemoryDenied,
          'denied',
        ),
      );

      expect(result.address, isNull);
      expect(result.permissionDeniedReads, 1);
    });

    test('never reads across an inaccessible module gap', () {
      const module = WindowsModule(
        name: ggstWindowsExecutable,
        baseAddress: 0x1000,
        sizeOfImage: 0x300,
      );
      const regions = <WindowsMemoryRegion>[
        WindowsMemoryRegion(baseAddress: 0x1000, size: 0x20),
        WindowsMemoryRegion(baseAddress: 0x1200, size: 0x20),
      ];
      final requests = <(int, int)>[];
      final result = const WindowsPatternScanner(chunkSize: 0x10).scan(
        module: module,
        pattern: WindowsBytePattern(bytes: <int>[0xAA, 0xBB], mask: 'xx'),
        readableRegions: regions,
        read: (address, length) {
          requests.add((address, length));
          if (address < 0x1000 ||
              address + length > 0x1020 && address < 0x1200 ||
              address >= 0x1200 && address + length > 0x1220) {
            throw StateError('read crossed an inaccessible module gap');
          }
          return List<int>.filled(length, 0);
        },
      );

      expect(result.address, isNull);
      expect(requests, isNotEmpty);
      for (final (address, length) in requests) {
        final inFirst = address >= 0x1000 && address + length <= 0x1020;
        final inSecond = address >= 0x1200 && address + length <= 0x1220;
        expect(inFirst || inSecond, isTrue);
      }
    });
  });

  group('Windows replay monitor', () {
    test('decodes the GWorld pointer chain, frame, and bounded events',
        () async {
      final fake = _FakeWindowsMemorySession.withGWorldSignature();
      final monitor = WindowsReplayMonitor(memoryFactory: (_) => fake);

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
        throwsA(_windowsCode(WindowsNativeErrorCode.notAttached)),
      );
    });

    test('turns an inaccessible sample into an empty snapshot', () async {
      final fake = _FakeWindowsMemorySession.withGWorldSignature();
      final monitor = WindowsReplayMonitor(memoryFactory: (_) => fake);

      await monitor.attach();
      fake.throwOnSnapshotReads = true;
      final snapshot = await monitor.snapshot();

      expect(snapshot.enginePresent, isFalse);
    });

    test('propagates persistent process-memory denial during a snapshot',
        () async {
      final fake = _FakeWindowsMemorySession.withGWorldSignature();
      final monitor = WindowsReplayMonitor(memoryFactory: (_) => fake);

      await monitor.attach();
      fake.snapshotFailure = WindowsNativeErrorCode.processMemoryDenied;
      await expectLater(
        monitor.snapshot(),
        throwsA(_windowsCode(WindowsNativeErrorCode.processMemoryDenied)),
      );
    });

    test('propagates architecture mismatch during a snapshot', () async {
      final fake = _FakeWindowsMemorySession.withGWorldSignature();
      final monitor = WindowsReplayMonitor(memoryFactory: (_) => fake);

      await monitor.attach();
      fake.snapshotFailure = WindowsNativeErrorCode.architectureMismatch;
      await expectLater(
        monitor.snapshot(),
        throwsA(_windowsCode(WindowsNativeErrorCode.architectureMismatch)),
      );
    });

    test('reports signature mismatch and closes a failed attach', () async {
      final fake = _FakeWindowsMemorySession();
      final monitor = WindowsReplayMonitor(memoryFactory: (_) => fake);

      await expectLater(
        monitor.attach(),
        throwsA(_windowsCode(WindowsNativeErrorCode.signatureMismatch)),
      );
      expect(fake.closed, isTrue);
    });

    test('reports denied pattern reads as process memory denied', () async {
      final fake = _FakeWindowsMemorySession.withGWorldSignature()
        ..throwOnPatternReads = true;
      final monitor = WindowsReplayMonitor(memoryFactory: (_) => fake);

      await expectLater(
        monitor.attach(),
        throwsA(_windowsCode(WindowsNativeErrorCode.processMemoryDenied)),
      );
      expect(fake.closed, isTrue);
    });
  });

  group('Windows SendInput mapping', () {
    test('maps actions, waits between U,U, and closes after failure', () async {
      final driver = _FakeWindowsKeyboardDriver()..failOnPress = 'W';
      final delays = <Duration>[];
      final input = WindowsKeyboardMenuInput(
        driver: driver,
        delay: (duration) async => delays.add(duration),
      );

      await input.perform(ReplayMenuAction.openReplay);
      expect(driver.openCount, 1);
      expect(driver.pressed, ['U', 'U']);
      expect(delays, [const Duration(milliseconds: 800)]);

      await input.perform(ReplayMenuAction.exitToReplayList);
      expect(driver.pressed, ['U', 'U', 'U']);

      await expectLater(
        input.perform(ReplayMenuAction.selectNextReplay),
        throwsA(isA<StateError>()),
      );
      expect(driver.closeCount, 1);
      expect(
        () => validateWindowsKey('A;rm'),
        throwsA(_windowsCode(WindowsNativeErrorCode.invalidKey)),
      );
    });

    test('releases a key when the hold operation fails', () async {
      final api = _FakeWindowsKeyboardNativeApi()..failOnKeyUp = true;
      final driver = WindowsSendInputDriver(
        api: api,
        keyHold: Duration.zero,
      );

      await driver.open();
      await expectLater(
        driver.press('U'),
        throwsA(_windowsCode(WindowsNativeErrorCode.inputUnavailable)),
      );
      expect(api.events, [
        const _KeyboardEvent(virtualKey: 0x55, keyDown: true),
        const _KeyboardEvent(virtualKey: 0x55, keyDown: false),
      ]);
      expect(api.inputSizes, [windowsInputSize, windowsInputSize]);
      expect(windowsInputSize, 40);
    });

    test('rejects incomplete configurable mappings', () {
      expect(
        () => WindowsMenuInputMapping(
          sequences: <ReplayMenuAction, Iterable<String>>{
            ReplayMenuAction.openReplay: const <String>[],
          },
        ),
        throwsA(_windowsCode(WindowsNativeErrorCode.invalidKey)),
      );
    });
  });

  group('Windows virtual controller', () {
    test('maps replay actions to position-neutral controller buttons', () {
      final mapping = WindowsVirtualControllerMapping();

      expect(mapping.sequenceFor(ReplayMenuAction.openReplay), [
        WindowsControllerButton.south,
        WindowsControllerButton.south,
      ]);
      expect(
        mapping.sequenceFor(ReplayMenuAction.exitToReplayList),
        [WindowsControllerButton.south],
      );
      expect(
        mapping.sequenceFor(ReplayMenuAction.selectNextReplay),
        [WindowsControllerButton.dpadUp],
      );
    });

    test('presses, releases, waits, and removes the virtual controller',
        () async {
      final driver = _FakeWindowsVirtualControllerDriver();
      final delays = <Duration>[];
      final input = WindowsVirtualControllerMenuInput(
        driver: driver,
        delay: (duration) async => delays.add(duration),
      );

      await input.perform(ReplayMenuAction.openReplay);
      expect(driver.openCount, 1);
      expect(driver.states, [
        WindowsControllerButton.south,
        0,
        WindowsControllerButton.south,
        0,
      ]);
      expect(delays, [
        const Duration(milliseconds: 80),
        const Duration(milliseconds: 800),
        const Duration(milliseconds: 80),
      ]);

      await input.close();
      expect(driver.closeCount, 1);
    });

    test('releases the button and closes after an input failure', () async {
      final driver = _FakeWindowsVirtualControllerDriver();
      final input = WindowsVirtualControllerMenuInput(
        driver: driver,
        delay: (_) async => throw StateError('synthetic delay failure'),
      );

      await expectLater(
        input.perform(ReplayMenuAction.exitToReplayList),
        throwsA(isA<StateError>()),
      );
      expect(driver.states, [WindowsControllerButton.south, 0]);
      expect(driver.closeCount, 1);
    });

    test('reports a missing virtual-controller bus distinctly', () {
      final readiness = WindowsVirtualControllerReadinessProbe(
        api: _FakeWindowsControllerApi(
          probeResult: windowsControllerBusNotFound,
        ),
        platformIsWindows: true,
      ).inspect();

      expect(readiness.ready, isFalse);
      expect(readiness.code, WindowsNativeErrorCode.controllerDriverMissing);
      expect(
          readiness.detail, contains('Install the ViGEmBus driver manually'));
    });

    test('drives and destroys the native virtual-controller handle', () async {
      final api = _FakeWindowsControllerApi(createResultAddress: 42);
      final driver = WindowsViGEmControllerDriver(api: api);

      await driver.open();
      await driver.setButtons(WindowsControllerButton.south);
      await driver.close();

      expect(api.updates, [WindowsControllerButton.south]);
      expect(api.destroyCount, 1);
    });

    test('surfaces the native create failure instead of falling back',
        () async {
      final driver = WindowsViGEmControllerDriver(
        api: _FakeWindowsControllerApi(
          createResultAddress: 0,
          lastErrorResult: windowsControllerBusNotFound,
        ),
      );

      await expectLater(
        driver.open(),
        throwsA(_windowsCode(WindowsNativeErrorCode.controllerDriverMissing)),
      );
    });
  });

  group('Windows native backend', () {
    test('opens controller mode without consuming the physical controller',
        () async {
      final nativeApi = _FakeWindowsControllerApi();
      final driver = _FakeWindowsVirtualControllerDriver();
      final backend = WindowsNativeRecorderBackend(
        platformIsWindows: true,
        memoryFactory: (_) => _FakeWindowsMemorySession.withGWorldSignature(),
        controllerProbe: WindowsVirtualControllerReadinessProbe(
          api: nativeApi,
          platformIsWindows: true,
        ),
        controllerDriverFactory: () => driver,
      );

      final input = await backend.openMenuInput(InputMode.virtualController);
      expect(input, isA<WindowsVirtualControllerMenuInput>());
      await input.perform(ReplayMenuAction.selectNextReplay);
      expect(
        driver.states,
        [WindowsControllerButton.dpadUp, 0],
      );
    });

    test('assembles monitor, keyboard, OBS, and output ports', () async {
      final fakeObs = _FakeObsRecorder();
      final backend = WindowsNativeRecorderBackend(
        platformIsWindows: true,
        obsConfig: const ObsWebSocketConfig(port: 4455),
        obsRecorderFactory: (_) => fakeObs,
        memoryFactory: (_) => _FakeWindowsMemorySession.withGWorldSignature(),
        keyboardDriverFactory: _FakeWindowsKeyboardDriver.new,
      );

      expect(await backend.openReplayMonitor(), isA<WindowsReplayMonitor>());
      expect(
        await backend.openMenuInput(InputMode.keyboard),
        isA<WindowsKeyboardMenuInput>(),
      );
      expect(await backend.openObsRecorder(), same(fakeObs));
      expect(
        await backend.openOutputOrganizer(),
        isA<FileOutputOrganizer>(),
      );
    });

    test('input readiness does not depend on replay monitor attachment',
        () async {
      final backend = WindowsNativeRecorderBackend(
        platformIsWindows: true,
        memoryFactory: (_) => throw const WindowsNativeException(
          WindowsNativeErrorCode.processMemoryDenied,
          'memory monitor unavailable',
        ),
        keyboardDriverFactory: _FakeWindowsKeyboardDriver.new,
      );

      final readiness = await backend.inspectForInput(InputMode.keyboard);

      expect(readiness.available, isTrue);
      expect(readiness.detail, isNot(contains('memory monitor unavailable')));
    });

    test('reports controller mode ready when the bus probe connects', () async {
      final backend = WindowsNativeRecorderBackend(
        platformIsWindows: true,
        memoryFactory: (_) => _FakeWindowsMemorySession.withGWorldSignature(),
        controllerProbe: WindowsVirtualControllerReadinessProbe(
          api: _FakeWindowsControllerApi(),
          platformIsWindows: true,
        ),
      );

      final report = await backend.inspectDetailed(
        inputMode: InputMode.virtualController,
      );

      expect(report.ready, isTrue);
      expect(report.blockingChecks, isEmpty);
    });
  });
}

Matcher _windowsCode(WindowsNativeErrorCode code) =>
    isA<WindowsNativeException>().having(
      (error) => error.code,
      'code',
      code,
    );

class _FakeWindowsApi implements WindowsNativeApi {
  _FakeWindowsApi({required this.module});

  final WindowsModule module;
  final handle = Pointer<Void>.fromAddress(0x1234);
  final bytes = <int, int>{};
  final closedHandles = <Pointer<Void>>[];

  @override
  int findProcessId(String processName) => 42;

  @override
  Pointer<Void> openProcess(int processId) => handle;

  @override
  WindowsModule moduleFromName(
    Pointer<Void> processHandle,
    int processId,
    String moduleName,
  ) =>
      module;

  @override
  List<WindowsMemoryRegion> readableMemoryRegions(
    Pointer<Void> processHandle,
    WindowsModule module,
  ) =>
      <WindowsMemoryRegion>[
        WindowsMemoryRegion(
          baseAddress: module.baseAddress,
          size: module.sizeOfImage,
        ),
      ];

  @override
  List<int> readProcessMemory(
    Pointer<Void> processHandle,
    int address,
    int length,
  ) =>
      List<int>.generate(length, (index) => bytes[address + index] ?? 0);

  @override
  void closeHandle(Pointer<Void> handle) => closedHandles.add(handle);
}

class _FakeWindowsMemorySession implements WindowsMemorySession {
  _FakeWindowsMemorySession() : module = _defaultModule;

  static const WindowsModule _defaultModule = WindowsModule(
    name: ggstWindowsExecutable,
    baseAddress: 0x1000,
    sizeOfImage: 0x1000,
  );

  factory _FakeWindowsMemorySession.withGWorldSignature() {
    final fake = _FakeWindowsMemorySession();
    fake._writeBytes(0x1020, <int>[
      0x0F,
      0x2E,
      0xAA,
      0x74,
      0x11,
      0x48,
      0x8B,
      0x1D,
      0xD4,
      0x00,
      0x00,
      0x00,
      0x48,
      0x85,
      0xDB,
      0x74,
    ]);
    fake._writePointer(0x1100, 0x2000);
    fake._writePointer(0x2130, 0x3000);
    fake._writePointer(0x3C38, 0x4000);
    fake._writeUint32(0x7E7C, 1234);
    fake._writePointer(0x3C58, 0x5000);
    fake._writeUint32(0x50A8, 2);
    fake._writeUint32(0x5008, 15);
    fake._writeUint32(0x5018, 7);
    return fake;
  }

  final WindowsModule module;
  final bytes = <int, int>{};
  bool closed = false;
  bool throwOnPatternReads = false;
  bool throwOnSnapshotReads = false;
  WindowsNativeErrorCode? snapshotFailure;

  @override
  int get processId => 42;

  @override
  WindowsModule moduleFromName(String moduleName) => module;

  @override
  List<WindowsMemoryRegion> readableMemoryRegions(WindowsModule module) =>
      <WindowsMemoryRegion>[
        WindowsMemoryRegion(
          baseAddress: module.baseAddress,
          size: module.sizeOfImage,
        ),
      ];

  @override
  List<int> readBytes(int address, int length) {
    if (throwOnPatternReads && address == module.baseAddress) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.processMemoryDenied,
        'denied',
      );
    }
    if (throwOnSnapshotReads) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.memoryReadFailed,
        'sample unavailable',
      );
    }
    final failure = snapshotFailure;
    if (failure != null) {
      throw WindowsNativeException(failure, 'sample failed');
    }
    return List<int>.generate(length, (index) => bytes[address + index] ?? 0);
  }

  @override
  void close() {
    closed = true;
  }

  void _writeBytes(int address, List<int> values) {
    for (var index = 0; index < values.length; index++) {
      bytes[address + index] = values[index];
    }
  }

  void _writePointer(int address, int value) {
    _writeBytes(
        address, List<int>.generate(8, (index) => value >> (index * 8) & 0xFF));
  }

  void _writeUint32(int address, int value) {
    _writeBytes(
        address, List<int>.generate(4, (index) => value >> (index * 8) & 0xFF));
  }
}

class _FakeWindowsKeyboardDriver implements WindowsKeyboardDriver {
  final pressed = <String>[];
  String? failOnPress;
  int openCount = 0;
  int closeCount = 0;

  @override
  Future<void> open() async {
    openCount++;
  }

  @override
  Future<void> press(String key) async {
    if (key == failOnPress) {
      throw StateError('synthetic key failure');
    }
    pressed.add(key);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class _FakeWindowsVirtualControllerDriver
    implements WindowsVirtualControllerDriver {
  int openCount = 0;
  int closeCount = 0;
  final List<int> states = <int>[];

  @override
  Future<void> open() async {
    openCount++;
  }

  @override
  Future<void> setButtons(int buttons) async {
    states.add(buttons);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class _FakeWindowsControllerApi implements WindowsVirtualControllerNativeApi {
  _FakeWindowsControllerApi({
    this.probeResult = windowsControllerSuccess,
    this.createResultAddress = 1,
    this.lastErrorResult = windowsControllerBusNotFound,
  });

  final int probeResult;
  final int createResultAddress;
  final int lastErrorResult;
  final List<int> updates = <int>[];
  int destroyCount = 0;

  @override
  int probe() => probeResult;

  @override
  Pointer<Void> create() => Pointer<Void>.fromAddress(createResultAddress);

  @override
  int lastError() => lastErrorResult;

  @override
  int update(Pointer<Void> controller, int buttons) {
    updates.add(buttons);
    return windowsControllerSuccess;
  }

  @override
  int destroy(Pointer<Void> controller) {
    destroyCount++;
    return windowsControllerSuccess;
  }
}

class _KeyboardEvent {
  const _KeyboardEvent({required this.virtualKey, required this.keyDown});

  final int virtualKey;
  final bool keyDown;

  @override
  bool operator ==(Object other) =>
      other is _KeyboardEvent &&
      other.virtualKey == virtualKey &&
      other.keyDown == keyDown;

  @override
  int get hashCode => Object.hash(virtualKey, keyDown);
}

class _FakeWindowsKeyboardNativeApi implements WindowsKeyboardNativeApi {
  final events = <_KeyboardEvent>[];
  final inputSizes = <int>[];
  bool failOnKeyUp = false;

  @override
  void open() {}

  @override
  void sendKey(
    int virtualKey, {
    required bool keyDown,
    required int inputSize,
  }) {
    inputSizes.add(inputSize);
    events.add(_KeyboardEvent(virtualKey: virtualKey, keyDown: keyDown));
    if (!keyDown && failOnKeyUp) {
      throw const WindowsNativeException(
        WindowsNativeErrorCode.inputUnavailable,
        'key-up failed',
      );
    }
  }

  @override
  void close() {}
}

class _FakeObsRecorder implements ObsRecorderPort {
  @override
  Future<void> assertIdle() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<RecordedOutput> stopRecording() async =>
      const RecordedOutput('recording.mp4');
}
