import 'replay_batch.dart';

enum ReplaySummaryOutcome {
  running,
  completed,
  failed,
  stopped,
}

class ReplaySummaryEntry {
  const ReplaySummaryEntry({
    required this.index,
    required this.status,
    this.sourcePath,
    this.outputPath,
    this.partial,
    this.error,
  });

  factory ReplaySummaryEntry.fromResult(ReplayResult result) {
    return ReplaySummaryEntry(
      index: result.index,
      status: result.status.name,
      sourcePath: result.sourceOutput?.path,
      outputPath: result.output?.path,
      partial: result.output?.partial,
      error: result.error?.toString(),
    );
  }

  final int index;
  final String status;
  final String? sourcePath;
  final String? outputPath;
  final bool? partial;
  final String? error;

  Map<String, Object?> toJson() {
    return {
      'index': index,
      'status': status,
      'source': sourcePath,
      'output': outputPath,
      'partial': partial,
      'error': error,
    };
  }
}

class ReplayBatchSummary {
  const ReplayBatchSummary({
    required this.updatedAt,
    required this.outcome,
    required this.replays,
    this.combinedSourcePath,
    this.combinedOutputPath,
    this.combinedPartial,
    this.error,
  });

  factory ReplayBatchSummary.fromResults({
    required DateTime updatedAt,
    required ReplaySummaryOutcome outcome,
    required Iterable<ReplayResult> replays,
    OrganizedOutput? combinedOutput,
    RecordedOutput? combinedSourceOutput,
    Object? error,
  }) {
    return ReplayBatchSummary(
      updatedAt: updatedAt,
      outcome: outcome,
      replays:
          replays.map(ReplaySummaryEntry.fromResult).toList(growable: false),
      combinedSourcePath: combinedSourceOutput?.path,
      combinedOutputPath: combinedOutput?.path,
      combinedPartial: combinedOutput?.partial,
      error: error?.toString(),
    );
  }

  final DateTime updatedAt;
  final ReplaySummaryOutcome outcome;
  final List<ReplaySummaryEntry> replays;
  final String? combinedSourcePath;
  final String? combinedOutputPath;
  final bool? combinedPartial;
  final String? error;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'outcome': outcome.name,
      'replays': replays.map((replay) => replay.toJson()).toList(),
      'combinedSource': combinedSourcePath,
      'combinedOutput': combinedOutputPath,
      'combinedPartial': combinedPartial,
      'error': error,
    };
  }
}
