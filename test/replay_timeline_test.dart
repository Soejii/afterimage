import 'package:flutter_test/flutter_test.dart';

import 'package:afterimage/domain/replay_batch.dart';
import 'package:afterimage/presentation/replay_timeline.dart';

void main() {
  group('timelineFromOutcomes', () {
    test('marks finished, current and pending replays', () {
      const progress = ReplayBatchProgress(
        state: ReplayBatchState.recordingReplay,
        totalReplays: 4,
        currentReplay: 3,
        completedReplays: 2,
      );
      final rows = timelineFromOutcomes(
        _outcomesFrom([
          _event(ReplayBatchEventType.replayCompleted, 1, progress),
          _event(ReplayBatchEventType.replayCompleted, 2, progress),
        ]),
        progress,
      );

      expect(rows.map((row) => row.status), [
        ReplayRowStatus.done,
        ReplayRowStatus.done,
        ReplayRowStatus.active,
        ReplayRowStatus.pending,
      ]);
    });

    test('a replayFailed event marks that replay failed while it runs', () {
      // The engine emits `replayFailed`, not `replayCompleted` with an error
      // attached. Reading only `replayCompleted` left a replay that failed
      // mid-batch rendered as though it were still waiting its turn.
      const progress = ReplayBatchProgress(
        state: ReplayBatchState.recordingReplay,
        totalReplays: 2,
        currentReplay: 2,
        completedReplays: 1,
      );
      final rows = timelineFromOutcomes(
        _outcomesFrom([
          _event(ReplayBatchEventType.replayFailed, 1, progress,
              message: 'Replay 1 failed safely.'),
        ]),
        progress,
      );

      expect(rows.first.status, ReplayRowStatus.failed);
      expect(rows.first.detail, 'Replay 1 failed safely.');
    });

    test('a replayStopped event marks that replay stopped', () {
      const progress = ReplayBatchProgress(
        state: ReplayBatchState.stoppingRecording,
        totalReplays: 2,
        currentReplay: 1,
        completedReplays: 0,
      );
      final rows = timelineFromOutcomes(
        _outcomesFrom([
          _event(ReplayBatchEventType.replayStopped, 1, progress,
              message: 'Replay 1 stopped safely.'),
        ]),
        progress,
      );

      expect(rows.first.status, ReplayRowStatus.stopped);
    });

    test('events that say nothing about a replay leave its row alone', () {
      const progress = ReplayBatchProgress(
        state: ReplayBatchState.recordingReplay,
        totalReplays: 2,
        currentReplay: 1,
        completedReplays: 0,
      );
      final rows = timelineFromOutcomes(
        _outcomesFrom([
          _event(ReplayBatchEventType.replayStarted, 1, progress),
          _event(ReplayBatchEventType.battleStarted, 1, progress),
          _event(ReplayBatchEventType.outputSaved, 1, progress),
        ]),
        progress,
      );

      expect(rows.first.status, ReplayRowStatus.active);
    });

    test('an unstarted batch has no rows', () {
      const progress = ReplayBatchProgress(
        state: ReplayBatchState.idle,
        totalReplays: 0,
        currentReplay: 0,
        completedReplays: 0,
      );
      expect(timelineFromOutcomes(const {}, progress), isEmpty);
    });
  });

  group('timelineFromResult', () {
    test('carries each terminal replay status through', () {
      const result = ReplayBatchResult(
        outcome: ReplayBatchOutcome.stopped,
        replays: [
          ReplayResult(index: 1, status: ReplayResultStatus.recorded),
          ReplayResult(index: 2, status: ReplayResultStatus.failed),
          ReplayResult(index: 3, status: ReplayResultStatus.stopped),
        ],
      );

      expect(timelineFromResult(result).map((row) => row.status), [
        ReplayRowStatus.done,
        ReplayRowStatus.failed,
        ReplayRowStatus.stopped,
      ]);
    });
  });

  group('phaseLabelFor', () {
    test('collapses the engine states into a few user-facing phases', () {
      // The engine distinguishes twelve states because it needs to. A person
      // watching a batch does not, so several must share one label.
      expect(
        phaseLabelFor(ReplayBatchState.openingReplay),
        phaseLabelFor(ReplayBatchState.waitingForBattleStart),
      );
      expect(
        phaseLabelFor(ReplayBatchState.recordingReplay),
        phaseLabelFor(ReplayBatchState.waitingForReplayEnd),
      );
      expect(phaseLabelFor(ReplayBatchState.recordingReplay), 'Recording');
    });

    test('every engine state has a label', () {
      for (final state in ReplayBatchState.values) {
        expect(phaseLabelFor(state), isNotEmpty, reason: state.name);
      }
    });
  });

  group('formatElapsed', () {
    test('drops the hour field under an hour', () {
      expect(formatElapsed(const Duration(seconds: 9)), '0:09');
      expect(formatElapsed(const Duration(minutes: 7, seconds: 5)), '7:05');
    });

    test('shows hours for a long batch', () {
      expect(
        formatElapsed(const Duration(hours: 2, minutes: 4, seconds: 6)),
        '2:04:06',
      );
    });
  });
}

ReplayBatchEvent _event(
  ReplayBatchEventType type,
  int index,
  ReplayBatchProgress progress, {
  String? message,
}) {
  return ReplayBatchEvent(
    type: type,
    progress: progress,
    replayIndex: index,
    message: message,
  );
}

/// Runs events through the same reducer the controller uses, so these tests
/// exercise the real event handling rather than a hand-built outcome map.
Map<int, ReplayOutcome> _outcomesFrom(List<ReplayBatchEvent> events) {
  final outcomes = <int, ReplayOutcome>{};
  for (final event in events) {
    final index = event.replayIndex;
    if (index == null) continue;
    final outcome = outcomeFromEvent(event);
    if (outcome != null) outcomes[index] = outcome;
  }
  return outcomes;
}
