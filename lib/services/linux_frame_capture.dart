import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../app/afterimage_version.dart';
import '../domain/recorder_contracts.dart';
import '../domain/replay_batch.dart';
import 'linux_process_memory.dart';
import 'linux_replay_monitor.dart';

const int linuxEnginePlayersOffset = 0x0;
const int linuxEnginePlayerStride = 0x198;
const int linuxPlayerPointerOffset = 0x8;
const int linuxEngineInputsOffset = 0x3868;
const int linuxInputStride = 0x80;
const int linuxInputMaskOffset = 0x2;
const int linuxEngineEntitiesOffset = 0xC80;
const int linuxEngineEntityCountOffset = 0x910;
const int linuxMaxEntityCount = 107;
const int linuxEntityParentObjectOffset = 0x2C0;

const int _linuxPointerSize = 8;
const Duration _linuxFrameCaptureStopTimeout = Duration(seconds: 3);

/// Result of one memory read for a candidate frame.
class LinuxFrameRowRead {
  const LinuxFrameRowRead({
    this.row,
    this.torn = false,
    this.readError = false,
  });

  final Map<String, Object?>? row;
  final bool torn;
  final bool readError;
}

/// Minimal seam used by the polling loop and its fake-source tests.
abstract interface class LinuxFrameCaptureSource {
  int? readFrame();

  LinuxFrameRowRead readRow(int expectedFrame, int elapsedMicros);
}

/// Optional diagnostics for sources that can distinguish failed reads from
/// ordinary missing engine or player pointers.
abstract interface class LinuxFrameCaptureSourceDiagnostics {
  bool get lastReadFailed;
}

abstract interface class LinuxFrameCaptureLineSink {
  Future<void> writeLine(Map<String, Object?> value);

  Future<void> flush();
}

abstract interface class LinuxFrameCaptureClosableLineSink
    implements LinuxFrameCaptureLineSink {
  Future<void> close();
}

/// Keeps the isolate's completion message ahead of its exit notification.
class LinuxFrameCaptureExitTracker {
  bool _doneReceived = false;

  void markDone() {
    _doneReceived = true;
  }

  bool exitIsUnexpected() => !_doneReceived;
}

/// Polls `GameFrame`, logging only changed frames and rejecting torn reads.
class LinuxFrameCaptureLoop {
  LinuxFrameCaptureLoop({
    required this.replayIndex,
    required this.source,
    required this.sink,
    required this.elapsed,
    required this.delay,
    required this.startedUtc,
    required this.afterimageVersion,
  });

  final int replayIndex;
  final LinuxFrameCaptureSource source;
  final LinuxFrameCaptureLineSink sink;
  final Duration Function() elapsed;
  final Future<void> Function(Duration duration) delay;
  final String startedUtc;
  final String afterimageVersion;

  Future<FrameCaptureResult> run({
    required bool Function() shouldStop,
    FrameCaptureEndReason Function()? endReason,
  }) async {
    await sink.writeLine(<String, Object?>{
      'type': 'header',
      'schema': 1,
      'replay': replayIndex,
      'startedUtc': startedUtc,
      'afterimage': afterimageVersion,
    });
    var rows = 0;
    var frameGaps = 0;
    var maxFrameGap = 0;
    var polls = 0;
    var tornRows = 0;
    var readErrors = 0;
    int? previousFrame;
    var lastFlush = elapsed();
    final resolveEndReason = endReason ?? () => FrameCaptureEndReason.completed;
    final diagnostics = source is LinuxFrameCaptureSourceDiagnostics
        ? source as LinuxFrameCaptureSourceDiagnostics
        : null;

    while (!shouldStop()) {
      polls++;
      final frame = source.readFrame();
      if (diagnostics?.lastReadFailed ?? false) {
        readErrors++;
      }
      if (frame != null && frame != previousFrame) {
        final candidate = source.readRow(frame, elapsed().inMicroseconds);
        if (candidate.readError) {
          readErrors++;
        } else if (candidate.torn) {
          tornRows++;
        } else if (candidate.row != null) {
          final prior = previousFrame;
          if (prior != null && frame > prior + 1) {
            final missing = frame - prior - 1;
            frameGaps++;
            if (missing > maxFrameGap) maxFrameGap = missing;
          }
          await sink.writeLine(candidate.row!);
          rows++;
          previousFrame = frame;
        }
      }

      final now = elapsed();
      if (now - lastFlush >= const Duration(seconds: 1)) {
        await sink.flush();
        lastFlush = now;
      }
      await delay(const Duration(milliseconds: 1));
    }

    await sink.writeLine(<String, Object?>{
      'type': 'footer',
      'end': resolveEndReason().name,
      'rows': rows,
      'frameGaps': frameGaps,
      'maxFrameGap': maxFrameGap,
      'polls': polls,
      'tornRows': tornRows,
      'readErrors': readErrors,
    });
    await sink.flush();
    return FrameCaptureResult(
      rows: rows,
      frameGaps: frameGaps,
      maxFrameGap: maxFrameGap,
      readErrors: readErrors,
    );
  }
}

/// Decodes raw GGST memory into one contract row. The function performs no IO
/// besides reads through [memory], so it can be exercised with a byte-map fake.
LinuxFrameRowRead decodeLinuxFrameRow({
  required LinuxMemorySession memory,
  required int gWorldPointerAddress,
  required int expectedFrame,
  required int elapsedMicros,
}) {
  final state = _readEngineState(memory, gWorldPointerAddress);
  if (state == null) return const LinuxFrameRowRead();

  final initialFrame =
      _readUint32(memory, state.engine + linuxEngineGameFrameOffset);
  if (initialFrame != expectedFrame) {
    return const LinuxFrameRowRead(torn: true);
  }

  final inputs = <int>[
    _readUint16(
      memory,
      state.engine + linuxEngineInputsOffset + linuxInputMaskOffset,
    ),
    _readUint16(
      memory,
      state.engine +
          linuxEngineInputsOffset +
          linuxInputStride +
          linuxInputMaskOffset,
    ),
  ];
  final players = <Map<String, Object?>>[
    _readPlayer(memory, state.player1),
    _readPlayer(memory, state.player2),
  ];
  final entities = _readEntities(memory, state);

  final finalFrame =
      _readUint32(memory, state.engine + linuxEngineGameFrameOffset);
  if (finalFrame != initialFrame) {
    return const LinuxFrameRowRead(torn: true);
  }

  return LinuxFrameRowRead(
    row: <String, Object?>{
      'type': 'frame',
      'f': initialFrame,
      't': elapsedMicros,
      'in': inputs,
      'p': players,
      'e': entities,
    },
  );
}

class LinuxFrameCapture implements FrameCapturePort, AbortableFrameCapturePort {
  LinuxFrameCapture({
    this.processName = ggstLinuxExecutable,
    this.stopTimeout = _linuxFrameCaptureStopTimeout,
  });

  final String processName;
  final Duration stopTimeout;
  _LinuxFrameCaptureWorker? _worker;

  @override
  Future<void> start({
    required int replayIndex,
    required String outputPath,
    int? gWorldPointerAddress,
  }) async {
    if (_worker != null) {
      throw StateError('A frame capture is already active.');
    }
    final worker = _LinuxFrameCaptureWorker(
      processName: processName,
      replayIndex: replayIndex,
      outputPath: outputPath,
      gWorldPointerAddress: gWorldPointerAddress,
      stopTimeout: stopTimeout,
    );
    _worker = worker;
    try {
      await worker.start();
    } catch (_) {
      _worker = null;
      await worker.dispose();
      rethrow;
    }
  }

  @override
  Future<FrameCaptureResult> stop({
    required FrameCaptureEndReason reason,
  }) async {
    final worker = _worker;
    if (worker == null) return const FrameCaptureResult();
    try {
      return await worker.stop(reason: reason);
    } finally {
      _worker = null;
      await worker.dispose();
    }
  }

  @override
  Future<void> close() async {
    final worker = _worker;
    if (worker == null) return;
    try {
      await worker.stop(reason: FrameCaptureEndReason.failed);
    } finally {
      _worker = null;
      await worker.dispose();
    }
  }

  @override
  Future<FrameCaptureResult> abort() async {
    final worker = _worker;
    if (worker == null) return const FrameCaptureResult();
    try {
      return await worker.abort();
    } finally {
      _worker = null;
      await worker.dispose(forceKill: true);
    }
  }
}

class _LinuxFrameCaptureWorker {
  _LinuxFrameCaptureWorker({
    required this.processName,
    required this.replayIndex,
    required this.outputPath,
    required this.gWorldPointerAddress,
    required this.stopTimeout,
  });

  final String processName;
  final int replayIndex;
  final String outputPath;
  final int? gWorldPointerAddress;
  final Duration stopTimeout;
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Completer<FrameCaptureResult> _completed =
      Completer<FrameCaptureResult>();
  final Completer<void> _exited = Completer<void>();
  ReceivePort? _responses;
  ReceivePort? _errors;
  SendPort? _commands;
  Isolate? _isolate;
  String? _createdOutputPath;
  final LinuxFrameCaptureExitTracker _exitTracker =
      LinuxFrameCaptureExitTracker();

  Future<void> start() async {
    final responses = ReceivePort();
    final errors = ReceivePort();
    _responses = responses;
    _errors = errors;
    responses.listen(_onResponse);
    errors.listen(_onError);

    _isolate = await Isolate.spawn<List<Object?>>(
      _linuxFrameCaptureIsolateEntry,
      <Object?>[
        responses.sendPort,
        processName,
        replayIndex,
        outputPath,
        gWorldPointerAddress,
      ],
      onError: errors.sendPort,
      onExit: responses.sendPort,
    );
    _commands = await _ready.future;
  }

  Future<FrameCaptureResult> stop({
    required FrameCaptureEndReason reason,
  }) async {
    if (!_completed.isCompleted) {
      _commands?.send(<String, Object?>{
        'type': 'stop',
        'reason': reason.name,
      });
    }
    try {
      return await _completed.future.timeout(stopTimeout);
    } on TimeoutException {
      return abort();
    }
  }

  Future<FrameCaptureResult> abort() async {
    if (_completed.isCompleted) return _completed.future;
    final result = FrameCaptureResult(
      path: _createdOutputPath,
      error: 'Frame capture isolate was abandoned during stop.',
    );
    if (!_ready.isCompleted) {
      _ready.completeError(
        StateError('Frame capture isolate was abandoned before it was ready.'),
      );
    }
    _complete(result);
    _isolate?.kill(priority: Isolate.immediate);
    return result;
  }

  Future<void> dispose({bool forceKill = false}) async {
    final isolate = _isolate;
    if (isolate != null) {
      if (forceKill) {
        isolate.kill(priority: Isolate.immediate);
      } else if (!_completed.isCompleted) {
        _commands?.send(<String, Object?>{
          'type': 'stop',
          'reason': FrameCaptureEndReason.failed.name,
        });
        try {
          await _completed.future.timeout(stopTimeout);
        } on TimeoutException {
          await abort();
        }
      }
      if (!_exited.isCompleted) {
        try {
          await _exited.future.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          isolate.kill(priority: Isolate.immediate);
        }
      }
    }
    _responses?.close();
    _errors?.close();
    _responses = null;
    _errors = null;
    _commands = null;
    _isolate = null;
  }

  void _onResponse(Object? message) {
    if (message == null) {
      _onExit();
      return;
    }
    if (message is! Map) return;
    switch (message['type']) {
      case 'ready':
        final port = message['commandPort'];
        if (port is SendPort && !_ready.isCompleted) {
          _ready.complete(port);
        }
      case 'fileCreated':
        final path = message['path'];
        if (path is String) _createdOutputPath = path;
      case 'done':
        _exitTracker.markDone();
        final result = message['result'];
        if (result is Map) {
          final path = result['path'];
          if (path is String) _createdOutputPath = path;
          _complete(FrameCaptureResult(
            rows: _intValue(result['rows']),
            frameGaps: _intValue(result['frameGaps']),
            maxFrameGap: _intValue(result['maxFrameGap']),
            readErrors: _intValue(result['readErrors']),
            path: path is String ? path : _createdOutputPath,
            error: result['error'] is String ? result['error'] as String : null,
          ));
        } else {
          _completeWithError('Frame capture returned an invalid result.');
        }
    }
  }

  void _onExit() {
    if (!_exited.isCompleted) _exited.complete();
    if (!_exitTracker.exitIsUnexpected()) return;
    if (!_ready.isCompleted) {
      _ready.completeError(
        StateError('Frame capture isolate exited before it was ready.'),
      );
    }
    _completeWithError('Frame capture isolate exited unexpectedly.');
  }

  void _onError(Object? message) {
    final description = message is List && message.isNotEmpty
        ? message.first.toString()
        : message.toString();
    _completeWithError(description);
    if (!_ready.isCompleted) _ready.completeError(StateError(description));
  }

  void _complete(FrameCaptureResult result) {
    if (!_completed.isCompleted) _completed.complete(result);
  }

  void _completeWithError(String error) =>
      _complete(FrameCaptureResult(path: _createdOutputPath, error: error));

  static int _intValue(Object? value) => value is int ? value : 0;
}

void _linuxFrameCaptureIsolateEntry(List<Object?> args) {
  final parent = args[0] as SendPort;
  final processName = args[1] as String;
  final replayIndex = args[2] as int;
  final outputPath = args[3] as String;
  final gWorldPointerAddress = args[4] as int?;
  final commands = ReceivePort();
  final stopwatch = Stopwatch()..start();
  var stopRequested = false;
  var stopReason = FrameCaptureEndReason.failed;
  commands.listen((message) {
    if (message is Map && message['type'] == 'stop') {
      stopRequested = true;
      stopReason = _parseFrameCaptureEndReason(message['reason']);
    }
  });
  parent.send(<String, Object?>{
    'type': 'ready',
    'commandPort': commands.sendPort,
  });
  Timer.run(() {
    unawaited(_runLinuxFrameCaptureIsolate(
      parent: parent,
      commands: commands,
      processName: processName,
      replayIndex: replayIndex,
      outputPath: outputPath,
      gWorldPointerAddress: gWorldPointerAddress,
      elapsed: () => stopwatch.elapsed,
      shouldStop: () => stopRequested,
      endReason: () => stopReason,
    ));
  });
}

FrameCaptureEndReason _parseFrameCaptureEndReason(Object? value) {
  for (final reason in FrameCaptureEndReason.values) {
    if (reason.name == value) return reason;
  }
  return FrameCaptureEndReason.failed;
}

Future<FrameCaptureResult> runLinuxFrameCaptureSession({
  required int replayIndex,
  required LinuxFrameCaptureSource source,
  required LinuxFrameCaptureClosableLineSink sink,
  required Duration Function() elapsed,
  required Future<void> Function(Duration duration) delay,
  required String startedUtc,
  required bool Function() shouldStop,
  required FrameCaptureEndReason Function() endReason,
  required String outputPath,
}) async {
  final loop = LinuxFrameCaptureLoop(
    replayIndex: replayIndex,
    source: source,
    sink: sink,
    elapsed: elapsed,
    delay: delay,
    startedUtc: startedUtc,
    afterimageVersion: afterimageVersion,
  );
  try {
    final result = await loop.run(
      shouldStop: shouldStop,
      endReason: endReason,
    );
    await sink.close();
    return FrameCaptureResult(
      rows: result.rows,
      frameGaps: result.frameGaps,
      maxFrameGap: result.maxFrameGap,
      readErrors: result.readErrors,
      path: outputPath,
    );
  } catch (error) {
    try {
      await sink.close();
    } on Object {
      // Preserve the partial sidecar even when its final flush fails.
    }
    return FrameCaptureResult(
      path: outputPath,
      error: error.toString(),
    );
  }
}

Future<void> _runLinuxFrameCaptureIsolate({
  required SendPort parent,
  required ReceivePort commands,
  required String processName,
  required int replayIndex,
  required String outputPath,
  required int? gWorldPointerAddress,
  required Duration Function() elapsed,
  required bool Function() shouldStop,
  required FrameCaptureEndReason Function() endReason,
}) async {
  LinuxMemorySession? memory;
  LinuxFrameCaptureFileSink? sink;
  final startedUtc = DateTime.now().toUtc().toIso8601String();
  try {
    memory = LinuxProcessMemory.open(processName);
    var resolvedAddress = gWorldPointerAddress;
    if (resolvedAddress == null) {
      final module = memory.moduleFromName(processName);
      final scan = const LinuxPatternScanner().scan(
        module: module,
        pattern: ggstGWorldPattern,
        read: memory.readBytes,
      );
      final hit = scan.address;
      if (hit == null) {
        throw StateError('The GGST GWorld signature was not found.');
      }
      final displacement = decodeSignedInt32(memory.readBytes(hit + 8, 4));
      resolvedAddress = resolveRipRelativeAddress(hit, displacement);
    }

    sink = await LinuxFrameCaptureFileSink.create(outputPath);
    parent.send(<String, Object?>{
      'type': 'fileCreated',
      'path': outputPath,
    });
    final source = _LinuxProcessFrameSource(
      memory: memory,
      gWorldPointerAddress: resolvedAddress,
    );
    final result = await runLinuxFrameCaptureSession(
      replayIndex: replayIndex,
      source: source,
      sink: sink,
      elapsed: elapsed,
      delay: Future<void>.delayed,
      startedUtc: startedUtc,
      shouldStop: shouldStop,
      endReason: endReason,
      outputPath: outputPath,
    );
    parent.send(<String, Object?>{
      'type': 'done',
      'result': <String, Object?>{
        'rows': result.rows,
        'frameGaps': result.frameGaps,
        'maxFrameGap': result.maxFrameGap,
        'readErrors': result.readErrors,
        'path': result.path,
        'error': result.error,
      },
    });
  } catch (error) {
    try {
      await sink?.close();
    } on Object {
      // Preserve the partial sidecar even when its final flush fails.
    }
    parent.send(<String, Object?>{
      'type': 'done',
      'result': <String, Object?>{
        'path': sink?.path,
        'error': error.toString(),
      },
    });
  } finally {
    memory?.close();
    commands.close();
  }
}

class LinuxFrameCaptureFileSink implements LinuxFrameCaptureClosableLineSink {
  LinuxFrameCaptureFileSink._(this.path, this.file, this.handle);

  static Future<LinuxFrameCaptureFileSink> create(String path) async {
    final file = File(path);
    await file.create(exclusive: true);
    try {
      final handle = await file.open(mode: FileMode.append);
      return LinuxFrameCaptureFileSink._(path, file, handle);
    } on Object {
      rethrow;
    }
  }

  final String path;
  final File file;
  final RandomAccessFile handle;
  final StringBuffer _buffer = StringBuffer();
  bool _closed = false;

  @override
  Future<void> writeLine(Map<String, Object?> value) async {
    if (_closed) throw StateError('The frame capture file is closed.');
    _buffer.writeln(jsonEncode(value));
  }

  @override
  Future<void> flush() async {
    if (_closed) return;
    if (_buffer.isNotEmpty) {
      final contents = _buffer.toString();
      await handle.writeString(contents);
      _buffer.clear();
    }
    await handle.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    try {
      await flush();
    } finally {
      _closed = true;
      await handle.close();
    }
  }
}

class _LinuxProcessFrameSource
    implements LinuxFrameCaptureSource, LinuxFrameCaptureSourceDiagnostics {
  _LinuxProcessFrameSource({
    required this.memory,
    required this.gWorldPointerAddress,
  });

  final LinuxMemorySession memory;
  final int gWorldPointerAddress;
  bool _lastReadFailed = false;

  @override
  bool get lastReadFailed => _lastReadFailed;

  @override
  int? readFrame() {
    _lastReadFailed = false;
    try {
      final state = _readEngineState(memory, gWorldPointerAddress);
      if (state == null) return null;
      return _readUint32(memory, state.engine + linuxEngineGameFrameOffset);
    } on Object {
      _lastReadFailed = true;
      // Read failures and missing pointers are transient during replay and
      // rounds. The capture keeps polling without inventing rows.
      return null;
    }
  }

  @override
  LinuxFrameRowRead readRow(int expectedFrame, int elapsedMicros) {
    try {
      return decodeLinuxFrameRow(
        memory: memory,
        gWorldPointerAddress: gWorldPointerAddress,
        expectedFrame: expectedFrame,
        elapsedMicros: elapsedMicros,
      );
    } on Object {
      return const LinuxFrameRowRead(readError: true);
    }
  }
}

class _EngineFrameState {
  const _EngineFrameState({
    required this.engine,
    required this.player1,
    required this.player2,
  });

  final int engine;
  final int player1;
  final int player2;
}

_EngineFrameState? _readEngineState(
  LinuxMemorySession memory,
  int gWorldPointerAddress,
) {
  final uWorld = _readPointer(memory, gWorldPointerAddress);
  if (uWorld == 0) return null;
  final gameState = _readPointer(memory, uWorld + linuxUWorldGameStateOffset);
  if (gameState == 0) return null;
  final engine = _readPointer(memory, gameState + linuxGameStateEngineOffset);
  if (engine == 0) return null;
  final player1 = _readPointer(
    memory,
    engine + linuxEnginePlayersOffset + linuxPlayerPointerOffset,
  );
  final player2 = _readPointer(
    memory,
    engine +
        linuxEnginePlayersOffset +
        linuxEnginePlayerStride +
        linuxPlayerPointerOffset,
  );
  if (player1 == 0 || player2 == 0) return null;
  return _EngineFrameState(
    engine: engine,
    player1: player1,
    player2: player2,
  );
}

Map<String, Object?> _readPlayer(LinuxMemorySession memory, int address) {
  return <String, Object?>{
    'spr': _readCString(memory, address + 0x12F8, 32),
    'bbs': _readBbState(memory, address + 0x12F0),
    'act': _readInt32(memory, address + 0xC50C),
    'at': _readInt32(memory, address + 0x1CC),
    'hs': _readInt32(memory, address + 0x288),
    'w1b0': _readUint32(memory, address + 0x1B0),
    'en': _readUint32(memory, address + 0x6320),
    'atk': _readUint32(memory, address + 0x632C),
    'bs': _readInt32(memory, address + 0x6340),
    'hst': _readInt32(memory, address + 0x9B08),
    'x': _readInt32(memory, address + 0x3B0),
    'y': _readInt32(memory, address + 0x3B4),
    'fc': _readInt32(memory, address + 0x3AC),
    'w398': _readUint32(memory, address + 0x398),
    'w39c': _readUint32(memory, address + 0x39C),
    'w3a0': _readUint32(memory, address + 0x3A0),
    'sivt': _readInt32(memory, address + 0x1220),
    'tivt': _readInt32(memory, address + 0x1218),
    'thr': _readInt32(memory, address + 0x7A8),
    'slow': _readInt32(memory, address + 0xD248),
    'sx': _readInt32(memory, address + 0x3CC),
    'sy': _readInt32(memory, address + 0x3D0),
    'bx': _readBoxes(memory, address),
  };
}

Map<String, Object?> _readEntity(
  LinuxMemorySession memory,
  int address,
  _EngineFrameState state,
) {
  return <String, Object?>{
    'id': '0x${address.toRadixString(16)}',
    'own': _readEntityOwner(memory, address, state.player1, state.player2),
    'spr': _readCString(memory, address + 0x12F8, 32),
    'bbs': _readBbState(memory, address + 0x12F0),
    'x': _readInt32(memory, address + 0x3B0),
    'y': _readInt32(memory, address + 0x3B4),
    'fc': _readInt32(memory, address + 0x3AC),
    'sx': _readInt32(memory, address + 0x3CC),
    'sy': _readInt32(memory, address + 0x3D0),
    'at': _readInt32(memory, address + 0x1CC),
    'w1b0': _readUint32(memory, address + 0x1B0),
    'hbc': _readInt32(memory, address + 0x118),
    'bx': _readBoxes(memory, address),
  };
}

List<Map<String, Object?>> _readEntities(
  LinuxMemorySession memory,
  _EngineFrameState state,
) {
  final count = _readInt32(
    memory,
    state.engine + linuxEngineEntityCountOffset,
  ).clamp(0, linuxMaxEntityCount);
  final entities = <Map<String, Object?>>[];
  for (var index = 0; index < count; index++) {
    final address = _readPointer(
      memory,
      state.engine + linuxEngineEntitiesOffset + index * _linuxPointerSize,
    );
    if (address == 0 || address == state.player1 || address == state.player2) {
      continue;
    }
    try {
      entities.add(_readEntity(memory, address, state));
    } on Object {
      // A projectile can disappear while another field is being read. Skip
      // only that entity; a transient entity read must not lose player rows.
    }
  }
  return entities;
}

int? _readEntityOwner(
  LinuxMemorySession memory,
  int address,
  int player1,
  int player2,
) {
  var parent = address;
  try {
    for (var hop = 0; hop < 8; hop++) {
      parent = _readPointer(memory, parent + linuxEntityParentObjectOffset);
      if (parent == 0) return null;
      if (parent == player1) return 0;
      if (parent == player2) return 1;
    }
  } on Object {
    return null;
  }
  return null;
}

List<List<Object>>? _readBoxes(LinuxMemorySession memory, int address) {
  final counts = List<int>.generate(
    19,
    (index) => _readInt32(memory, address + 0x114 + index * 4),
    growable: false,
  );
  if (counts.any((count) => count < 0 || count > 1000)) return null;

  final mainCount = counts[0] + counts[1];
  final followCount = counts[18];
  if (mainCount == 0 && followCount == 0) return <List<Object>>[];

  final boxesAddress = _readPointer(memory, address + 0x78);
  if (boxesAddress == 0) return null;
  final result = <List<Object>>[];
  for (var index = 0; index < mainCount; index++) {
    result.add(_readBox(memory, boxesAddress + index * 0x14));
  }
  var followStart = 0;
  for (var index = 0; index < 18; index++) {
    followStart += counts[index];
  }
  for (var index = 0; index < followCount; index++) {
    result.add(_readBox(memory, boxesAddress + (followStart + index) * 0x14));
  }
  return result;
}

List<Object> _readBox(LinuxMemorySession memory, int address) {
  final type = _readInt32(memory, address);
  final bytes = memory.readBytes(address + 4, 16);
  if (bytes.length < 16) {
    throw const OSError('A box read returned fewer than sixteen bytes.');
  }
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return <Object>[
    type,
    _round3(data.getFloat32(0, Endian.little)),
    _round3(data.getFloat32(4, Endian.little)),
    _round3(data.getFloat32(8, Endian.little)),
    _round3(data.getFloat32(12, Endian.little)),
  ];
}

double _round3(double value) => (value * 1000).round() / 1000;

String? _readBbState(LinuxMemorySession memory, int address) {
  final command = _readPointer(memory, address);
  if (command == 0 || _readInt32(memory, command) != 0) return null;
  return _readCString(memory, command + 4, 32);
}

String _readCString(LinuxMemorySession memory, int address, int maxLength) {
  final bytes = memory.readBytes(address, maxLength);
  final nul = bytes.indexOf(0);
  return String.fromCharCodes(nul < 0 ? bytes : bytes.sublist(0, nul));
}

int _readPointer(LinuxMemorySession memory, int address) {
  final bytes = memory.readBytes(address, _linuxPointerSize);
  if (bytes.length < _linuxPointerSize) {
    throw const OSError('A pointer read returned fewer than eight bytes.');
  }
  var value = 0;
  for (var index = 0; index < _linuxPointerSize; index++) {
    value |= bytes[index] << (index * 8);
  }
  return value;
}

int _readUint16(LinuxMemorySession memory, int address) {
  final bytes = memory.readBytes(address, 2);
  if (bytes.length < 2) {
    throw const OSError('A uint16 read returned fewer than two bytes.');
  }
  return bytes[0] | (bytes[1] << 8);
}

int _readUint32(LinuxMemorySession memory, int address) {
  final bytes = memory.readBytes(address, 4);
  if (bytes.length < 4) {
    throw const OSError('A uint32 read returned fewer than four bytes.');
  }
  return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
}

int _readInt32(LinuxMemorySession memory, int address) =>
    decodeSignedInt32(memory.readBytes(address, 4));
