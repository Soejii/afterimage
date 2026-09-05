import 'package:flutter/material.dart';

import '../recorder_blocker.dart';
import '../recorder_controller.dart';
import '../views/blocked_view.dart';
import '../views/done_view.dart';
import '../views/ready_view.dart';
import '../views/running_view.dart';
import '../widgets/afterimage_brand.dart';
import '../widgets/phase_indicator.dart';

/// Afterimage's only screen.
///
/// The application used to be two navigation destinations, Setup and Recorder,
/// which asked the user to decide where to go. Setup was never a peer of the
/// recorder; it was a precondition of it. There is now one screen that changes
/// state, so the interface always answers the single question this application
/// exists to answer: can I record right now, and if not, what do I fix.
class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    this.obsConnectionCard,
    required this.isRefreshing,
    required this.onRefresh,
    this.errorMessage,
  });

  final RecorderController controller;
  final Widget? obsConnectionCard;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  /// A failure raised by the shell's own setup checks. Failures raised by the
  /// controller are read inside the listener below, not passed in, so that a
  /// change to them actually reaches the screen.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final phase = controller.phase;
        // Order matters. A recording failure outranks "your choices could not
        // be remembered", which is persistent and would otherwise mask it.
        final message = errorMessage ??
            controller.error?.toString() ??
            controller.preferenceNotice;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkspaceHeader(phase: phase, controller: controller),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _body(phase, message),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _body(RecorderPhase phase, String? message) {
    switch (phase) {
      case RecorderPhase.checking:
        return const _CheckingView(key: ValueKey('checking-view'));
      case RecorderPhase.blocked:
        return BlockedView(
          key: const ValueKey('blocked-view'),
          controller: controller,
          obsConnectionCard: obsConnectionCard,
          isRefreshing: isRefreshing,
          onRefresh: onRefresh,
          errorMessage: message,
        );
      case RecorderPhase.ready:
        return ReadyView(
          key: const ValueKey('ready-view'),
          controller: controller,
          isRefreshing: isRefreshing,
          onRefresh: onRefresh,
          errorMessage: message,
        );
      case RecorderPhase.running:
        return RunningView(
          key: const ValueKey('running-view'),
          controller: controller,
        );
      case RecorderPhase.done:
        return DoneView(
          key: const ValueKey('done-view'),
          controller: controller,
        );
    }
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.phase, required this.controller});

  final RecorderPhase phase;
  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          const AfterimageBrand(),
          const Spacer(),
          PhaseIndicator(phase: phase, controller: controller),
        ],
      ),
    );
  }
}

/// Cold start, before the local checks have reported.
///
/// This is deliberately the blocked layout with a skeleton in it rather than a
/// fifth design, because it is on screen for well under a second and a distinct
/// layout would only make the application appear to flash between pages.
class _CheckingView extends StatelessWidget {
  const _CheckingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Checking this computer',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 4),
            const SizedBox(height: 14),
            Text(
              'Looking for the game, your saved replays, and OBS. Nothing is '
              'installed or changed.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
