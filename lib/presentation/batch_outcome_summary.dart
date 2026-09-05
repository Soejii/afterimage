import 'package:flutter/material.dart';

import '../domain/replay_batch.dart';
import 'widgets/status_surface.dart';

/// How a finished batch is described, computed once.
///
/// The header badge and the result panel both have to describe the same
/// terminal batch, and when each worked it out for itself they disagreed: a
/// stop whose output could not be saved rendered an amber "STOPPED" above a red
/// "Stopped, but saving needs attention". Interpreting a result is now done
/// here, once, and both read the answer.
class BatchOutcomeSummary {
  const BatchOutcomeSummary({
    required this.badge,
    required this.headline,
    required this.tone,
    required this.icon,
  });

  /// Short, upper-case, for the header badge.
  final String badge;

  /// A sentence for the result panel.
  final String headline;

  final StatusTone tone;
  final IconData icon;

  factory BatchOutcomeSummary.of(ReplayBatchResult result) {
    final stopped = result.outcome == ReplayBatchOutcome.stopped;
    // A stop that could not preserve its output is a failure, however it was
    // requested, and must not be dressed up as an orderly stop.
    final savingNeedsAttention = stopped && result.error != null;
    final failed =
        result.outcome == ReplayBatchOutcome.failed || savingNeedsAttention;

    if (savingNeedsAttention) {
      return const BatchOutcomeSummary(
        badge: 'NEEDS ATTENTION',
        headline: 'Stopped, but saving needs attention',
        tone: StatusTone.failed,
        icon: Icons.error_outline,
      );
    }
    if (failed) {
      return const BatchOutcomeSummary(
        badge: 'FAILED',
        headline: 'Stopped after a failure',
        tone: StatusTone.failed,
        icon: Icons.error_outline,
      );
    }
    if (stopped) {
      return const BatchOutcomeSummary(
        badge: 'STOPPED',
        headline: 'Stopped safely',
        tone: StatusTone.blocked,
        icon: Icons.stop_circle_outlined,
      );
    }
    return const BatchOutcomeSummary(
      badge: 'FINISHED',
      headline: 'Batch finished',
      tone: StatusTone.ready,
      icon: Icons.check_circle_outline,
    );
  }
}
