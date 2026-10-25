import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/app/afterimage_version.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/services/linux_frame_capture.dart';
import 'package:afterimage/services/linux_process_memory.dart';

void main() {
  group('decodeLinuxFrameRow', () {
    test('decodes player fields, inputs, boxes, and entity ownership', () {
      final memory = _frameMemory(entityCount: 3);
      _writePlayer(
        memory,
        _player1,
        sprite: 'kyk203_04',
        bbsCommand: _bbs1,
        bbsOpcode: 0,
        bbsName: 'NmlAtk5CNear',
        action: -55,
        actionTime: 6,
        hitstop: 3,
        hp: 420,
        w1b0: 0x4000000,
        enable: 0x1000,
        attack: 9,
        blockstun: -4,
        hitstun: 2,
        x: -12345,
        y: 67890,
        facing: 1,
        flags: 0x101,
        invuln: 0x30,
        landed: 0x20,
        strikeInvuln: -10,
        throwInvuln: 11,
        throwRange: 12,
        slowdown: -13,
        scaleX: 1400,
        scaleY: 900,
        hitboxes: _boxes1,
        boxCounts: {0: 1, 1: 1, 2: 2, 18: 1},
      );
      _writePlayer(
        memory,
        _player2,
        sprite: 'sol203_02',
        bbsCommand: _bbs2,
        bbsOpcode: 5,
        bbsName: 'ignored',
        action: 31,
        actionTime: 7,
        hitstop: 8,
        hp: 92,
        w1b0: 0,
        enable: 3,
        attack: 4,
        blockstun: 5,
        hitstun: 6,
        x: 700,
        y: -800,
        facing: 0,
        flags: 7,
        invuln: 8,
        landed: 9,
        strikeInvuln: 10,
        throwInvuln: 11,
        throwRange: 12,
        slowdown: 13,
        scaleX: 1000,
        scaleY: 1000,
        hitboxes: 0,
        boxCounts: const {},
      );
      memory
        ..putInt32(_bbs1, 0)
        ..putString(_bbs1 + 4, 'NmlAtk5CNear', 32)
        ..putInt32(_bbs2, 5)
        ..putString(_bbs2 + 4, 'ignored', 32)
        ..putUint16(_engine + 0x3868 + 0x2, 0x1ff)
        ..putUint16(_engine + 0x3868 + 0x80 + 0x2, 0x12)
        ..putPointer(_engine + 0xC80, _entity1)
        ..putPointer(_engine + 0xC80 + 8, _entity2)
        ..putPointer(_engine + 0xC80 + 16, _entity3);
      _writeEntity(memory, _entity1, parent: _bridge1, boxes: 0);
      _writeEntity(memory, _entity2, parent: _bridge2, boxes: 0);
      _writeEntity(memory, _entity3, parent: _bridge3, boxes: 0);
      memory
        ..putPointer(_bridge1 + 0x2C0, _player1)
        ..putPointer(_bridge2 + 0x2C0, _player2)
        ..putPointer(_bridge3 + 0x2C0, 0);

      final read = decodeLinuxFrameRow(
        memory: memory,
        gWorldPointerAddress: _gWorld,
        expectedFrame: 1234,
        elapsedMicros: 16683,
      );

      expect(read.torn, isFalse);
      final row = read.row!;
      expect(row['type'], 'frame');
      expect(row['f'], 1234);
      expect(row['t'], 16683);
      expect(row['in'], [0x1ff, 0x12]);
      final players = row['p']! as List<Map<String, Object?>>;
      expect(players, hasLength(2));
      expect(
        players[0].containsKey('hp'),
        isTrue,
        reason: 'Player row is missing the hp key.',
      );
      expect(players[0]['hp'], 420);
      expect(players[0], {
        'spr': 'kyk203_04',
        'bbs': 'NmlAtk5CNear',
        'act': -55,
        'at': 6,
        'hs': 3,
        'hp': 420,
        'w1b0': 0x4000000,
        'en': 0x1000,
        'atk': 9,
        'bs': -4,
        'hst': 2,
        'x': -12345,
        'y': 67890,
        'fc': 1,
        'w398': 0x101,
        'w39c': 0x30,
        'w3a0': 0x20,
        'sivt': -10,
        'tivt': 11,
        'thr': 12,
        'slow': -13,
        'sx': 1400,
        'sy': 900,
        'bx': [
          [0, 1.234, -2.987, 3.141, 4.111],
          [1, 5.5, 6.5, 7.5, 8.5],
          [18, 9.5, 10.5, 11.5, 12.5],
        ],
      });
      expect(players[1]['spr'], 'sol203_02');
      expect(players[1]['bbs'], isNull,
          reason: 'Only begin_state opcode zero has a state name.');
      expect(players[1]['act'], 31);

      final entities = row['e']! as List<Map<String, Object?>>;
      expect(entities, hasLength(3));
      expect(entities[0]['id'], '0x$_entity1Hex');
      expect(entities[0]['own'], 0);
      expect(entities[0].containsKey('hp'), isFalse);
      expect(entities[1]['own'], 1);
      expect(entities[2]['own'], isNull, reason: 'Orphans have no owner.');
    });

    test('invalid box counts reject the whole box list', () {
      for (final invalid in [-1, 1001]) {
        final memory = _frameMemory();
        memory
          ..putPointer(_player1 + 0x78, _boxes1)
          ..putInt32(_player1 + 0x114, invalid);

        final row = decodeLinuxFrameRow(
          memory: memory,
          gWorldPointerAddress: _gWorld,
          expectedFrame: 1234,
          elapsedMicros: 1,
        ).row!;

        expect((row['p']! as List<Map<String, Object?>>).first['bx'], isNull);
      }
    });

    test('entity_count is clamped to 107 entries', () {
      final memory = _frameMemory(entityCount: 200);
      memory
        ..putPointer(_engine + 0xC80 + 106 * 8, _entity1)
        ..putPointer(_entity1 + 0x2C0, _player1);
      _writeEntity(memory, _entity1, parent: _player1, boxes: 0);

      final row = decodeLinuxFrameRow(
        memory: memory,
        gWorldPointerAddress: _gWorld,
        expectedFrame: 1234,
        elapsedMicros: 1,
      ).row!;

      expect(row['e'], hasLength(1));
      expect((row['e']! as List<Map<String, Object?>>).single['own'], 0);
    });

    test('a GameFrame change during decoding marks the row torn', () {
      final memory = _frameMemory()..frameReadValues = [1234, 1235];

      final read = decodeLinuxFrameRow(
        memory: memory,
        gWorldPointerAddress: _gWorld,
        expectedFrame: 1234,
        elapsedMicros: 1,
      );

      expect(read.torn, isTrue);
      expect(read.row, isNull);
    });
  });

  test('capture loop writes changed rows, rejects tears, and writes stats',
      () async {
    final time = _FakeCaptureTime(stopAfterDelays: 5);
    final source = _FakeCaptureSource(
      frames: [100, 100, 101, 102, 105],
      reads: {
        100: const LinuxFrameRowRead(row: {'type': 'frame', 'f': 100, 't': 0}),
        101: const LinuxFrameRowRead(torn: true),
        102: const LinuxFrameRowRead(row: {'type': 'frame', 'f': 102, 't': 2}),
        105: const LinuxFrameRowRead(row: {'type': 'frame', 'f': 105, 't': 3}),
      },
    );
    final sink = _FakeCaptureSink();
    final loop = LinuxFrameCaptureLoop(
      replayIndex: 2,
      source: source,
      sink: sink,
      elapsed: () => time.now,
      delay: time.delay,
      startedUtc: '2026-10-02T12:00:00Z',
      afterimageVersion: '0.2.2',
    );

    final result = await loop.run(shouldStop: () => time.stopRequested);

    expect(result.rows, 3);
    expect(result.frameGaps, 2);
    expect(result.maxFrameGap, 2);
    expect(sink.lines.map((line) => line['type']), [
      'header',
      'frame',
      'frame',
      'frame',
      'footer',
    ]);
    expect(sink.lines.first, {
      'type': 'header',
      'schema': 1,
      'replay': 2,
      'startedUtc': '2026-10-02T12:00:00Z',
      'afterimage': '0.2.2',
    });
    expect(sink.lines.last, {
      'type': 'footer',
      'end': 'completed',
      'rows': 3,
      'frameGaps': 2,
      'maxFrameGap': 2,
      'polls': 5,
      'tornRows': 1,
      'readErrors': 0,
    });
    expect(sink.flushCalls, 3,
        reason: 'The loop flushes periodically and once after its footer.');
    expect(time.requestedDelays, everyElement(const Duration(milliseconds: 1)));
  });

  test('frame capture version is tied to the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(
      pubspec,
    );

    expect(match, isNotNull);
    expect(afterimageVersion, match!.group(1));
  });

  test('capture session writes the running app version in the header',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'afterimage-frame-version-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/replay_001.frames.jsonl';
    final sink = await LinuxFrameCaptureFileSink.create(path);
    final time = _FakeCaptureTime(stopAfterDelays: 1);

    final result = await runLinuxFrameCaptureSession(
      replayIndex: 1,
      source: _FakeCaptureSource(
        frames: [100],
        reads: {
          100: const LinuxFrameRowRead(
            row: {'type': 'frame', 'f': 100, 't': 0},
          ),
        },
      ),
      sink: sink,
      elapsed: () => time.now,
      delay: time.delay,
      startedUtc: '2026-10-02T12:00:00Z',
      shouldStop: () => time.stopRequested,
      endReason: () => FrameCaptureEndReason.completed,
      outputPath: path,
    );

    expect(result.error, isNull);
    final header = jsonDecode(
      File(path).readAsLinesSync().first,
    ) as Map<String, dynamic>;
    expect(header['afterimage'], afterimageVersion);
  });

  test('capture session counts read failures without counting missing pointers',
      () async {
    final time = _FakeCaptureTime(stopAfterDelays: 2);
    final sink = _FakeCaptureSink();
    final loop = LinuxFrameCaptureLoop(
      replayIndex: 1,
      source: _ReadFailureCaptureSource(),
      sink: sink,
      elapsed: () => time.now,
      delay: time.delay,
      startedUtc: '2026-10-02T12:00:00Z',
      afterimageVersion: afterimageVersion,
    );

    final result = await loop.run(
      shouldStop: () => time.stopRequested,
      endReason: () => FrameCaptureEndReason.stopped,
    );

    expect(result.rows, 0);
    expect(result.readErrors, 2);
    expect(sink.lines.last, {
      'type': 'footer',
      'end': 'stopped',
      'rows': 0,
      'frameGaps': 0,
      'maxFrameGap': 0,
      'polls': 2,
      'tornRows': 0,
      'readErrors': 2,
    });
  });

  test('a done response wins over the later isolate exit notification', () {
    final tracker = LinuxFrameCaptureExitTracker()..markDone();

    expect(tracker.exitIsUnexpected(), isFalse);
  });

  test('capture failure keeps the partial file and reports its path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'afterimage-frame-failure-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/replay_001.frames.jsonl';
    final sink = await LinuxFrameCaptureFileSink.create(path);

    final result = await runLinuxFrameCaptureSession(
      replayIndex: 1,
      source: _FailingCaptureSource(),
      sink: sink,
      elapsed: () => Duration.zero,
      delay: (_) async {},
      startedUtc: '2026-10-02T12:00:00Z',
      shouldStop: () => false,
      endReason: () => FrameCaptureEndReason.failed,
      outputPath: path,
    );

    expect(result.path, path);
    expect(result.error, contains('synthetic mid-capture failure'));
    final lines = File(path).readAsLinesSync();
    expect(lines, hasLength(2));
    expect(jsonDecode(lines.first), isA<Map<String, dynamic>>());
    expect(jsonDecode(lines.last)['type'], 'frame');
  });

  test('file sink keeps buffered partial rows when capture closes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'afterimage-frame-sink-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/replay_001.frames.jsonl';
    final sink = await LinuxFrameCaptureFileSink.create(path);

    await sink.writeLine(const <String, Object?>{
      'type': 'header',
      'schema': 1,
    });
    await sink.close();

    expect(await File(path).readAsString(), contains('"type":"header"'));
  });
}

const int _gWorld = 0x1000;
const int _uWorld = 0x2000;
const int _gameState = 0x3000;
const int _engine = 0x4000;
const int _player1 = 0x10000;
const int _player2 = 0x20000;
const int _entity1 = 0x30000;
const int _entity2 = 0x32000;
const int _entity3 = 0x33000;
const int _bridge1 = 0x31000;
const int _bridge2 = 0x32100;
const int _bridge3 = 0x33100;
const int _bbs1 = 0x50000;
const int _bbs2 = 0x51000;
const int _boxes1 = 0x60000;
const String _entity1Hex = '30000';

_FakeMemory _frameMemory({int entityCount = 0}) {
  final memory = _FakeMemory()
    ..putPointer(_gWorld, _uWorld)
    ..putPointer(_uWorld + 0x130, _gameState)
    ..putPointer(_gameState + 0xC38, _engine)
    ..putPointer(_engine + 0x8, _player1)
    ..putPointer(_engine + 0x198 + 0x8, _player2)
    ..putUint32(_engine + 0x3E7C, 1234)
    ..putInt32(_engine + 0x910, entityCount);
  return memory;
}

void _writePlayer(
  _FakeMemory memory,
  int address, {
  required String sprite,
  required int bbsCommand,
  required int bbsOpcode,
  required String bbsName,
  required int action,
  required int actionTime,
  required int hitstop,
  required int hp,
  required int w1b0,
  required int enable,
  required int attack,
  required int blockstun,
  required int hitstun,
  required int x,
  required int y,
  required int facing,
  required int flags,
  required int invuln,
  required int landed,
  required int strikeInvuln,
  required int throwInvuln,
  required int throwRange,
  required int slowdown,
  required int scaleX,
  required int scaleY,
  required int hitboxes,
  required Map<int, int> boxCounts,
}) {
  memory
    ..putString(address + 0x12F8, sprite, 32)
    ..putPointer(address + 0x12F0, bbsCommand)
    ..putInt32(address + 0xC50C, action)
    ..putInt32(address + 0x1CC, actionTime)
    ..putInt32(address + 0x288, hitstop)
    ..putInt32(address + 0x1254, hp)
    ..putUint32(address + 0x1B0, w1b0)
    ..putUint32(address + 0x6320, enable)
    ..putUint32(address + 0x632C, attack)
    ..putInt32(address + 0x6340, blockstun)
    ..putInt32(address + 0x9B08, hitstun)
    ..putInt32(address + 0x3B0, x)
    ..putInt32(address + 0x3B4, y)
    ..putInt32(address + 0x3AC, facing)
    ..putUint32(address + 0x398, flags)
    ..putUint32(address + 0x39C, invuln)
    ..putUint32(address + 0x3A0, landed)
    ..putInt32(address + 0x1220, strikeInvuln)
    ..putInt32(address + 0x1218, throwInvuln)
    ..putInt32(address + 0x7A8, throwRange)
    ..putInt32(address + 0xD248, slowdown)
    ..putInt32(address + 0x3CC, scaleX)
    ..putInt32(address + 0x3D0, scaleY)
    ..putPointer(address + 0x78, hitboxes);
  for (final entry in boxCounts.entries) {
    memory.putInt32(address + 0x114 + entry.key * 4, entry.value);
  }
  if (hitboxes != 0) {
    memory
      ..putBox(hitboxes, [0, 1.2344, -2.9874, 3.1414, 4.1114])
      ..putBox(hitboxes + 0x14, [1, 5.5, 6.5, 7.5, 8.5])
      ..putBox(hitboxes + 0x28, [2, 0, 0, 0, 0])
      ..putBox(hitboxes + 0x3C, [2, 0, 0, 0, 0])
      ..putBox(hitboxes + 0x50, [18, 9.5, 10.5, 11.5, 12.5]);
  }
}

void _writeEntity(
  _FakeMemory memory,
  int address, {
  required int parent,
  required int boxes,
}) {
  memory
    ..putPointer(address + 0x2C0, parent)
    ..putString(address + 0x12F8, 'projectile', 32)
    ..putPointer(address + 0x12F0, 0)
    ..putInt32(address + 0x3B0, 50)
    ..putInt32(address + 0x3B4, 60)
    ..putInt32(address + 0x3AC, 1)
    ..putInt32(address + 0x3CC, 1000)
    ..putInt32(address + 0x3D0, 1000)
    ..putInt32(address + 0x1CC, 4)
    ..putUint32(address + 0x1B0, 3)
    ..putInt32(address + 0x118, 1)
    ..putPointer(address + 0x78, boxes);
}

class _FakeMemory implements LinuxMemorySession {
  final Map<int, List<int>> _regions = {};
  List<int>? frameReadValues;
  int? _frameAddress;

  @override
  int get processId => 1;

  @override
  LinuxModule moduleFromName(String moduleName) =>
      throw UnsupportedError('No module in frame decoder tests.');

  @override
  List<int> readBytes(int address, int length) {
    if (frameReadValues != null && address == _frameAddress) {
      final values = frameReadValues!;
      if (values.isNotEmpty) {
        return _intBytes(values.removeAt(0), 4, signed: false);
      }
    }
    return List<int>.generate(length, (index) {
      final at = address + index;
      for (final entry in _regions.entries) {
        final offset = at - entry.key;
        if (offset >= 0 && offset < entry.value.length) {
          return entry.value[offset];
        }
      }
      return 0;
    });
  }

  @override
  void close() {}

  void putBytes(int address, List<int> bytes) {
    _regions[address] = List<int>.of(bytes);
    if (address == _engine + 0x3E7C) _frameAddress = address;
  }

  void putPointer(int address, int value) =>
      putBytes(address, _intBytes(value, 8, signed: false));

  void putUint16(int address, int value) =>
      putBytes(address, _intBytes(value, 2, signed: false));

  void putUint32(int address, int value) =>
      putBytes(address, _intBytes(value, 4, signed: false));

  void putInt32(int address, int value) =>
      putBytes(address, _intBytes(value, 4, signed: true));

  void putString(int address, String value, int maxLength) {
    final codes = value.codeUnits.take(maxLength).toList();
    codes.addAll(List<int>.filled(maxLength - codes.length, 0));
    putBytes(address, codes);
  }

  void putBox(int address, List<num> values) {
    putInt32(address, values.first.toInt());
    final data = ByteData(16);
    for (var index = 0; index < 4; index++) {
      data.setFloat32(index * 4, values[index + 1].toDouble(), Endian.little);
    }
    putBytes(address + 4, data.buffer.asUint8List());
  }
}

List<int> _intBytes(int value, int length, {required bool signed}) {
  final data = ByteData(length);
  switch (length) {
    case 2:
      if (signed) {
        data.setInt16(0, value, Endian.little);
      } else {
        data.setUint16(0, value, Endian.little);
      }
    case 4:
      if (signed) {
        data.setInt32(0, value, Endian.little);
      } else {
        data.setUint32(0, value, Endian.little);
      }
    case 8:
      data.setUint64(0, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

class _FakeCaptureSource implements LinuxFrameCaptureSource {
  _FakeCaptureSource({required this.frames, required this.reads});

  final List<int?> frames;
  final Map<int, LinuxFrameRowRead> reads;
  int? _lastFrame;

  @override
  int? readFrame() {
    if (frames.isNotEmpty) _lastFrame = frames.removeAt(0);
    return _lastFrame;
  }

  @override
  LinuxFrameRowRead readRow(int expectedFrame, int elapsedMicros) =>
      reads[expectedFrame] ?? const LinuxFrameRowRead();
}

class _ReadFailureCaptureSource
    implements LinuxFrameCaptureSource, LinuxFrameCaptureSourceDiagnostics {
  var _readCount = 0;
  bool _lastReadFailed = false;

  @override
  bool get lastReadFailed => _lastReadFailed;

  @override
  int? readFrame() {
    _lastReadFailed = _readCount++ < 2;
    return null;
  }

  @override
  LinuxFrameRowRead readRow(int expectedFrame, int elapsedMicros) =>
      const LinuxFrameRowRead();
}

class _FailingCaptureSource implements LinuxFrameCaptureSource {
  var _readCount = 0;

  @override
  int? readFrame() {
    if (_readCount++ == 0) return 100;
    throw StateError('synthetic mid-capture failure');
  }

  @override
  LinuxFrameRowRead readRow(int expectedFrame, int elapsedMicros) =>
      const LinuxFrameRowRead(row: {'type': 'frame', 'f': 100, 't': 0});
}

class _FakeCaptureSink implements LinuxFrameCaptureLineSink {
  final List<Map<String, Object?>> lines = [];
  int flushCalls = 0;

  @override
  Future<void> writeLine(Map<String, Object?> value) async {
    lines.add(value);
  }

  @override
  Future<void> flush() async {
    flushCalls++;
  }
}

class _FakeCaptureTime {
  _FakeCaptureTime({required this.stopAfterDelays});

  final int stopAfterDelays;
  final List<Duration> requestedDelays = [];
  Duration now = Duration.zero;
  int _delayCalls = 0;
  bool stopRequested = false;

  Future<void> delay(Duration duration) async {
    requestedDelays.add(duration);
    now += const Duration(milliseconds: 500);
    _delayCalls++;
    if (_delayCalls >= stopAfterDelays) stopRequested = true;
  }
}
