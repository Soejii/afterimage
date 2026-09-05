import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../recorder_blocker.dart';
import '../recorder_controller.dart';
import '../widgets/diagnostics_drawer.dart';
import '../widgets/obs_setup_guide.dart';
import '../widgets/status_surface.dart';

/// What is on screen while something prevents recording.
///
/// Exactly one blocker leads, with the action that resolves it. The rest are a
/// compact strip beneath, so the user can see how much is left without being
/// handed a list of problems to triage. Hiding the remainder entirely turns
/// every fix into a fresh unexpected wall, which is how people give up.
class BlockedView extends StatelessWidget {
  const BlockedView({
    super.key,
    required this.controller,
    required this.isRefreshing,
    required this.onRefresh,
    this.obsConnectionCard,
    this.errorMessage,
  });

  final RecorderController controller;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final Widget? obsConnectionCard;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    // Only environment blockers belong here. Listing an option blocker on a
    // screen that does not contain the batch form names a problem whose
    // control is not present.
    final blockers = controller.environmentBlockers;
    final lead = controller.leadBlocker;
    if (lead == null) {
      return const SizedBox.shrink();
    }
    final rest = blockers.skip(1).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (errorMessage != null) ...[
                StatusSurface(
                  tone: StatusTone.failed,
                  icon: Icons.warning_amber_rounded,
                  child: Text(
                    errorMessage!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _LeadBlocker(
                blocker: lead,
                controller: controller,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh,
                obsConnectionCard: obsConnectionCard,
              ),
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 18),
                _RemainingStrip(blockers: rest),
              ],
              const SizedBox(height: 20),
              DiagnosticsDrawer(
                report: controller.setupReport,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh,
                onBrowseGameDirectory: controller.browseGameDirectory,
                onBrowseReplayDirectory: controller.browseReplayDirectory,
                onUseAutomaticLocations: controller.useAutomaticLocations,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadBlocker extends StatelessWidget {
  const _LeadBlocker({
    required this.blocker,
    required this.controller,
    required this.isRefreshing,
    required this.onRefresh,
    required this.obsConnectionCard,
  });

  final RecorderBlocker blocker;
  final RecorderController controller;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final Widget? obsConnectionCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isObs = blocker.id == RecorderBlockerId.obsConnection;
    final connection = controller.obsConnection;

    return Card(
      key: const ValueKey('lead-blocker'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEXT STEP',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AfterimageTheme.blocked,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            if (isObs && connection != null)
              // OBS is the one wall Afterimage refuses to climb for the user,
              // so it gets the illustrated guide instead of one sentence.
              ObsSetupGuide(
                stage: connection.stage,
                isBusy: isRefreshing || controller.isBusy,
                onOpenObsDownload: controller.openObsDownload,
                onConnect: () async {
                  await connection.useAutomaticConnection();
                  if (connection.result?.ready == true) {
                    await onRefresh();
                  }
                },
              )
            else ...[
              Text(
                blocker.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                blocker.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              _BlockerAction(
                blocker: blocker,
                controller: controller,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh,
              ),
            ],
            if (isObs && obsConnectionCard != null) ...[
              const SizedBox(height: 18),
              obsConnectionCard!,
            ],
          ],
        ),
      ),
    );
  }
}

class _BlockerAction extends StatelessWidget {
  const _BlockerAction({
    required this.blocker,
    required this.controller,
    required this.isRefreshing,
    required this.onRefresh,
  });

  final RecorderBlocker blocker;
  final RecorderController controller;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final busy = isRefreshing || controller.isBusy;
    switch (blocker.action) {
      case RecorderBlockerAction.none:
        return const SizedBox.shrink();
      case RecorderBlockerAction.refreshChecks:
        return FilledButton.icon(
          key: const ValueKey('blocker-refresh'),
          onPressed: busy ? null : () => unawaited(onRefresh()),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(busy ? 'Checking…' : 'Check again'),
        );
      case RecorderBlockerAction.chooseOutputFolder:
        return FilledButton.icon(
          key: const ValueKey('blocker-choose-folder'),
          onPressed:
              busy ? null : () => unawaited(controller.browseOutputDirectory()),
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Choose folder'),
        );
      case RecorderBlockerAction.locateGame:
        return FilledButton.icon(
          key: const ValueKey('blocker-locate-game'),
          onPressed:
              busy ? null : () => unawaited(controller.browseGameDirectory()),
          icon: const Icon(Icons.sports_esports_outlined),
          label: const Text('Locate game'),
        );
      case RecorderBlockerAction.locateReplays:
        return FilledButton.icon(
          key: const ValueKey('blocker-locate-replays'),
          onPressed:
              busy ? null : () => unawaited(controller.browseReplayDirectory()),
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Locate saved replays'),
        );
      case RecorderBlockerAction.connectObs:
        return const SizedBox.shrink();
      case RecorderBlockerAction.openAdvancedOptions:
        return Text(
          'Choose a different option under Replay controls, or fix the one '
          'you selected. Afterimage never switches to a different control '
          'method on its own.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
        );
    }
  }
}

/// The remaining blockers, as a compact honest count.
class _RemainingStrip extends StatelessWidget {
  const _RemainingStrip({required this.blockers});

  final List<RecorderBlocker> blockers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('remaining-blockers'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AFTER THAT',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final blocker in blockers)
              Tooltip(
                message: blocker.message,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AfterimageTheme.panelRaised,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AfterimageTheme.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.circle_outlined,
                        size: 13,
                        color: AfterimageTheme.blocked,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        blocker.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
