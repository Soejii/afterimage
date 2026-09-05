import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../batch_outcome_summary.dart';
import '../recorder_blocker.dart';
import '../recorder_controller.dart';
import 'status_surface.dart';
import 'viewfinder_frame.dart';

/// The one place in Afterimage that states whether recording is possible.
///
/// Readiness used to be rendered in eight places at once: a sidebar badge, a
/// status pill, two blocker lists, a check summary, a guided step, a recorder
/// pill, and the Start button's own label. Every one of them derived the same
/// fact slightly differently. There is now exactly one, and it reads its state
/// from `RecorderController.phase`.
class PhaseIndicator extends StatelessWidget {
  const PhaseIndicator({
    super.key,
    required this.phase,
    required this.controller,
  });

  final RecorderPhase phase;
  final RecorderController controller;

  BatchOutcomeSummary? get _terminal {
    final result = controller.result;
    return result == null ? null : BatchOutcomeSummary.of(result);
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (phase) {
      RecorderPhase.checking => ('CHECKING', AfterimageTheme.blocked),
      RecorderPhase.blocked => ('SETUP NEEDED', AfterimageTheme.blocked),
      // The batch form is on screen, but a value in it can still be blocking
      // the start action, and a failure raised before the engine started also
      // leaves us here. Saying READY in either case contradicts what the rest
      // of the screen shows, which is the exact defect this widget exists to
      // stop. A refresh in progress is NOT an action the user has to take.
      RecorderPhase.ready => controller.error != null
          ? ('NOT READY', AfterimageTheme.failed)
          : controller.blockers.isEmpty
              ? ('READY', AfterimageTheme.ready)
              : ('ACTION NEEDED', AfterimageTheme.blocked),
      RecorderPhase.running => ('RECORDING', AfterimageTheme.recording),
      // A terminal batch is not automatically a success. Showing a green
      // FINISHED above a red failure panel is the interface contradicting
      // itself in the one place a user looks first.
      RecorderPhase.done => _terminal == null
          ? ('FINISHED', AfterimageTheme.ready)
          : (_terminal!.badge, _terminal!.tone.color),
    };

    return Container(
      key: const ValueKey('phase-indicator'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _leading(color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
          ),
        ],
      ),
    );
  }

  Widget _leading(Color color) {
    switch (phase) {
      case RecorderPhase.running:
        return const RecordDot(size: 10);
      case RecorderPhase.checking:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
        );
      case RecorderPhase.blocked:
        return Icon(Icons.lock_outline, size: 14, color: color);
      case RecorderPhase.done:
        return Icon(
          _terminal?.icon ?? Icons.check_circle_outline,
          size: 14,
          color: color,
        );
      case RecorderPhase.ready:
        return Icon(
          controller.error == null && controller.blockers.isEmpty
              ? Icons.check_circle_outline
              : Icons.lock_outline,
          size: 14,
          color: color,
        );
    }
  }
}
