import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/recorder_contracts.dart';
import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/domain/replay_summary.dart';
import 'package:afterimage/domain/setup_models.dart';
import 'package:afterimage/services/linux_frame_capture.dart';
import 'package:afterimage/services/replay_batch_engine.dart';

void main() {
  group('ReplayCompletionDetector', () {
    test('a result event only completes a battle after frame movement', () {
      final detector = ReplayCompletionDetector(absentPollsRequired: 2);

      expect(
        detector.observe(
          _snapshot(frame: 100, events: {matchResultEventType}),
        ),
        isFalse,
      );
      expect(detector.battleStarted, isFalse);
      expect(detector.observe(_snapshot(frame: 100)), isFalse);
      expect(detector.observe(_snapshot(frame: 101)), isFalse);
      expect(detector.battleStarted, isTrue);
      expect(
        detector.observe(
          _snapshot(frame: 101, events: {matchResultEventType}),
        ),
        isTrue,
      );
      expect(detector.reason, ReplayCompletionReason.matchResultEvent);
    });

    test('temporary missing reads need consecutive duration-derived polls', () {
      final detector = ReplayCompletionDetector(absentPollsRequired: 2);

      detector.observe(_snapshot(frame: 20));
      detector.observe(_snapshot(frame: 21));
      expect(detector.observe(const BattleSnapshot.empty()), isFalse);
      expect(detector.absentPolls, 1);
      expect(detector.observe(_snapshot(frame: 21)), isFalse);
      expect(detector.absentPolls, 0);
      expect(detector.observe(const BattleSnapshot.empty()), isFalse);
      expect(detector.observe(const BattleSnapshot.empty()), isTrue);
      expect(detector.reason, ReplayCompletionReason.battleStateDisappeared);
    });

    test('a frozen frame does not look like a completed battle', () {
      final detector = ReplayCompletionDetector(absentPollsRequired: 4);

      detector.observe(_snapshot(frame: 100));
      detector.observe(_snapshot(frame: 101));
      for (var index = 0; index < 100; index++) {
        expect(detector.observe(_snapshot(frame: 101)), isFalse);
      }

      expect(detector.battleStarted, isTrue);
      expect(detector.reason, isNull);
    });

    test('missing-read threshold preserves the prototype duration rule', () {
      expect(
        absentPollsForInterval(const Duration(milliseconds: 10)),
        300,
      );
      expect(
        absentPollsForInterval(const Duration(seconds: 1)),
        4,
      );
      expect(
        () => absentPollsForInterval(Duration.zero),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ReplayBatchEngine', () {
    test(
        'separate mode records once per replay and waits for list confirmation',
        () async {
      final monitor = _FakeMonitor(
        _successfulBatchSnapshots(2, noisyFirstList: true),
      );
      final menu = _FakeMenu();
      final selectNextReads = <int>[];
      menu.onPerform = (action) {
        if (action == ReplayMenuAction.selectNextReplay) {
          selectNextReads.add(monitor.snapshotsRead);
        }
      };
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final events = <ReplayBatchEvent>[];
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
        onEvent: events.add,
      );

      final result = await engine.startBatch(_request(count: 2));

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(
        result.replays.map((replay) => replay.status).toList(),
        [ReplayResultStatus.recorded, ReplayResultStatus.recorded],
      );
      expect(obs.startCalls, 2);
      expect(obs.stopCalls, 2);
      expect(
        organizer.replayCalls.map((call) => call.replayIndex).toList(),
        [1, 2],
      );
      expect(organizer.replayCalls.every((call) => !call.partial), isTrue);
      expect(
        menu.actions,
        [
          ReplayMenuAction.openReplay,
          ReplayMenuAction.exitToReplayList,
          ReplayMenuAction.selectNextReplay,
          ReplayMenuAction.openReplay,
          ReplayMenuAction.exitToReplayList,
        ],
      );
      // The first replay has three battle reads, one non-list read, and four
      // consecutive list reads before the next-replay action is sent.
      expect(selectNextReads, [8]);
      expect(
        events
            .where((event) => event.type == ReplayBatchEventType.battleStarted),
        hasLength(2),
      );
      expect(
        events.where(
            (event) => event.type == ReplayBatchEventType.replayCompleted),
        hasLength(2),
      );
      expect(engine.isRunning, isFalse);
      expect(monitor.closed, isTrue);
      expect(obs.connectCalls, 1);
      expect(obs.closeCalls, 1);
    });

    test('combined mode starts and stops OBS exactly once for the batch',
        () async {
      final monitor = _FakeMonitor(_successfulBatchSnapshots(2));
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
      );

      final result = await engine.startBatch(
        _request(count: 2, videoMode: VideoMode.combined),
      );

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(obs.startCalls, 1);
      expect(obs.stopCalls, 1);
      expect(organizer.replayCalls, isEmpty);
      expect(organizer.combinedCalls, hasLength(1));
      expect(organizer.combinedCalls.single.partial, isFalse);
      expect(result.combinedOutput?.partial, isFalse);
      expect(result.combinedOutput?.path, 'combined_1.mp4');
      expect(
        menu.actions.where((action) => action == ReplayMenuAction.openReplay),
        hasLength(2),
      );
    });

    test('capture brackets battle events and stops before result delay',
        () async {
      for (final mode in VideoMode.values) {
        final markers = <String>[];
        final clock = _FakeClock()
          ..onDelayDuration = (duration) {
            if (duration == const Duration(milliseconds: 10)) {
              markers.add('resultDelay');
            }
          };
        Duration? obsConfirmedAt;
        Duration? captureConfirmedAt;
        final obs = _FakeObs()
          ..onStart = () {
            clock.advance(const Duration(milliseconds: 5));
            obsConfirmedAt = clock.elapsed;
          };
        final capture = _FakeFrameCapture(
          onStart: () {
            clock.advance(const Duration(milliseconds: 7));
            captureConfirmedAt = clock.elapsed;
            markers.add('captureStart');
          },
          onStop: () => markers.add('captureStop'),
        );
        final engine = _engine(
          monitor: _FakeMonitor(_successfulReplaySnapshots()),
          menu: _FakeMenu(),
          obs: obs,
          organizer: _FakeOrganizer(),
          clock: clock,
          frameCapturePort: capture,
          onEvent: (event) {
            if (event.type == ReplayBatchEventType.battleStarted) {
              markers.add('battleStarted');
            }
          },
        );

        final result = await engine.startBatch(
          _request(
            videoMode: mode,
            captureFrameData: true,
            timing: _testTiming(resultDelay: const Duration(milliseconds: 10)),
          ),
        );

        expect(result.replays.single.status, ReplayResultStatus.recorded);
        expect(
          markers.indexOf('battleStarted'),
          lessThan(markers.indexOf('captureStart')),
        );
        expect(
          markers.indexOf('captureStop'),
          lessThan(markers.indexOf('resultDelay')),
        );
        expect(
          result.replays.single.capture?.videoOffsetMs,
          (captureConfirmedAt! - obsConfirmedAt!).inMilliseconds,
        );
        expect(capture.startCalls.single.outputPath,
            '/tmp/afterimage-test/replay_001.frames.jsonl');
        expect(result.replays.single.capture?.path, 'replay_001.frames.jsonl');
        expect(result.replays.single.capture?.rows, 3);
        expect(capture.stopReasons, [FrameCaptureEndReason.completed]);
      }
    });

    test('a hung capture stop is bounded and does not keep OBS recording',
        () async {
      final capture = _FakeFrameCapture()..neverCompleteOnStop = true;
      final obs = _FakeObs();
      late ReplayBatchEngine engine;
      engine = _engine(
        monitor: _FakeMonitor(_successfulReplaySnapshots()),
        menu: _FakeMenu(),
        obs: obs,
        organizer: _FakeOrganizer(),
        clock: _FakeClock(),
        frameCapturePort: capture,
        onEvent: (event) {
          if (event.progress.state == ReplayBatchState.waitingForReplayEnd) {
            unawaited(engine.requestStop());
          }
        },
      );

      final result = await engine
          .startBatch(
            _request(
              captureFrameData: true,
              timing: _testTiming(
                frameCaptureStopTimeout: const Duration(milliseconds: 1),
              ),
            ),
          )
          .timeout(const Duration(milliseconds: 100));

      expect(result.outcome, ReplayBatchOutcome.stopped);
      expect(result.replays.single.capture?.error,
          contains('Frame capture stop timed out'));
      expect(capture.stopReasons, [FrameCaptureEndReason.stopped]);
      expect(obs.stopCalls, 1);
      expect(obs.recording, isFalse);
    });

    test('a hung capture start is bounded and does not keep OBS recording',
        () async {
      final capture = _FakeFrameCapture()..neverCompleteOnStart = true;
      final obs = _FakeObs();
      final result = await _engine(
        monitor: _FakeMonitor(_successfulReplaySnapshots()),
        menu: _FakeMenu(),
        obs: obs,
        organizer: _FakeOrganizer(),
        clock: _FakeClock(),
        frameCapturePort: capture,
      ).startBatch(
        _request(
          captureFrameData: true,
          timing: _testTiming(
            frameCaptureStopTimeout: const Duration(milliseconds: 1),
          ),
        ),
      );

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(result.replays.single.status, ReplayResultStatus.recorded);
      expect(result.replays.single.capture?.error,
          contains('Frame capture start timed out'));
      expect(capture.abortCalls, 1);
      expect(obs.stopCalls, 1);
      expect(obs.recording, isFalse);
    });

    test('capture start failure is diagnostic-only and leaves video complete',
        () async {
      final capture = _FakeFrameCapture()..throwOnStart = true;
      final events = <ReplayBatchEvent>[];
      final obs = _FakeObs();
      final engine = _engine(
        monitor: _FakeMonitor(_successfulReplaySnapshots()),
        menu: _FakeMenu(),
        obs: obs,
        organizer: _FakeOrganizer(),
        frameCapturePort: capture,
        onEvent: events.add,
      );

      final result = await engine.startBatch(
        _request(captureFrameData: true),
      );

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(result.replays.single.status, ReplayResultStatus.recorded);
      expect(result.replays.single.capture?.path, isNull);
      expect(result.replays.single.capture?.error,
          contains('synthetic capture start failure'));
      expect(obs.startCalls, 1);
      expect(obs.stopCalls, 1);
      expect(
          events
              .where((event) => event.type == ReplayBatchEventType.diagnostic),
          hasLength(1));
    });

    test('capture stop failure does not change replay or OBS results',
        () async {
      final capture = _FakeFrameCapture()..throwOnStop = true;
      final obs = _FakeObs();
      final result = await _engine(
        monitor: _FakeMonitor(_successfulReplaySnapshots()),
        menu: _FakeMenu(),
        obs: obs,
        organizer: _FakeOrganizer(),
        frameCapturePort: capture,
      ).startBatch(_request(captureFrameData: true));

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(result.replays.single.status, ReplayResultStatus.recorded);
      expect(result.replays.single.capture?.path, isNull);
      expect(result.replays.single.capture?.error,
          contains('synthetic capture stop failure'));
      expect(obs.startCalls, 1);
      expect(obs.stopCalls, 1);
      expect(obs.recording, isFalse);
    });

    test('capture failure keeps a relative partial log path', () async {
      final directory = await Directory.systemTemp.createTemp(
        'afterimage-engine-frame-failure-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final absolutePath = '${directory.path}/replay_001.frames.jsonl';
      final sink = await LinuxFrameCaptureFileSink.create(absolutePath);
      final captureResult = await runLinuxFrameCaptureSession(
        replayIndex: 1,
        source: _MidCaptureFailureSource(),
        sink: sink,
        elapsed: () => Duration.zero,
        delay: (_) async {},
        startedUtc: '2026-10-02T12:00:00Z',
        shouldStop: () => false,
        endReason: () => FrameCaptureEndReason.failed,
        outputPath: absolutePath,
      );
      final capture = _FakeFrameCapture()..stopResult = captureResult;

      expect(captureResult.error, contains('synthetic mid-capture failure'));
      expect(File(absolutePath).readAsLinesSync(), hasLength(2));

      final result = await _engine(
        monitor: _FakeMonitor(_successfulReplaySnapshots()),
        menu: _FakeMenu(),
        obs: _FakeObs(),
        organizer: _FakeOrganizer(),
        frameCapturePort: capture,
      ).startBatch(_request(captureFrameData: true));

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(result.replays.single.capture?.path, 'replay_001.frames.jsonl');
      expect(result.replays.single.capture?.error,
          contains('synthetic mid-capture failure'));
      expect(result.replays.single.capture?.rows, 0);
    });

    test('zero rows with read errors is reported as a capture failure',
        () async {
      final capture = _FakeFrameCapture()
        ..stopResult = const FrameCaptureResult(
          path: '/tmp/afterimage-test/replay_001.frames.jsonl',
          readErrors: 3,
        );
      final result = await _engine(
        monitor: _FakeMonitor(_successfulReplaySnapshots()),
        menu: _FakeMenu(),
        obs: _FakeObs(),
        organizer: _FakeOrganizer(),
        frameCapturePort: capture,
      ).startBatch(_request(captureFrameData: true));

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(result.replays.single.capture?.path, 'replay_001.frames.jsonl');
      expect(
          result.replays.single.capture?.error, contains('memory read errors'));
    });

    test('capture closes on stop, timeout, and replay failure', () async {
      final stoppedCapture = _FakeFrameCapture();
      final stopClock = _FakeClock();
      late ReplayBatchEngine stopEngine;
      stopEngine = _engine(
        monitor: _FakeMonitor(_successfulReplaySnapshots()),
        menu: _FakeMenu(),
        obs: _FakeObs(),
        organizer: _FakeOrganizer(),
        clock: stopClock,
        frameCapturePort: stoppedCapture,
        onEvent: (event) {
          if (event.progress.state == ReplayBatchState.waitingForReplayEnd) {
            unawaited(stopEngine.requestStop());
          }
        },
      );
      final stopped = await stopEngine.startBatch(
        _request(captureFrameData: true),
      );
      expect(stopped.outcome, ReplayBatchOutcome.stopped);
      expect(stoppedCapture.stopCalls, 1);
      expect(stoppedCapture.stopReasons, [FrameCaptureEndReason.stopped]);

      final timeoutCapture = _FakeFrameCapture();
      final timedOut = await _engine(
        monitor: _FakeMonitor(
          [_snapshot(frame: 100), _snapshot(frame: 101)],
          fallback: _snapshot(frame: 101),
        ),
        menu: _FakeMenu(),
        obs: _FakeObs(),
        organizer: _FakeOrganizer(),
        frameCapturePort: timeoutCapture,
      ).startBatch(
        _request(
          captureFrameData: true,
          timing: _testTiming(replayTimeout: const Duration(milliseconds: 2)),
        ),
      );
      expect(timedOut.outcome, ReplayBatchOutcome.failed);
      expect(timeoutCapture.stopCalls, 1);
      expect(timeoutCapture.stopReasons, [FrameCaptureEndReason.timeout]);

      final failureCapture = _FakeFrameCapture();
      final failureSnapshots = <BattleSnapshot>[
        _snapshot(frame: 100),
        _snapshot(frame: 101),
      ];
      final failed = await _engine(
        monitor: _FakeMonitor(failureSnapshots, throwAt: 2),
        menu: _FakeMenu(),
        obs: _FakeObs(),
        organizer: _FakeOrganizer(),
        frameCapturePort: failureCapture,
      ).startBatch(_request(captureFrameData: true));
      expect(failed.outcome, ReplayBatchOutcome.failed);
      expect(failureCapture.stopCalls, 1);
      expect(failureCapture.stopReasons, [FrameCaptureEndReason.failed]);
    });

    test('capture off creates no capture metadata or files', () async {
      final capture = _FakeFrameCapture();
      final result = await _engine(
        monitor: _FakeMonitor(_successfulReplaySnapshots()),
        menu: _FakeMenu(),
        obs: _FakeObs(),
        organizer: _FakeOrganizer(),
        frameCapturePort: capture,
      ).startBatch(_request());

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(capture.startCalls, isEmpty);
      expect(capture.stopCalls, 0);
      expect(result.replays.single.capture, isNull);
    });

    test('summary checkpoints are written after each result and at completion',
        () async {
      final monitor = _FakeMonitor(_successfulBatchSnapshots(2));
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final summaryWriter = _FakeSummaryWriter();
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
        summaryWriter: summaryWriter,
      );

      final result = await engine.startBatch(_request(count: 2));

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(
        summaryWriter.summaries.map((summary) => summary.outcome).toList(),
        [
          ReplaySummaryOutcome.running,
          ReplaySummaryOutcome.running,
          ReplaySummaryOutcome.completed,
        ],
      );
      expect(summaryWriter.summaries[0].replays, hasLength(1));
      expect(summaryWriter.summaries[1].replays, hasLength(2));
      expect(summaryWriter.summaries.last.replays, hasLength(2));
      expect(summaryWriter.closed, isTrue);
    });

    test('a sustained missing-read run completes a started replay', () async {
      final monitor = _FakeMonitor([
        _snapshot(frame: 100),
        _snapshot(frame: 101),
        ...List<BattleSnapshot>.filled(4, const BattleSnapshot.empty()),
        ...List<BattleSnapshot>.filled(4, const BattleSnapshot.empty()),
      ]);
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final events = <ReplayBatchEvent>[];
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
        onEvent: events.add,
      );

      final result = await engine.startBatch(_request());

      expect(result.outcome, ReplayBatchOutcome.completed);
      expect(result.replays.single.status, ReplayResultStatus.recorded);
      expect(
        events
            .where(
                (event) => event.type == ReplayBatchEventType.replayCompleted)
            .single
            .message,
        contains('sustained missing battle state'),
      );
      expect(obs.startCalls, 1);
      expect(obs.stopCalls, 1);
      expect(organizer.replayCalls.single.partial, isFalse);
    });

    test('a failure after battle start stops and preserves a partial replay',
        () async {
      final monitor = _FakeMonitor(
        [
          _snapshot(frame: 100),
          _snapshot(frame: 101),
        ],
        throwAt: 2,
      );
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
      );

      final result = await engine.startBatch(_request());

      expect(result.outcome, ReplayBatchOutcome.failed);
      expect(result.replays.single.status, ReplayResultStatus.failed);
      expect(result.replays.single.output?.partial, isTrue);
      expect(result.replays.single.sourceOutput?.path, 'obs_1.mp4');
      expect(obs.startCalls, 1);
      expect(obs.stopCalls, 1);
      expect(organizer.replayCalls.single.partial, isTrue);
      expect(menu.actions, [ReplayMenuAction.openReplay]);
      expect(obs.recording, isFalse);
    });

    test('a return-to-list timeout fails after saving the current replay',
        () async {
      final monitor = _FakeMonitor(
        [
          _snapshot(frame: 100),
          _snapshot(frame: 101),
          _snapshot(frame: 101, events: {matchResultEventType}),
        ],
        fallback: _snapshot(frame: 900),
      );
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
      );

      final result = await engine.startBatch(
        _request(
          timing:
              _testTiming(returnToListTimeout: const Duration(milliseconds: 4)),
        ),
      );

      expect(result.outcome, ReplayBatchOutcome.failed);
      expect(result.replays.single.status, ReplayResultStatus.failed);
      expect(result.replays.single.output?.partial, isFalse);
      expect(result.replays.single.error, isNotNull);
      expect(obs.stopCalls, 1);
      expect(menu.actions, [
        ReplayMenuAction.openReplay,
        ReplayMenuAction.exitToReplayList,
      ]);
      expect(
        menu.actions.contains(ReplayMenuAction.selectNextReplay),
        isFalse,
      );
    });

    test('wrong foreground window prevents recording and menu input', () async {
      final monitor = _FakeMonitor(_successfulReplaySnapshots());
      final menu = _GuardedMenu()..safe = false;
      final obs = _FakeObs();
      final engine = _engine(
          monitor: monitor, menu: menu, obs: obs, organizer: _FakeOrganizer());
      final result = await engine.startBatch(_request());
      expect(obs.startCalls, 0,
          reason:
              'An unsafe foreground window must prevent starting OBS recording');
      expect(menu.actions, isEmpty);
      expect(result.outcome, ReplayBatchOutcome.failed);
    });

    test(
        'focus lost during playback preserves partial output without menu input',
        () async {
      final monitor = _FakeMonitor(_successfulReplaySnapshots());
      final menu = _GuardedMenu();
      final obs = _FakeObs();
      final engine = _engine(
          monitor: monitor,
          menu: menu,
          obs: obs,
          organizer: _FakeOrganizer(),
          onEvent: (event) {
            if (event.progress.state == ReplayBatchState.waitingForReplayEnd) {
              menu.safe = false;
            }
          });
      final result = await engine.startBatch(_request());
      expect(result.outcome, ReplayBatchOutcome.failed,
          reason:
              'Losing game focus must fail safely instead of continuing the batch');
      expect(result.replays.single.output?.partial, isTrue);
      expect(obs.stopCalls, 1);
      expect(menu.actions, [ReplayMenuAction.openReplay]);
    });

    test('a stop request preserves the active replay as partial output',
        () async {
      final monitor = _FakeMonitor([
        _snapshot(frame: 100),
        _snapshot(frame: 101),
        _snapshot(frame: 101, events: {matchResultEventType}),
      ]);
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final clock = _FakeClock();
      late ReplayBatchEngine engine;
      engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
        clock: clock,
        onEvent: (event) {
          if (event.progress.state == ReplayBatchState.waitingForReplayEnd) {
            unawaited(engine.requestStop());
          }
        },
      );

      final result = await engine.startBatch(_request());

      expect(result.outcome, ReplayBatchOutcome.stopped);
      expect(result.replays.single.status, ReplayResultStatus.stopped);
      expect(result.replays.single.output?.partial, isTrue);
      expect(result.replays.single.sourceOutput?.path, 'obs_1.mp4');
      expect(obs.stopCalls, 1);
      expect(menu.actions, [ReplayMenuAction.openReplay]);
      expect(organizer.replayCalls.single.partial, isTrue);
    });

    test('combined failure preserves one partial batch output', () async {
      final firstReplay = _successfulReplaySnapshots();
      final monitor = _FakeMonitor(
        [
          ...firstReplay,
          _snapshot(frame: 100),
          _snapshot(frame: 101),
        ],
        throwAt: firstReplay.length + 2,
      );
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
      );

      final result = await engine.startBatch(
        _request(count: 2, videoMode: VideoMode.combined),
      );

      expect(result.outcome, ReplayBatchOutcome.failed);
      expect(result.replays, hasLength(2));
      expect(result.replays.first.status, ReplayResultStatus.recorded);
      expect(result.replays.last.status, ReplayResultStatus.failed);
      expect(obs.startCalls, 1);
      expect(obs.stopCalls, 1);
      expect(result.combinedOutput?.partial, isTrue);
      expect(organizer.combinedCalls.single.partial, isTrue);
      expect(menu.actions, [
        ReplayMenuAction.openReplay,
        ReplayMenuAction.exitToReplayList,
        ReplayMenuAction.selectNextReplay,
        ReplayMenuAction.openReplay,
      ]);
    });

    test('combined stop reports an OBS stop failure', () async {
      final monitor = _FakeMonitor([
        _snapshot(frame: 100),
        _snapshot(frame: 101),
      ]);
      final menu = _FakeMenu();
      final obs = _FakeObs()..throwOnStop = true;
      final organizer = _FakeOrganizer();
      final clock = _FakeClock();
      late ReplayBatchEngine engine;
      clock.onDelay = (call) {
        if (call == 2) {
          unawaited(engine.requestStop());
        }
      };
      engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
        clock: clock,
      );

      final result = await engine.startBatch(
        _request(videoMode: VideoMode.combined),
      );

      expect(result.outcome, ReplayBatchOutcome.stopped);
      expect(result.error.toString(), contains('synthetic OBS stop failure'));
      expect(obs.recording, isTrue);
      expect(obs.stopCalls, 1);
      expect(organizer.combinedCalls, isEmpty);
    });

    test('an organizer failure keeps the OBS source path recoverable',
        () async {
      final monitor = _FakeMonitor(
        [
          _snapshot(frame: 100),
          _snapshot(frame: 101),
        ],
        throwAt: 2,
      );
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer()..throwReplay = true;
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
      );

      final result = await engine.startBatch(_request());

      expect(result.outcome, ReplayBatchOutcome.failed);
      expect(result.replays.single.output, isNull);
      expect(result.replays.single.sourceOutput?.path, 'obs_1.mp4');
      expect(result.replays.single.error, isNotNull);
      expect(organizer.replayCalls.single.partial, isTrue);
    });

    test('invalid requests fail before any platform port is used', () async {
      final monitor = _FakeMonitor(const []);
      final menu = _FakeMenu();
      final obs = _FakeObs();
      final organizer = _FakeOrganizer();
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: organizer,
      );

      final result = await engine.startBatch(
        _request(count: 0),
      );

      expect(result.outcome, ReplayBatchOutcome.failed);
      expect(monitor.attached, isFalse);
      expect(obs.assertIdleCalls, 0);
      expect(menu.actions, isEmpty);
    });

    test('close failures do not replace the primary batch error', () async {
      final monitor = _FakeMonitor(
        [
          _snapshot(frame: 100),
          _snapshot(frame: 101),
        ],
        throwAt: 2,
      )..throwOnClose = true;
      final menu = _FakeMenu();
      final obs = _FakeObs()..throwOnClose = true;
      final engine = _engine(
        monitor: monitor,
        menu: menu,
        obs: obs,
        organizer: _FakeOrganizer(),
      );

      final result = await engine.startBatch(_request());

      expect(result.outcome, ReplayBatchOutcome.failed);
      expect(result.error.toString(), contains('synthetic monitor read'));
      expect(result.error.toString(), isNot(contains('close failed')));
      expect(monitor.closed, isTrue);
      expect(obs.closeCalls, 1);
      expect(engine.isRunning, isFalse);
    });
  });
}

BattleSnapshot _snapshot({
  required int frame,
  Set<int> events = const <int>{},
}) {
  return BattleSnapshot(
    enginePresent: true,
    frame: frame,
    events: events,
  );
}

List<BattleSnapshot> _successfulReplaySnapshots({bool noisyList = false}) {
  return [
    _snapshot(frame: 100),
    _snapshot(frame: 101),
    _snapshot(frame: 101, events: {matchResultEventType}),
    if (noisyList) _snapshot(frame: 900),
    ...List<BattleSnapshot>.filled(4, const BattleSnapshot.empty()),
  ];
}

List<BattleSnapshot> _successfulBatchSnapshots(
  int count, {
  bool noisyFirstList = false,
}) {
  final snapshots = <BattleSnapshot>[];
  for (var index = 0; index < count; index++) {
    snapshots.addAll(
      _successfulReplaySnapshots(
        noisyList: noisyFirstList && index == 0,
      ),
    );
  }
  return snapshots;
}

ReplayBatchRequest _request({
  int count = 1,
  VideoMode videoMode = VideoMode.separate,
  bool captureFrameData = false,
  ReplayBatchTiming? timing,
}) {
  return ReplayBatchRequest(
    replayCount: count,
    options: RecordingOptions(
      videoMode: videoMode,
      outputDirectory: '/tmp/afterimage-test',
      captureFrameData: captureFrameData,
    ),
    timing: timing ?? _testTiming(),
  );
}

ReplayBatchTiming _testTiming({
  Duration returnToListTimeout = const Duration(milliseconds: 20),
  Duration replayTimeout = const Duration(milliseconds: 20),
  Duration resultDelay = Duration.zero,
  Duration frameCaptureStopTimeout = const Duration(seconds: 3),
}) {
  return ReplayBatchTiming(
    pollInterval: const Duration(milliseconds: 1),
    startTimeout: const Duration(milliseconds: 20),
    replayTimeout: replayTimeout,
    returnToListTimeout: returnToListTimeout,
    resultDelay: resultDelay,
    startupDelay: Duration.zero,
    menuDelay: Duration.zero,
    actionDelay: Duration.zero,
    frameCaptureStopTimeout: frameCaptureStopTimeout,
    absentReadWindow: const Duration(milliseconds: 1),
  );
}

ReplayBatchEngine _engine({
  required _FakeMonitor monitor,
  required _FakeMenu menu,
  required _FakeObs obs,
  required _FakeOrganizer organizer,
  ReplayClock? clock,
  ReplayBatchEventSink? onEvent,
  SummaryWriterPort? summaryWriter,
  FrameCapturePort? frameCapturePort,
}) {
  return ReplayBatchEngine(
    monitor: monitor,
    menuInput: menu,
    obs: obs,
    organizer: organizer,
    clock: clock ?? _FakeClock(),
    summaryWriter: summaryWriter,
    frameCapturePort: frameCapturePort,
    onEvent: onEvent,
  );
}

class _FakeClock implements ReplayClock {
  Duration _elapsed = Duration.zero;
  int delayCalls = 0;
  void Function(int call)? onDelay;
  void Function(Duration duration)? onDelayDuration;
  final List<Duration> delays = [];

  @override
  Duration get elapsed => _elapsed;

  void advance(Duration duration) {
    _elapsed += duration;
  }

  @override
  Future<void> delay(Duration duration) async {
    if (duration < Duration.zero) {
      throw ArgumentError.value(duration, 'duration');
    }
    _elapsed += duration;
    delayCalls++;
    delays.add(duration);
    onDelay?.call(delayCalls);
    onDelayDuration?.call(duration);
  }
}

class _FakeMonitor implements ReplayMonitorPort {
  _FakeMonitor(
    Iterable<BattleSnapshot> snapshots, {
    this.fallback = const BattleSnapshot.empty(),
    this.throwAt,
  }) : _snapshots = [...snapshots];

  final List<BattleSnapshot> _snapshots;
  final BattleSnapshot fallback;
  final int? throwAt;
  bool attached = false;
  bool closed = false;
  bool throwOnClose = false;
  int snapshotsRead = 0;

  @override
  Future<void> attach() async {
    attached = true;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (throwOnClose) {
      throw StateError('synthetic monitor close failed');
    }
  }

  @override
  Future<BattleSnapshot> snapshot() async {
    if (throwAt != null && snapshotsRead >= throwAt!) {
      throw StateError('synthetic monitor read failure');
    }
    snapshotsRead++;
    if (_snapshots.isEmpty) {
      return fallback;
    }
    return _snapshots.removeAt(0);
  }
}

class _FakeMenu implements MenuInputPort {
  final List<ReplayMenuAction> actions = [];
  void Function(ReplayMenuAction action)? onPerform;

  @override
  Future<void> perform(ReplayMenuAction action) async {
    actions.add(action);
    onPerform?.call(action);
  }
}

class _FakeObs implements ObsRecorderPort {
  bool recording = false;
  int connectCalls = 0;
  int closeCalls = 0;
  int assertIdleCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  bool throwOnClose = false;
  bool throwOnStop = false;
  void Function()? onStart;

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  Future<void> assertIdle() async {
    assertIdleCalls++;
    if (recording) {
      throw StateError('synthetic OBS was already recording');
    }
  }

  @override
  Future<void> startRecording() async {
    if (recording) {
      throw StateError('synthetic OBS start was duplicated');
    }
    recording = true;
    startCalls++;
    onStart?.call();
  }

  @override
  Future<RecordedOutput> stopRecording() async {
    if (!recording) {
      throw StateError('synthetic OBS stop had no active recording');
    }
    stopCalls++;
    if (throwOnStop) {
      throw StateError('synthetic OBS stop failure');
    }
    recording = false;
    return RecordedOutput('obs_$stopCalls.mp4');
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (throwOnClose) {
      throw StateError('synthetic OBS close failed');
    }
  }
}

class _MidCaptureFailureSource implements LinuxFrameCaptureSource {
  bool _failed = false;

  @override
  int? readFrame() {
    if (_failed) {
      throw StateError('synthetic mid-capture failure');
    }
    _failed = true;
    return 100;
  }

  @override
  LinuxFrameRowRead readRow(int expectedFrame, int elapsedMicros) =>
      const LinuxFrameRowRead(
        row: <String, Object?>{'type': 'frame', 'f': 100, 't': 0},
      );
}

class _FakeFrameCapture implements FrameCapturePort, AbortableFrameCapturePort {
  _FakeFrameCapture({this.onStart, this.onStop});

  final void Function()? onStart;
  final void Function()? onStop;
  final List<_FrameCaptureStart> startCalls = [];
  final List<FrameCaptureEndReason> stopReasons = [];
  int stopCalls = 0;
  int closeCalls = 0;
  bool throwOnStart = false;
  bool throwOnStop = false;
  bool neverCompleteOnStart = false;
  bool neverCompleteOnStop = false;
  FrameCaptureResult? stopResult;
  int abortCalls = 0;
  Completer<void>? _startCompletion;

  @override
  Future<void> start({
    required int replayIndex,
    required String outputPath,
    int? gWorldPointerAddress,
  }) async {
    startCalls.add(_FrameCaptureStart(replayIndex, outputPath));
    onStart?.call();
    if (throwOnStart) {
      throw StateError('synthetic capture start failure');
    }
    if (neverCompleteOnStart) {
      _startCompletion = Completer<void>();
      return _startCompletion!.future;
    }
  }

  @override
  Future<FrameCaptureResult> stop({
    required FrameCaptureEndReason reason,
  }) async {
    stopCalls++;
    stopReasons.add(reason);
    onStop?.call();
    if (neverCompleteOnStop) {
      return Completer<FrameCaptureResult>().future;
    }
    if (throwOnStop) {
      throw StateError('synthetic capture stop failure');
    }
    return stopResult ??
        const FrameCaptureResult(rows: 3, frameGaps: 1, maxFrameGap: 1);
  }

  @override
  Future<FrameCaptureResult> abort() async {
    abortCalls++;
    _startCompletion?.complete();
    return const FrameCaptureResult(
      path: '/tmp/afterimage-test/replay_001.frames.jsonl',
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

class _FrameCaptureStart {
  const _FrameCaptureStart(this.replayIndex, this.outputPath);

  final int replayIndex;
  final String outputPath;
}

class _FakeSummaryWriter implements ClosableSummaryWriterPort {
  final List<ReplayBatchSummary> summaries = [];
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> write({
    required String outputDirectory,
    required ReplayBatchSummary summary,
  }) async {
    summaries.add(summary);
  }
}

class _FakeOrganizer implements OutputOrganizerPort {
  final List<_ReplayOrganization> replayCalls = [];
  final List<_CombinedOrganization> combinedCalls = [];
  bool throwReplay = false;
  bool throwCombined = false;

  @override
  Future<OrganizedOutput> organizeReplay({
    required RecordedOutput source,
    required String outputDirectory,
    required int replayIndex,
    required bool partial,
  }) async {
    replayCalls.add(
      _ReplayOrganization(
        source: source,
        outputDirectory: outputDirectory,
        replayIndex: replayIndex,
        partial: partial,
      ),
    );
    if (throwReplay) {
      throw StateError('synthetic replay organization failure');
    }
    return OrganizedOutput(
      path: 'replay_${replayIndex}_${partial ? 'partial' : 'complete'}.mp4',
      partial: partial,
      replayIndex: replayIndex,
    );
  }

  @override
  Future<OrganizedOutput> organizeCombined({
    required RecordedOutput source,
    required String outputDirectory,
    required bool partial,
  }) async {
    combinedCalls.add(
      _CombinedOrganization(
        source: source,
        outputDirectory: outputDirectory,
        partial: partial,
      ),
    );
    if (throwCombined) {
      throw StateError('synthetic combined organization failure');
    }
    return OrganizedOutput(
      path: 'combined_${combinedCalls.length}.mp4',
      partial: partial,
    );
  }
}

class _ReplayOrganization {
  const _ReplayOrganization({
    required this.source,
    required this.outputDirectory,
    required this.replayIndex,
    required this.partial,
  });

  final RecordedOutput source;
  final String outputDirectory;
  final int replayIndex;
  final bool partial;
}

class _CombinedOrganization {
  const _CombinedOrganization({
    required this.source,
    required this.outputDirectory,
    required this.partial,
  });

  final RecordedOutput source;
  final String outputDirectory;
  final bool partial;
}

class _GuardedMenu extends _FakeMenu implements InputSafetyPort {
  bool safe = true;
  @override
  void assertInputSafe() {
    if (!safe) throw StateError('GGST is no longer the active window.');
  }
}
