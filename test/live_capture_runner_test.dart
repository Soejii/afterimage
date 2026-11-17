import 'dart:convert';
import 'dart:io';

import 'package:afterimage/domain/finder_contracts.dart';
import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/services/linux_frame_capture.dart';
import 'package:afterimage/services/live_capture_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two live games never use input or OBS and start finder once', () async {
    final parent = await Directory.systemTemp.createTemp('live-capture-test-');
    addTearDown(() => parent.delete(recursive: true));
    final clock = _Clock();
    final finder = _Finder();
    final runner = LiveCaptureRunner(
      source: _Source(clock, [0, 1, 900, 0, 0, 1, 600, 0, 0]),
      clock: clock,
      reserveDirectory: () async => (await parent.createTemp('batch_')).path,
      menuInput: const ForbiddenLiveInput(),
      obs: const ForbiddenLiveObs(),
      finder: finder,
    );
    final directory = await runner.run();
    final summary =
        jsonDecode(await File('$directory/summary.json').readAsString()) as Map;
    expect(summary['source'], 'live');
    expect(summary['videoMode'], 'none');
    expect(summary['replays'], hasLength(2));
    expect(await File('$directory/replay_001.frames.jsonl').exists(), isTrue);
    expect(await File('$directory/replay_002.frames.jsonl').exists(), isTrue);
    expect(finder.calls, 1);
    expect(finder.reference, false);
    expect(finder.clips, false);
  });

  test('no games creates no folder and does not start finder', () async {
    final clock = _Clock();
    final finder = _Finder();
    final runner = LiveCaptureRunner(
      source: _Source(clock, [0, 0, 0]),
      clock: clock,
      reserveDirectory: () => throw StateError('unexpected folder'),
      menuInput: const ForbiddenLiveInput(),
      obs: const ForbiddenLiveObs(),
      finder: finder,
    );
    expect(await runner.run(), isNull);
    expect(finder.calls, 0);
  });

  test('game process exit ends its capture as aborted', () async {
    final parent = await Directory.systemTemp.createTemp('live-aborted-test-');
    addTearDown(() => parent.delete(recursive: true));
    final clock = _Clock();
    final runner = LiveCaptureRunner(
      source: _Source(clock, [0, 1, 2]),
      clock: clock,
      reserveDirectory: () async => (await parent.createTemp('batch_')).path,
      menuInput: const ForbiddenLiveInput(),
      obs: const ForbiddenLiveObs(),
    );
    final directory = await runner.run();
    final lines =
        await File('$directory/replay_001.frames.jsonl').readAsLines();
    final footer = jsonDecode(lines.last) as Map;
    expect(footer['end'], 'aborted');
  });
}

class _Clock implements ReplayClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  Future<void> delay(Duration duration) async {
    elapsed += duration;
  }
}

class _Source implements LiveCaptureSource, LinuxFrameCaptureInputStreamSource {
  _Source(this.clock, this.heads);
  final _Clock clock;
  final List<int> heads;
  int get index => clock.elapsed.inMilliseconds ~/ 16;
  @override
  bool get processAlive => index < heads.length;
  @override
  int readWriteSolid() => heads[index];
  @override
  int? readFrame() => clock.elapsed.inMilliseconds;
  @override
  LinuxFrameRowRead readRow(int expectedFrame, int elapsedMicros) =>
      LinuxFrameRowRead(row: {
        'type': 'frame',
        'f': expectedFrame,
        'wp': [heads[index], heads[index]]
      });
  @override
  Map<String, Object?> readInputStream() => {
        'type': 'inputs',
        'seats': [
          [65541],
          [65541]
        ],
        'frames': [1, 1],
        'error': null,
      };
}

class _Finder implements FinderPort {
  int calls = 0;
  bool? reference;
  bool? clips;
  @override
  bool get available => true;
  @override
  Future<void> startBatch(String batchFolder,
      {bool reference = false, bool clips = true}) async {
    calls++;
    this.reference = reference;
    this.clips = clips;
  }
}
