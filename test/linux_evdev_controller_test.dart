import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/services/linux_evdev_controller.dart';
import 'package:afterimage/services/linux_process_memory.dart';

void main() {
  group('Linux evdev bitmap parsing', () {
    test('checks bits in most-significant-word-first procfs bitmaps', () {
      expect(
        linuxProcBitmapHasBit(
          '7cdb000000000000 0 0 0 0',
          LinuxEvdevEventCode.btnSouth,
        ),
        isTrue,
      );
      expect(
        linuxProcBitmapHasBit(
          '7cdb000000000000 0 0 0 0',
          0x220,
        ),
        isFalse,
      );
      expect(
        linuxProcBitmapHasBit(
          '0000000000030000',
          LinuxEvdevEventCode.absHat0Y,
        ),
        isTrue,
      );
      expect(linuxProcBitmapHasBit('0000000000000001', 64), isFalse);
      expect(linuxProcBitmapHasBit('not-a-bitmap', 0), isFalse);
    });

    test('checks bits in full-width procfs words with the top bit set', () {
      expect(
        linuxProcBitmapHasBit('8000000000000000', 63),
        isTrue,
      );
      expect(
        linuxProcBitmapHasBit('8000000000000000', 62),
        isFalse,
      );
      for (var bit = 0; bit < 64; bit++) {
        expect(
          linuxProcBitmapHasBit('ffffffffffffffff', bit),
          isTrue,
          reason: 'bit $bit should be set',
        );
      }
    });

    test('parses event handlers and identifies only controller records', () {
      final devices = parseLinuxInputDevices(
        _inputDevice(eventNumber: 2, vendor: '045e', product: '028e') +
            _inputDevice(
              eventNumber: 24,
              vendor: '28de',
              product: '11ff',
              keyBitmap: '0 0 0 0 0',
            ),
      );

      expect(devices, hasLength(2));
      expect(devices.first.eventNumbers, [2]);
      expect(devices.first.vendorProduct, '0x045e/0x028e');
      expect(devices.first.isGamepad, isTrue);
      expect(devices.last.isGamepad, isFalse);
    });
  });

  group('Linux evdev controller discovery', () {
    test(
      'chooses the Wine-held gamepad instead of the Steam-held physical pad',
      () {
        final proc = _controllerProc();
        final discovery = LinuxEvdevControllerDiscovery(procFileSystem: proc);

        final node = discovery.discover();

        expect(node.path, '/dev/input/event24');
        expect(node.vendorProduct, '0x28de/0x11ff');
      },
      skip: !Platform.isLinux,
    );

    test(
      'matches GGST through its truncated comm name',
      () {
        final proc = _controllerProc(
          commandLine: 'wine-preloader\u0000',
          comm: 'GGST-Win64-Ship\u0000',
        );
        final node =
            LinuxEvdevControllerDiscovery(procFileSystem: proc).discover();

        expect(node.eventNumber, 24);
      },
      skip: !Platform.isLinux,
    );

    test(
      'rejects a single Wine-held candidate in the SDL ignore list',
      () {
        final proc = _controllerProc(
          inputDevices: _inputDevice(
            eventNumber: 24,
            vendor: '045e',
            product: '028e',
          ),
          ignoredDevices: '0x045e/0x028e',
        );

        expect(
          () => LinuxEvdevControllerDiscovery(procFileSystem: proc).discover(),
          throwsA(_evdevCode(LinuxEvdevErrorCode.controllerNotReading)),
        );
      },
      skip: !Platform.isLinux,
    );

    test(
      'rejects ambiguity after ignoring no matching vendor-product',
      () {
        final proc = _controllerProc(
          includeSecondWineController: true,
          ignoredDevices: '0x045e/0x028e',
        );

        expect(
          () => LinuxEvdevControllerDiscovery(procFileSystem: proc).discover(),
          throwsA(
            isA<LinuxEvdevException>()
                .having(
                  (error) => error.code,
                  'code',
                  LinuxEvdevErrorCode.ambiguousController,
                )
                .having(
                    (error) => error.message,
                    'message',
                    allOf(
                      contains('/dev/input/event24'),
                      contains('/dev/input/event25'),
                      contains('0x28de/0x11ff'),
                      contains('Disconnect'),
                      contains('refresh setup checks'),
                    )),
          ),
        );
      },
      skip: !Platform.isLinux,
    );

    test(
      'reports distinct absent-game, prefix, and controller failures',
      () {
        final absent = LinuxEvdevControllerDiscovery(
          procFileSystem: _FakeProcFileSystem(const {}),
        );
        expect(
          () => absent.discover(),
          throwsA(_evdevCode(LinuxEvdevErrorCode.gameAbsent)),
        );

        final prefixUnknown = LinuxEvdevControllerDiscovery(
          procFileSystem: _FakeProcFileSystem({
            42: {
              'cmdline': utf8.encode('GGST-Win64-Shipping.exe\u0000'),
              'comm': utf8.encode('GGST-Win64-Ship\u0000'),
              'environ': utf8.encode('HOME=/tmp\u0000'),
            },
          }),
        );
        expect(
          () => prefixUnknown.discover(),
          throwsA(_evdevCode(LinuxEvdevErrorCode.winePrefixUnknown)),
        );

        final noController = LinuxEvdevControllerDiscovery(
          procFileSystem: _controllerProc(inputDevices: ''),
        );
        expect(
          () => noController.discover(),
          throwsA(_evdevCode(LinuxEvdevErrorCode.controllerNotReading)),
        );
      },
      skip: !Platform.isLinux,
    );
  });

  group('Linux evdev input port', () {
    test(
      'next replay emits ABS_HAT0Y -1 then 0 on the discovered node',
      () async {
        final device = _FakeEvdevDevice();
        final factory = _FakeEvdevFactory(device);
        final delays = <Duration>[];
        final input = LinuxEvdevMenuInput(
          discovery: LinuxEvdevControllerDiscovery(
            procFileSystem: _controllerProc(),
          ),
          factory: factory,
          delay: (duration) async => delays.add(duration),
        );

        await input.perform(ReplayMenuAction.selectNextReplay);

        expect(factory.openedPaths, ['/dev/input/event24']);
        expect(_decodeEvents(device.writes), [
          _event(LinuxEvdevEventType.abs, LinuxEvdevEventCode.absHat0Y, -1),
          _event(LinuxEvdevEventType.syn, LinuxEvdevEventCode.syn, 0),
          _event(LinuxEvdevEventType.abs, LinuxEvdevEventCode.absHat0Y, 0),
          _event(LinuxEvdevEventType.syn, LinuxEvdevEventCode.syn, 0),
        ]);
        expect(delays, [const Duration(milliseconds: 80)]);
      },
      skip: !Platform.isLinux,
    );

    test(
      'maps confirm taps and keeps the delay seam injectable',
      () async {
        final device = _FakeEvdevDevice();
        final delays = <Duration>[];
        final input = LinuxEvdevMenuInput(
          discovery: LinuxEvdevControllerDiscovery(
            procFileSystem: _controllerProc(),
          ),
          factory: _FakeEvdevFactory(device),
          delay: (duration) async => delays.add(duration),
        );

        await input.perform(ReplayMenuAction.openReplay);

        expect(_decodeEvents(device.writes), [
          _event(LinuxEvdevEventType.key, LinuxEvdevEventCode.btnSouth, 1),
          _event(LinuxEvdevEventType.syn, LinuxEvdevEventCode.syn, 0),
          _event(LinuxEvdevEventType.key, LinuxEvdevEventCode.btnSouth, 0),
          _event(LinuxEvdevEventType.syn, LinuxEvdevEventCode.syn, 0),
          _event(LinuxEvdevEventType.key, LinuxEvdevEventCode.btnSouth, 1),
          _event(LinuxEvdevEventType.syn, LinuxEvdevEventCode.syn, 0),
          _event(LinuxEvdevEventType.key, LinuxEvdevEventCode.btnSouth, 0),
          _event(LinuxEvdevEventType.syn, LinuxEvdevEventCode.syn, 0),
        ]);
        expect(delays, [
          const Duration(milliseconds: 80),
          const Duration(milliseconds: 800),
          const Duration(milliseconds: 80),
        ]);
      },
      skip: !Platform.isLinux,
    );

    test(
      'neutralises the button and hat before closing after a failure',
      () async {
        final device = _FakeEvdevDevice();
        final input = LinuxEvdevMenuInput(
          discovery: LinuxEvdevControllerDiscovery(
            procFileSystem: _controllerProc(),
          ),
          factory: _FakeEvdevFactory(device),
          delay: (_) async => throw StateError('injected delay failure'),
        );

        await expectLater(
          input.perform(ReplayMenuAction.selectNextReplay),
          throwsA(isA<StateError>()),
        );

        expect(device.closed, isTrue);
        expect(_decodeEvents(device.writes).sublist(device.writes.length - 4), [
          _event(LinuxEvdevEventType.key, LinuxEvdevEventCode.btnSouth, 0),
          _event(LinuxEvdevEventType.syn, LinuxEvdevEventCode.syn, 0),
          _event(LinuxEvdevEventType.abs, LinuxEvdevEventCode.absHat0Y, 0),
          _event(LinuxEvdevEventType.syn, LinuxEvdevEventCode.syn, 0),
        ]);
      },
      skip: !Platform.isLinux,
    );

    test(
      'reports a neutralisation write failure while preserving the action error',
      () async {
        final device = _FakeEvdevDevice(failOnWrite: 3);
        final actionFailure = StateError('injected delay failure');
        final input = LinuxEvdevMenuInput(
          discovery: LinuxEvdevControllerDiscovery(
            procFileSystem: _controllerProc(),
          ),
          factory: _FakeEvdevFactory(device),
          delay: (_) async => throw actionFailure,
        );

        await expectLater(
          input.perform(ReplayMenuAction.selectNextReplay),
          throwsA(
            isA<LinuxEvdevException>()
                .having(
                    (error) => error.message,
                    'message',
                    allOf(
                      contains('injected delay failure'),
                      contains(
                        'could not be returned to a neutral state',
                      ),
                      contains('may still be holding an input'),
                    ))
                .having((error) => error.cause, 'cause', same(actionFailure)),
          ),
        );

        expect(device.closed, isTrue);
      },
      skip: !Platform.isLinux,
    );

    test(
      'keeps the tap action error when release also fails',
      () async {
        final device = _FakeEvdevDevice(failOnWrite: 3);
        final actionFailure = StateError('injected delay failure');
        final input = LinuxEvdevMenuInput(
          discovery: LinuxEvdevControllerDiscovery(
            procFileSystem: _controllerProc(),
          ),
          factory: _FakeEvdevFactory(device),
          delay: (_) async => throw actionFailure,
        );

        await expectLater(
          input.perform(ReplayMenuAction.exitToReplayList),
          throwsA(
            isA<LinuxEvdevException>()
                .having(
                    (error) => error.message,
                    'message',
                    allOf(
                      contains('injected delay failure'),
                      contains('injected write failure'),
                    ))
                .having((error) => error.cause, 'cause', same(actionFailure)),
          ),
        );

        expect(device.closed, isTrue);
      },
      skip: !Platform.isLinux,
    );

    test(
      'reports both neutralisation and close failures',
      () async {
        const closeFailure = LinuxEvdevException(
          LinuxEvdevErrorCode.closeFailed,
          'injected close failure',
        );
        final device = _FakeEvdevDevice(
          failOnWrite: 5,
          closeFailure: closeFailure,
        );
        final input = LinuxEvdevMenuInput(
          discovery: LinuxEvdevControllerDiscovery(
            procFileSystem: _controllerProc(),
          ),
          factory: _FakeEvdevFactory(device),
          delay: (_) async {},
        );

        await input.perform(ReplayMenuAction.exitToReplayList);

        await expectLater(
          input.close(),
          throwsA(
            isA<LinuxEvdevException>()
                .having(
                    (error) => error.message,
                    'message',
                    allOf(
                      contains('injected write failure'),
                      contains('injected close failure'),
                    ))
                .having((error) => error.cause, 'cause', same(closeFailure)),
          ),
        );

        expect(device.closed, isTrue);
      },
      skip: !Platform.isLinux,
    );
  });

  group('Linux evdev readiness', () {
    test(
      'reports a discovered node that cannot be opened as not writable',
      () {
        final discovery = LinuxEvdevControllerDiscovery(
          procFileSystem: _controllerProc(),
        );
        final readiness = LinuxEvdevReadinessProbe(
          discovery: discovery,
          factory: _FakeEvdevFactory(
            _FakeEvdevDevice(),
            openFailure: const LinuxEvdevException(
              LinuxEvdevErrorCode.nodeNotWritable,
              'permission denied',
            ),
          ),
        ).inspect();

        expect(readiness.ready, isFalse);
        expect(readiness.code, LinuxEvdevErrorCode.nodeNotWritable);
        expect(readiness.detail, contains('/dev/input/event24'));
      },
      skip: !Platform.isLinux,
    );
  });
}

Matcher _evdevCode(LinuxEvdevErrorCode code) =>
    isA<LinuxEvdevException>().having((error) => error.code, 'code', code);

String _inputDevice({
  required int eventNumber,
  required String vendor,
  required String product,
  String name = 'Microsoft X-Box 360 pad',
  String keyBitmap = '7cdb000000000000 0 0 0 0',
  String absBitmap = '0000000000030000',
}) {
  return '''I: Bus=0003 Vendor=$vendor Product=$product Version=0114
N: Name="$name"
H: Handlers=event$eventNumber js0
B: KEY=$keyBitmap
B: ABS=$absBitmap

''';
}

_FakeProcFileSystem _controllerProc({
  String commandLine = '/games/GGST-Win64-Shipping.exe\u0000',
  String comm = 'wine-preloader\u0000',
  String ignoredDevices = '0x045e/0x028e',
  String? inputDevices,
  bool includeSecondWineController = false,
}) {
  const prefix = '/home/suji/Games/steamapps/compatdata/1384160/pfx';
  final files = <int, Map<String, List<int>>>{
    42: {
      'cmdline': utf8.encode(commandLine),
      'comm': utf8.encode(comm),
      'environ': utf8.encode(
        'WINEPREFIX=$prefix/\u0000SDL_GAMECONTROLLER_IGNORE_DEVICES=$ignoredDevices\u0000',
      ),
    },
    100: {
      'cmdline': utf8.encode('steam\u0000'),
      'comm': utf8.encode('steam\u0000'),
      'environ': utf8.encode('WINEPREFIX=/other/prefix\u0000'),
    },
    43: {
      'cmdline': utf8.encode('winedevice.exe\u0000'),
      'comm': utf8.encode('winedevice.exe\u0000'),
      'environ': utf8.encode('WINEPREFIX=$prefix\u0000'),
    },
  };
  final fdTargets = <int, List<String>>{
    100: ['/dev/input/event2'],
    43: ['/dev/input/event24'],
  };
  var devices = _inputDevice(
    eventNumber: 2,
    vendor: '045e',
    product: '028e',
  );
  devices += _inputDevice(
    eventNumber: 24,
    vendor: '28de',
    product: '11ff',
    name: 'Microsoft X-Box 360 pad 0',
  );
  if (includeSecondWineController) {
    files[44] = {
      'cmdline': utf8.encode('winedevice-helper.exe\u0000'),
      'comm': utf8.encode('winedevice-helper.exe\u0000'),
      'environ': utf8.encode('WINEPREFIX=$prefix\u0000'),
    };
    fdTargets[44] = ['/dev/input/event25'];
    devices += _inputDevice(
      eventNumber: 25,
      vendor: '28de',
      product: '11ff',
      name: 'Microsoft X-Box 360 pad 1',
    );
  }
  return _FakeProcFileSystem(
    files,
    fdTargetsByProcess: fdTargets,
    inputDevices: inputDevices ?? devices,
  );
}

class _FakeProcFileSystem implements LinuxProcFileSystem {
  _FakeProcFileSystem(
    this.files, {
    this.fdTargetsByProcess = const <int, List<String>>{},
    this.inputDevices = '',
  });

  final Map<int, Map<String, List<int>>> files;
  final Map<int, List<String>> fdTargetsByProcess;
  final String inputDevices;

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

  @override
  Iterable<String> fdTargets(int processId) =>
      fdTargetsByProcess[processId] ?? const <String>[];

  @override
  String readInputDevices() => inputDevices;
}

class _FakeEvdevFactory implements LinuxEvdevDeviceFactory {
  _FakeEvdevFactory(
    this.device, {
    this.openFailure,
  });

  final _FakeEvdevDevice device;
  final LinuxEvdevException? openFailure;
  final List<String> openedPaths = <String>[];

  @override
  LinuxEvdevDevicePort open(String path) {
    openedPaths.add(path);
    if (openFailure != null) {
      throw openFailure!;
    }
    return device;
  }
}

class _FakeEvdevDevice implements LinuxEvdevDevicePort {
  _FakeEvdevDevice({this.failOnWrite, this.closeFailure});

  final List<List<int>> writes = <List<int>>[];
  final int? failOnWrite;
  final Object? closeFailure;
  bool closed = false;
  int _writeCount = 0;

  @override
  void write(List<int> bytes) {
    _writeCount++;
    if (_writeCount == failOnWrite) {
      throw const LinuxEvdevException(
        LinuxEvdevErrorCode.writeFailed,
        'injected write failure',
      );
    }
    writes.add(List<int>.from(bytes));
  }

  @override
  void close() {
    closed = true;
    if (closeFailure != null) {
      throw closeFailure!;
    }
  }
}

List<_DecodedEvent> _decodeEvents(List<List<int>> writes) {
  final offset = sizeOf<IntPtr>() * 2;
  return [
    for (final bytes in writes)
      () {
        final data = ByteData.sublistView(Uint8List.fromList(bytes));
        return _DecodedEvent(
          data.getUint16(offset, Endian.host),
          data.getUint16(offset + 2, Endian.host),
          data.getInt32(offset + 4, Endian.host),
        );
      }(),
  ];
}

_DecodedEvent _event(int type, int code, int value) =>
    _DecodedEvent(type, code, value);

class _DecodedEvent {
  const _DecodedEvent(this.type, this.code, this.value);

  final int type;
  final int code;
  final int value;

  @override
  bool operator ==(Object other) =>
      other is _DecodedEvent &&
      other.type == type &&
      other.code == code &&
      other.value == value;

  @override
  int get hashCode => Object.hash(type, code, value);

  @override
  String toString() => '$type/$code/$value';
}
