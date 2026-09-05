import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/setup_models.dart';
import '../recorder_controller.dart';
import '../widgets/afterimage_brand.dart';
import '../widgets/guided_step.dart';
import '../widgets/section_card.dart';
import '../widgets/setup_check_tile.dart';

class SetupScreen extends StatelessWidget {
  const SetupScreen({
    super.key,
    required this.report,
    required this.isRefreshing,
    required this.errorMessage,
    this.recorderController,
    this.isBusy = false,
    this.obsConnectionCard,
    this.obsConnected = false,
    this.pictureAndSoundConfirmed = false,
    this.onPictureAndSoundChanged,
    this.replayListPrepared = false,
    this.onReplayListPreparedChanged,
    this.onBrowseGameDirectory,
    this.onBrowseReplayDirectory,
    this.onUseAutomaticLocations,
    this.onOpenTestRecorder,
    this.onOpenObsDownload,
    required this.onRefresh,
    required this.onOpenRecorder,
  });

  final SetupReport? report;
  final bool isRefreshing;
  final String? errorMessage;
  final RecorderController? recorderController;
  final bool isBusy;
  final Widget? obsConnectionCard;
  final bool obsConnected;
  final bool pictureAndSoundConfirmed;
  final ValueChanged<bool>? onPictureAndSoundChanged;
  final bool replayListPrepared;
  final ValueChanged<bool>? onReplayListPreparedChanged;
  final Future<void> Function()? onBrowseGameDirectory;
  final Future<void> Function()? onBrowseReplayDirectory;
  final Future<void> Function()? onUseAutomaticLocations;
  final VoidCallback? onOpenTestRecorder;
  final Future<void> Function()? onOpenObsDownload;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenRecorder;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SetupHeading(
                report: report,
                recorderController: recorderController,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh,
                onOpenRecorder: onOpenRecorder,
              ),
              const SizedBox(height: 22),
              if (errorMessage != null) ...[
                _ErrorNotice(message: errorMessage!),
                const SizedBox(height: 16),
              ],
              if (report == null)
                const _LoadingChecks()
              else ...[
                _GuidedSetup(
                  report: report!,
                  recorderController: recorderController,
                  isBusy: isBusy,
                  obsConnectionCard: obsConnectionCard,
                  obsConnected: obsConnected,
                  pictureAndSoundConfirmed: pictureAndSoundConfirmed,
                  onPictureAndSoundChanged: onPictureAndSoundChanged,
                  replayListPrepared: replayListPrepared,
                  onReplayListPreparedChanged: onReplayListPreparedChanged,
                  onBrowseGameDirectory: onBrowseGameDirectory,
                  onBrowseReplayDirectory: onBrowseReplayDirectory,
                  onUseAutomaticLocations: onUseAutomaticLocations,
                  onOpenTestRecorder: onOpenTestRecorder,
                  onOpenObsDownload: onOpenObsDownload,
                  onRefresh: onRefresh,
                  onOpenRecorder: onOpenRecorder,
                ),
                const SizedBox(height: 16),
                _CheckSummary(report: report!),
                const SizedBox(height: 16),
                _ChecksGrid(report: report!),
                const SizedBox(height: 12),
                const _PrivacyNotice(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupHeading extends StatelessWidget {
  const _SetupHeading({
    required this.report,
    required this.recorderController,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onOpenRecorder,
  });

  final SetupReport? report;
  final RecorderController? recorderController;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenRecorder;

  @override
  Widget build(BuildContext context) {
    final controller = recorderController;
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _buildHeading(context),
      );
    }
    return _buildHeading(context);
  }

  Widget _buildHeading(BuildContext context) {
    final canRecord =
        recorderController?.canStart ?? report?.canRecord ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 620;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Let’s get your first recording ready',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Follow these short steps once. Afterimage will remember your choices on this computer.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('refresh-checks'),
              onPressed: isRefreshing ? null : onRefresh,
              icon: isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(isRefreshing ? 'Checking…' : 'Refresh checks'),
            ),
            FilledButton.icon(
              key: const ValueKey('open-recorder'),
              onPressed: onOpenRecorder,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(canRecord ? 'Record a test replay' : 'Open recorder'),
            ),
          ],
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: 18),
              actions,
              const SizedBox(height: 14),
              StatusPill(ready: canRecord, checking: isRefreshing),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                actions,
                const SizedBox(height: 12),
                StatusPill(ready: canRecord, checking: isRefreshing),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _GuidedSetup extends StatelessWidget {
  const _GuidedSetup({
    required this.report,
    required this.recorderController,
    required this.isBusy,
    required this.obsConnectionCard,
    required this.obsConnected,
    required this.pictureAndSoundConfirmed,
    required this.onPictureAndSoundChanged,
    required this.replayListPrepared,
    required this.onReplayListPreparedChanged,
    required this.onBrowseGameDirectory,
    required this.onBrowseReplayDirectory,
    required this.onUseAutomaticLocations,
    required this.onOpenTestRecorder,
    required this.onOpenObsDownload,
    required this.onRefresh,
    required this.onOpenRecorder,
  });

  final SetupReport report;
  final RecorderController? recorderController;
  final bool isBusy;
  final Widget? obsConnectionCard;
  final bool obsConnected;
  final bool pictureAndSoundConfirmed;
  final ValueChanged<bool>? onPictureAndSoundChanged;
  final bool replayListPrepared;
  final ValueChanged<bool>? onReplayListPreparedChanged;
  final Future<void> Function()? onBrowseGameDirectory;
  final Future<void> Function()? onBrowseReplayDirectory;
  final Future<void> Function()? onUseAutomaticLocations;
  final VoidCallback? onOpenTestRecorder;
  final Future<void> Function()? onOpenObsDownload;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenRecorder;

  @override
  Widget build(BuildContext context) {
    final reportObsReady =
        report.checkFor(SetupCheckId.obsWebSocket)?.isReady ?? false;
    final obsReady =
        obsConnected || (obsConnectionCard == null && reportObsReady);
    final replayReady =
        report.checkFor(SetupCheckId.replayLibrary)?.isReady ?? false;
    final allChecksReady = recorderController?.canStart ?? report.canRecord;
    final firstStepReady = obsReady;
    final secondStepCurrent = firstStepReady && !pictureAndSoundConfirmed;
    final thirdStepCurrent =
        firstStepReady && pictureAndSoundConfirmed && !replayListPrepared;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start here',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
        ),
        const SizedBox(height: 10),
        if (!allChecksReady && recorderController != null) ...[
          const SizedBox(height: 8),
          _ActionableBlockers(
            blockers: recorderController!.blockers,
            report: report,
          ),
        ],
        const SizedBox(height: 12),
        GuidedStep(
          number: 1,
          title: 'Connect OBS',
          subtitle:
              'Afterimage uses OBS to capture your game picture and sound.',
          status: firstStepReady
              ? GuidedStepStatus.ready
              : GuidedStepStatus.current,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              obsConnectionCard ??
                  _StepStatus(
                    ready: obsReady,
                    message: obsReady
                        ? 'OBS is ready for Afterimage.'
                        : 'Open OBS, then use Refresh checks when it is ready.',
                    action: obsReady
                        ? null
                        : OutlinedButton.icon(
                            key: const ValueKey('refresh-obs-check'),
                            onPressed: isBusy ? null : onRefresh,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Refresh checks'),
                          ),
                  ),
              if (onOpenObsDownload != null) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  key: const ValueKey('get-obs-studio'),
                  onPressed:
                      isBusy ? null : () => unawaited(onOpenObsDownload!()),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Get OBS Studio'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        GuidedStep(
          number: 2,
          title: 'Check picture and sound',
          subtitle:
              'Record one replay first. Look and listen before recording a full batch.',
          status: pictureAndSoundConfirmed
              ? GuidedStepStatus.ready
              : secondStepCurrent
                  ? GuidedStepStatus.current
                  : GuidedStepStatus.pending,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                key: const ValueKey('confirm-picture-and-sound'),
                value: pictureAndSoundConfirmed,
                onChanged: isBusy || onPictureAndSoundChanged == null
                    ? null
                    : (value) => onPictureAndSoundChanged!(value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I can see the game and hear its sound.'),
                subtitle: const Text(
                  'Use the one replay test in Recorder, then tick this box.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  'In OBS, the preview should show GGST and the game audio meter should move. Capture sources differ between Windows and Linux, so use the source that works on your desktop.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ),
              const SizedBox(height: 7),
              OutlinedButton.icon(
                key: const ValueKey('open-recorder-test'),
                onPressed: onOpenTestRecorder ?? onOpenRecorder,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('Open the one replay test'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GuidedStep(
          number: 3,
          title: 'Prepare your saved replays',
          subtitle:
              'Open the saved replay list in the game and highlight the bottom replay. Afterimage moves upward from there.',
          status: replayListPrepared
              ? GuidedStepStatus.ready
              : thirdStepCurrent
                  ? GuidedStepStatus.current
                  : GuidedStepStatus.pending,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                key: const ValueKey('confirm-replay-list'),
                value: replayListPrepared,
                onChanged: isBusy || onReplayListPreparedChanged == null
                    ? null
                    : (value) => onReplayListPreparedChanged!(value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('The bottom replay is highlighted in GGST.'),
                subtitle: Text(
                  replayReady
                      ? 'The saved replay folder was found. Keep GGST on this list before starting.'
                      : 'Save at least one replay, then open its list in GGST.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GuidedStep(
          number: 4,
          title: 'Record your replays',
          subtitle: allChecksReady
              ? 'Everything needed for a test recording is ready.'
              : 'Afterimage will show the next thing to fix before it unlocks recording.',
          status: allChecksReady
              ? GuidedStepStatus.ready
              : GuidedStepStatus.pending,
          action: FilledButton.icon(
            key: const ValueKey('guided-record'),
            onPressed: onOpenRecorder,
            icon: const Icon(Icons.arrow_forward_rounded),
            label:
                Text(allChecksReady ? 'Go to Recorder' : 'See what is missing'),
          ),
          child: _StepStatus(
            ready: allChecksReady,
            message: allChecksReady
                ? 'Start with one replay. You can choose more after the test works.'
                : 'Fix the next action shown below before recording.',
          ),
        ),
        if (onBrowseGameDirectory != null ||
            onBrowseReplayDirectory != null ||
            onUseAutomaticLocations != null) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Can’t find the game or saved replays?',
            subtitle:
                'Choose a folder only when automatic setup cannot find it.',
            child: Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                if (onBrowseGameDirectory != null)
                  OutlinedButton.icon(
                    key: const ValueKey('browse-game-directory'),
                    onPressed: isBusy
                        ? null
                        : () => unawaited(onBrowseGameDirectory!()),
                    icon: const Icon(Icons.sports_esports_outlined),
                    label: const Text('Locate game'),
                  ),
                if (onBrowseReplayDirectory != null)
                  OutlinedButton.icon(
                    key: const ValueKey('browse-replay-directory'),
                    onPressed: isBusy
                        ? null
                        : () => unawaited(onBrowseReplayDirectory!()),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Locate saved replays'),
                  ),
                if (onUseAutomaticLocations != null)
                  TextButton(
                    key: const ValueKey('use-automatic-locations'),
                    onPressed: isBusy
                        ? null
                        : () => unawaited(onUseAutomaticLocations!()),
                    child: const Text('Try automatic setup again'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StepStatus extends StatelessWidget {
  const _StepStatus({
    required this.ready,
    required this.message,
    this.action,
  });

  final bool ready;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = ready ? AfterimageTheme.accent : const Color(0xFFFFC67A);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ready ? Icons.check_circle_outline : Icons.info_outline,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 10),
          action!,
        ],
      ],
    );
  }
}

class _CheckSummary extends StatelessWidget {
  const _CheckSummary({required this.report});

  final SetupReport report;

  @override
  Widget build(BuildContext context) {
    final blockers = report.blockingChecks.length;
    final message = blockers == 0
        ? 'Everything needed for setup is ready.'
        : 'Finish the highlighted step to unlock recording.';
    final color =
        blockers == 0 ? AfterimageTheme.accent : const Color(0xFFFFC67A);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            blockers == 0 ? Icons.check_circle_outline : Icons.lock_outline,
            color: color,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecksGrid extends StatelessWidget {
  const _ChecksGrid({required this.report});

  final SetupReport report;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final innerWidth =
            (constraints.maxWidth - 40).clamp(0.0, double.infinity);
        final columns = innerWidth >= 760 ? 2 : 1;
        const gap = 12.0;
        final itemWidth =
            columns == 1 ? innerWidth : (innerWidth - gap) / columns;
        return Card(
          child: Material(
            color: Colors.transparent,
            child: ExpansionTile(
              key: const ValueKey('computer-details'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 20),
              title: const Text('Computer details'),
              subtitle: const Text('Optional information about this setup.'),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final check in report.checks)
                      SizedBox(
                        width: itemWidth,
                        child: SetupCheckTile(
                          check: check,
                          showTechnicalDetail:
                              check.status != SetupCheckStatus.ready,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined,
              color: AfterimageTheme.accent, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Setup only reads local status. It does not install software or change your game settings.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionableBlockers extends StatelessWidget {
  const _ActionableBlockers({required this.blockers, required this.report});

  final List<String> blockers;
  final SetupReport report;

  @override
  Widget build(BuildContext context) {
    final reportBlockers = report.blockingChecks;
    final reasons = <String>[
      for (final check in reportBlockers)
        '${_friendlyBlockerTitle(check.id)}: ${check.detail}',
      ...blockers.skip(reportBlockers.length),
    ];
    if (reasons.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC67A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFFFC67A).withValues(alpha: 0.24)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Next action',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFFFFD9A8), fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(reasons.first, style: Theme.of(context).textTheme.bodyMedium),
        if (reasons.length > 1)
          Material(
              color: Colors.transparent,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('${reasons.length - 1} more steps'),
                children: [
                  for (final reason in reasons.skip(1))
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(reason,
                                style: Theme.of(context).textTheme.bodySmall))),
                ],
              )),
      ]),
    );
  }

  String _friendlyBlockerTitle(SetupCheckId id) {
    switch (id) {
      case SetupCheckId.supportedPlatform:
        return 'Computer';
      case SetupCheckId.runtime:
        return 'Afterimage';
      case SetupCheckId.gameInstall:
        return 'Game installation';
      case SetupCheckId.gameRunning:
        return 'Game';
      case SetupCheckId.obsWebSocket:
        return 'OBS';
      case SetupCheckId.replayLibrary:
        return 'Saved replays';
      case SetupCheckId.keyboardInput:
        return 'Keyboard controls';
      case SetupCheckId.controllerInput:
        return 'Controller';
      case SetupCheckId.nativeRecorderBackend:
        return 'Recording support';
    }
  }
}

class _LoadingChecks extends StatelessWidget {
  const _LoadingChecks();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Checking this computer',
      subtitle:
          'Afterimage is reading local status only. Nothing is installed or changed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 15),
          Text(
            'Looking for GGST, OBS, and replay files…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC67A).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFC67A).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC67A)),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
