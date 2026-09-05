import '../domain/replay_batch.dart';

enum ReplayRowStatus { done, failed, stopped, active, pending }

/// One replay's line in the batch timeline.
class ReplayRow {
  const ReplayRow({
    required this.index,
    required this.status,
    this.detail,
  });

  final int index;
  final ReplayRowStatus status;
  final String? detail;
}

/// What the engine reported about one replay, kept beyond the event buffer.
class ReplayOutcome {
  const ReplayOutcome(this.status, [this.detail]);

  final ReplayRowStatus status;
  final String? detail;
}

/// Records what an engine event says about a replay, if anything.
///
/// The engine reports three different terminal events per replay, not one.
/// Reading only `replayCompleted` leaves a replay that failed live rendered as
/// though it were still waiting.
ReplayOutcome? outcomeFromEvent(ReplayBatchEvent event) {
  switch (event.type) {
    case ReplayBatchEventType.replayCompleted:
      return const ReplayOutcome(ReplayRowStatus.done);
    case ReplayBatchEventType.replayFailed:
      return ReplayOutcome(ReplayRowStatus.failed, event.message);
    case ReplayBatchEventType.replayStopped:
      return ReplayOutcome(ReplayRowStatus.stopped, event.message);
    case ReplayBatchEventType.started:
    case ReplayBatchEventType.stateChanged:
    case ReplayBatchEventType.replayStarted:
    case ReplayBatchEventType.battleStarted:
    case ReplayBatchEventType.outputSaved:
    case ReplayBatchEventType.stopped:
    case ReplayBatchEventType.completed:
    case ReplayBatchEventType.failed:
      return null;
  }
}

/// Builds the per-replay timeline from the outcomes the controller has kept.
///
/// This deliberately does not read the controller's event list. That list is a
/// bounded ring buffer, so on a long batch the earliest `replayCompleted`
/// events are evicted and finished replays would silently revert to "waiting"
/// while the progress counters kept climbing.
List<ReplayRow> timelineFromOutcomes(
  Map<int, ReplayOutcome> outcomes,
  ReplayBatchProgress progress,
) {
  final total = progress.totalReplays;
  if (total <= 0) {
    return const [];
  }

  return [
    for (var index = 1; index <= total; index++)
      ReplayRow(
        index: index,
        status: outcomes[index]?.status ??
            (index == progress.currentReplay
                ? ReplayRowStatus.active
                : ReplayRowStatus.pending),
        detail: outcomes[index]?.detail,
      ),
  ];
}

/// Builds the timeline from a finished batch, so the Done state keeps showing
/// the same list the user watched while it ran.
List<ReplayRow> timelineFromResult(ReplayBatchResult result) {
  return [
    for (final replay in result.replays)
      ReplayRow(
        index: replay.index,
        status: switch (replay.status) {
          ReplayResultStatus.recorded => ReplayRowStatus.done,
          ReplayResultStatus.failed => ReplayRowStatus.failed,
          ReplayResultStatus.stopped => ReplayRowStatus.stopped,
        },
        detail: replay.error?.toString(),
      ),
  ];
}

/// Collapses the engine's twelve states into the four things a user needs to
/// know is happening.
///
/// `waitingForBattleStart` versus `openingReplay` is a distinction the engine
/// needs and a person does not.
String phaseLabelFor(ReplayBatchState state) {
  switch (state) {
    case ReplayBatchState.idle:
    case ReplayBatchState.preparing:
    case ReplayBatchState.startingRecording:
      return 'Getting ready';
    case ReplayBatchState.openingReplay:
    case ReplayBatchState.waitingForBattleStart:
      return 'Opening the replay';
    case ReplayBatchState.recordingReplay:
    case ReplayBatchState.waitingForReplayEnd:
      return 'Recording';
    case ReplayBatchState.stoppingRecording:
    case ReplayBatchState.returningToReplayList:
      return 'Returning to the replay list';
    case ReplayBatchState.completed:
      return 'Finished';
    case ReplayBatchState.failed:
      return 'Stopped after a failure';
    case ReplayBatchState.stopped:
      return 'Stopped';
  }
}

/// Formats an elapsed duration as `h:mm:ss`, or `m:ss` under an hour.
String formatElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  final paddedSeconds = remainder.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
  }
  return '$minutes:$paddedSeconds';
}
