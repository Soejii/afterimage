import 'setup_models.dart';

const int matchResultEventType = 15;

class BattleSnapshot {
  BattleSnapshot({
    required this.enginePresent,
    required this.frame,
    required Set<int> events,
  }) : events = Set.unmodifiable(events);

  const BattleSnapshot.empty()
      : enginePresent = false,
        frame = null,
        events = const <int>{};

  final bool enginePresent;
  final int? frame;
  final Set<int> events;
}

enum ReplayCompletionReason {
  matchResultEvent,
  battleStateDisappeared,
}

/// Detects replay completion from noisy snapshots without treating a pause as
/// the end of a battle.
class ReplayCompletionDetector {
  ReplayCompletionDetector({required this.absentPollsRequired}) {
    if (absentPollsRequired <= 0) {
      throw ArgumentError.value(
        absentPollsRequired,
        'absentPollsRequired',
        'must be greater than zero',
      );
    }
  }

  final int absentPollsRequired;
  int? lastFrame;
  bool battleStarted = false;
  int absentPolls = 0;
  ReplayCompletionReason? reason;

  bool observe(BattleSnapshot snapshot) {
    if (snapshot.enginePresent && snapshot.frame != null) {
      absentPolls = 0;
      if (lastFrame != null && snapshot.frame != lastFrame) {
        battleStarted = true;
      }
      lastFrame = snapshot.frame;
    } else if (battleStarted) {
      absentPolls++;
    }

    if (!battleStarted) {
      return false;
    }
    if (snapshot.events.contains(matchResultEventType)) {
      reason = ReplayCompletionReason.matchResultEvent;
      return true;
    }
    if (absentPolls >= absentPollsRequired) {
      reason = ReplayCompletionReason.battleStateDisappeared;
      return true;
    }
    return false;
  }
}

int absentPollsForInterval(
  Duration pollInterval, {
  Duration absentReadWindow = const Duration(seconds: 3),
}) {
  if (pollInterval <= Duration.zero) {
    throw ArgumentError.value(
      pollInterval,
      'pollInterval',
      'must be greater than zero',
    );
  }
  if (absentReadWindow <= Duration.zero) {
    throw ArgumentError.value(
      absentReadWindow,
      'absentReadWindow',
      'must be greater than zero',
    );
  }
  final intervalMicros = pollInterval.inMicroseconds;
  final windowMicros = absentReadWindow.inMicroseconds;
  final roundedUp = (windowMicros + intervalMicros - 1) ~/ intervalMicros;
  return roundedUp < 4 ? 4 : roundedUp;
}

class ReplayBatchTiming {
  const ReplayBatchTiming({
    this.pollInterval = const Duration(milliseconds: 10),
    this.startTimeout = const Duration(seconds: 45),
    this.replayTimeout = const Duration(minutes: 30),
    this.returnToListTimeout = const Duration(seconds: 20),
    this.resultDelay = const Duration(seconds: 7),
    this.startupDelay = const Duration(seconds: 5),
    this.menuDelay = const Duration(seconds: 2),
    this.actionDelay = const Duration(milliseconds: 800),
    this.absentReadWindow = const Duration(seconds: 3),
    this.listConfirmationPolls = 4,
  });

  final Duration pollInterval;
  final Duration startTimeout;
  final Duration replayTimeout;
  final Duration returnToListTimeout;
  final Duration resultDelay;
  final Duration startupDelay;
  final Duration menuDelay;
  final Duration actionDelay;
  final Duration absentReadWindow;
  final int listConfirmationPolls;

  int get absentPollsRequired =>
      absentPollsForInterval(pollInterval, absentReadWindow: absentReadWindow);
}

enum ReplayBatchState {
  idle,
  preparing,
  startingRecording,
  openingReplay,
  waitingForBattleStart,
  recordingReplay,
  waitingForReplayEnd,
  stoppingRecording,
  returningToReplayList,
  completed,
  failed,
  stopped,
}

enum ReplayBatchOutcome {
  completed,
  failed,
  stopped,
}

enum ReplayBatchEventType {
  started,
  stateChanged,
  replayStarted,
  battleStarted,
  replayCompleted,
  outputSaved,
  replayFailed,
  replayStopped,
  stopped,
  completed,
  failed,
}

class ReplayBatchProgress {
  const ReplayBatchProgress({
    required this.state,
    required this.totalReplays,
    required this.currentReplay,
    required this.completedReplays,
    this.detail,
    this.outputPath,
  });

  final ReplayBatchState state;
  final int totalReplays;
  final int currentReplay;
  final int completedReplays;
  final String? detail;
  final String? outputPath;

  double get fraction {
    if (totalReplays <= 0) {
      return 0;
    }
    return (completedReplays / totalReplays).clamp(0, 1).toDouble();
  }
}

class ReplayBatchEvent {
  const ReplayBatchEvent({
    required this.type,
    required this.progress,
    this.replayIndex,
    this.message,
    this.error,
    this.output,
  });

  final ReplayBatchEventType type;
  final ReplayBatchProgress progress;
  final int? replayIndex;
  final String? message;
  final Object? error;
  final OrganizedOutput? output;
}

class RecordedOutput {
  const RecordedOutput(this.path);

  final String path;
}

class OrganizedOutput {
  const OrganizedOutput({
    required this.path,
    required this.partial,
    this.replayIndex,
  });

  final String path;
  final bool partial;
  final int? replayIndex;
}

enum ReplayResultStatus {
  recorded,
  failed,
  stopped,
}

class ReplayResult {
  const ReplayResult({
    required this.index,
    required this.status,
    this.output,
    this.sourceOutput,
    this.error,
  });

  final int index;
  final ReplayResultStatus status;
  final OrganizedOutput? output;
  final RecordedOutput? sourceOutput;
  final Object? error;
}

class ReplayBatchResult {
  const ReplayBatchResult({
    required this.outcome,
    required this.replays,
    this.combinedOutput,
    this.combinedSourceOutput,
    this.error,
  });

  final ReplayBatchOutcome outcome;
  final List<ReplayResult> replays;
  final OrganizedOutput? combinedOutput;
  final RecordedOutput? combinedSourceOutput;
  final Object? error;

  bool get succeeded => outcome == ReplayBatchOutcome.completed;
}

class ReplayBatchRequest {
  const ReplayBatchRequest({
    required this.replayCount,
    required this.options,
    this.timing = const ReplayBatchTiming(),
  });

  final int replayCount;
  final RecordingOptions options;
  final ReplayBatchTiming timing;
}
