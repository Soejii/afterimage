import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/setup_models.dart';
import '../recorder_blocker.dart';
import '../recorder_controller.dart';
import '../ui/ui.dart';
import '../widgets/diagnostics_drawer.dart';
import '../widgets/obs_setup_guide.dart';
import '../widgets/status_surface.dart';
import '../widgets/teach_screens_dialog.dart';

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
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Not ready to record yet', style: Ui.h1),
              const SizedBox(height: 6),
              Text(
                  blockers.length == 1
                      ? 'One thing to sort out first.'
                      : '${blockers.length} things to sort out first, one at a time.',
                  style: Ui.bodyMid),
              const SizedBox(height: 22),
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
              if (lead.id == RecorderBlockerId.obsConnection &&
                  controller.frameCaptureSupported)
                TextButton(
                    key: const ValueKey('use-data-only'),
                    onPressed: () => controller.updateOptions(
                        controller.options.copyWith(videoMode: VideoMode.none)),
                    child: const Text(
                        'Or skip the video and capture frame data only')),
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

    return UiPanel(
      key: const ValueKey('lead-blocker'),
      border: AfterimageTheme.blocked.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_circle_right_outlined,
                size: 16, color: AfterimageTheme.blocked),
            SizedBox(width: 8),
            UiCaps('Do this now', color: AfterimageTheme.blocked),
          ]),
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
      case RecorderBlockerAction.teachScreens:
        return FilledButton.icon(
          key: const ValueKey('blocker-teach-screens'),
          onPressed: busy
              ? null
              : () => unawaited(showTeachScreensDialog(context, controller)),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Teach screens'),
        );
    }
  }
}

/// The remaining blockers, each with its sentence, so nothing waits behind a
/// tooltip.
class _RemainingStrip extends StatelessWidget {
  const _RemainingStrip({required this.blockers});

  final List<RecorderBlocker> blockers;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('remaining-blockers'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const UiCaps('After that'),
        const SizedBox(height: 8),
        UiPanel(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < blockers.length; index++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                      border: index == 0
                          ? null
                          : const Border(
                              top:
                                  BorderSide(color: AfterimageTheme.hairline))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.circle_outlined,
                            size: 14, color: Ui.inkLow),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(blockers[index].label,
                                style: Ui.body
                                    .copyWith(fontWeight: FontWeight.w600)),
                            Text(blockers[index].message, style: Ui.small),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
