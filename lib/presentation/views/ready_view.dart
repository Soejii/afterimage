import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/setup_models.dart';
import '../recorder_blocker.dart';
import '../recorder_controller.dart';
import '../ui/ui.dart';
import '../widgets/batch_form_fields.dart';
import '../widgets/diagnostics_drawer.dart';
import '../widgets/section_card.dart';
import '../widgets/status_surface.dart';
import '../widgets/teach_screens_dialog.dart';

/// What is on screen when a batch can start.
///
/// Windows replay controls start expanded because their focus and driver
/// requirements affect how the user can record. Every batch produces one video.
class ReadyView extends StatelessWidget {
  const ReadyView({
    super.key,
    required this.controller,
    required this.isRefreshing,
    required this.onRefresh,
    this.errorMessage,
  });

  final RecorderController controller;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final options = controller.options;

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
                  child: Text(errorMessage!),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                  width: double.infinity,
                  child: UiPanel(
                    key: const ValueKey('capture-gateway'),
                    // Spans the form like the panels below it.
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const UiCaps('What to capture'),
                          const SizedBox(height: 8),
                          Wrap(
                              key: const ValueKey('capture-mode'),
                              spacing: 8,
                              children: [
                                ChoiceChip(
                                    key: const ValueKey('capture-mode-video'),
                                    label: const Text('Video'),
                                    selected:
                                        options.videoMode != VideoMode.none,
                                    onSelected: (_) => controller.updateOptions(
                                        options.copyWith(
                                            videoMode: VideoMode.combined))),
                                Tooltip(
                                    message: controller.frameCaptureSupported
                                        ? 'Capture frame data without video'
                                        : controller
                                            .frameCaptureUnavailableReason,
                                    child: ChoiceChip(
                                        key:
                                            const ValueKey('capture-mode-data'),
                                        label: const Text('Frame data only'),
                                        selected:
                                            options.videoMode == VideoMode.none,
                                        onSelected: controller
                                                .frameCaptureSupported
                                            ? (_) => controller.updateOptions(
                                                options.copyWith(
                                                    videoMode: VideoMode.none))
                                            : null)),
                              ]),
                          const SizedBox(height: 8),
                          Text(
                              options.videoMode == VideoMode.none
                                  ? 'No video and no OBS. Plays the replays and saves their frame data.'
                                  : 'Records one video with OBS.',
                              style: Ui.small),
                          if (options.capturesFrameData) ...[
                            const SizedBox(height: 18),
                            const UiCaps('Whose replays'),
                            const SizedBox(height: 8),
                            Wrap(
                                key: const ValueKey('replay-owner'),
                                spacing: 8,
                                children: [
                                  ChoiceChip(
                                      key: const ValueKey('replay-owner-own'),
                                      label: const Text('My games'),
                                      selected: options.replayOwner ==
                                          ReplayOwner.own,
                                      onSelected: (_) => controller
                                          .updateOptions(options.copyWith(
                                              replayOwner: ReplayOwner.own))),
                                  ChoiceChip(
                                      key: const ValueKey(
                                          'replay-owner-reference'),
                                      label: const Text('High-level reference'),
                                      selected: options.replayOwner ==
                                          ReplayOwner.reference,
                                      onSelected: (_) => controller
                                          .updateOptions(options.copyWith(
                                              replayOwner:
                                                  ReplayOwner.reference))),
                                ]),
                            const SizedBox(height: 8),
                            const Text(
                                'Reference sets are kept out of your own history.',
                                style: Ui.small),
                          ],
                        ]),
                  )),
              const SizedBox(height: 16),
              SectionCard(
                title: 'How many replays',
                subtitle: options.videoMode == VideoMode.none
                    ? 'Afterimage captures frame data for the whole batch.'
                    : 'Afterimage records one video for the whole batch.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        for (final choice in ReplayCountOption.values)
                          ChoiceChip(
                            key: ValueKey('replay-count-${choice.name}'),
                            label: Text(choice.label),
                            selected: options.replayCount == choice,
                            onSelected: (_) => controller.updateOptions(
                              options.copyWith(replayCount: choice),
                            ),
                          ),
                      ],
                    ),
                    if (options.replayCount == ReplayCountOption.custom) ...[
                      const SizedBox(height: 14),
                      CustomReplayCountField(
                        value: options.customReplayCount,
                        enabled: true,
                        onChanged: (value) => controller.updateOptions(
                          options.copyWith(customReplayCount: value),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Where to save it',
                subtitle: 'Every batch gets its own folder, so a new run never '
                    'overwrites an earlier one.',
                child: OutputFolderField(
                  value: options.outputDirectory,
                  enabled: true,
                  isPicking: controller.isPickingDirectory,
                  onChanged: (value) => controller.updateOptions(
                    options.copyWith(outputDirectory: value),
                  ),
                  onBrowse: controller.browseOutputDirectory,
                ),
              ),
              const SizedBox(height: 16),
              _AdvancedOptions(controller: controller),
              const SizedBox(height: 22),
              _StartPanel(controller: controller),
              if (controller.recentOutputPaths.isNotEmpty) ...[
                const SizedBox(height: 20),
                _RecentRecordings(controller: controller),
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

class _AdvancedOptions extends StatelessWidget {
  const _AdvancedOptions({required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    final options = controller.options;
    return Card(
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: const ValueKey('advanced-options'),
          initiallyExpanded:
              Theme.of(context).platform == TargetPlatform.windows,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text('Replay controls'),
          subtitle: Text(
            options.inputMode == InputMode.keyboard
                ? Theme.of(context).platform == TargetPlatform.windows
                    ? 'Keyboard: direct to GGST window'
                    : 'Keyboard'
                : 'Controller',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            RadioGroup<InputMode>(
              groupValue: options.inputMode,
              onChanged: (value) {
                if (value != null) {
                  controller.updateOptions(options.copyWith(inputMode: value));
                }
              },
              child: Column(
                children: [
                  for (final mode in InputMode.values)
                    Builder(
                      builder: (context) {
                        final readiness = controller.readinessFor(mode);
                        return InputModeTile(
                          mode: mode,
                          available: readiness?.available ?? false,
                          availabilityDetail: readiness?.detail,
                          checking: readiness == null && controller.isChecking,
                          enabled: options.inputMode == mode ||
                              (readiness?.available ?? false),
                        );
                      },
                    ),
                ],
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('capture-frame-data'),
              value: options.capturesFrameData,
              onChanged: controller.frameCaptureSupported &&
                      options.videoMode != VideoMode.none
                  ? (value) => controller.updateOptions(
                        options.copyWith(
                          captureFrameData: value ?? false,
                        ),
                      )
                  : null,
              title: const Text('Save frame data for analysis'),
              subtitle: Text(
                controller.frameCaptureSupported
                    ? 'Writes raw frame values beside the batch recording.'
                    : controller.frameCaptureUnavailableReason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            SwitchListTile(
              key: const ValueKey('screen-guard-toggle'),
              value: options.videoMode != VideoMode.none &&
                  options.screenGuardEnabled,
              onChanged: options.videoMode == VideoMode.none
                  ? null
                  : (value) => controller.updateOptions(
                        options.copyWith(screenGuardEnabled: value),
                      ),
              title: const Text(
                'Check the game screen before each menu press',
              ),
              subtitle: Text(
                options.videoMode == VideoMode.none
                    ? 'Needs OBS, which this mode does not use.'
                    : controller.screenReferencesTaught
                        ? 'Both game screens are taught on this computer.'
                        : 'Teach the replay list and View Replay selection first.',
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('teach-screens'),
                onPressed: options.videoMode == VideoMode.none
                    ? null
                    : () => unawaited(
                          showTeachScreensDialog(context, controller),
                        ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Teach screens'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The start action, with a plain statement of what it will do.
///
/// This sentence replaces a checkbox that used to ask the user to confirm they
/// had highlighted the right replay. Afterimage cannot see the game's menu
/// cursor, so it cannot verify that, and a checkbox only recorded a promise.
/// Saying what the button does is the button's own job.
class _StartPanel extends StatelessWidget {
  const _StartPanel({required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    final count = controller.replayCountFromReport();
    final theme = Theme.of(context);
    final pending = controller.optionBlockers;

    if (pending.isNotEmpty) {
      // Something above needs correcting. Say which control, and keep that
      // control on screen; taking the form away would remove the only way to
      // fix it.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatusSurface(
            key: const ValueKey('option-blockers'),
            tone: StatusTone.blocked,
            icon: Icons.lock_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final blocker in pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${blocker.label}: ${blocker.message}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AfterimageTheme.blockedText,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (blocker.action ==
                            RecorderBlockerAction.teachScreens)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: OutlinedButton.icon(
                              key: const ValueKey('blocker-teach-screens'),
                              onPressed: () => unawaited(
                                showTeachScreensDialog(context, controller),
                              ),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Teach screens'),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 58,
            child: FilledButton.icon(
              key: const ValueKey('start-batch'),
              onPressed: null,
              icon: const Icon(Icons.lock_outline),
              label: Text(controller.options.videoMode == VideoMode.none
                  ? 'Start capturing'
                  : 'Start recording'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusSurface(
          tone: StatusTone.ready,
          icon: Icons.play_circle_outline_rounded,
          child: Text(
            count == null
                ? 'Afterimage starts at the replay you have highlighted in '
                    'GGST and works upward through the list.'
                : 'Afterimage starts at the replay you have highlighted in '
                    'GGST and ${controller.options.videoMode == VideoMode.none ? 'captures' : 'records'} $count '
                    '${count == 1 ? 'replay' : 'replays'} upward from there${controller.options.videoMode == VideoMode.none ? '.' : ', into one video.'}',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            key: const ValueKey('start-batch'),
            onPressed: controller.canStart
                ? () => unawaited(controller.startBatch())
                : null,
            icon: const Icon(Icons.fiber_manual_record),
            label: Text(
              controller.isChecking
                  ? 'Checking…'
                  : controller.options.videoMode == VideoMode.none
                      ? 'Start capturing'
                      : 'Start recording',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            controller.options.videoMode == VideoMode.none
                ? 'Keep GGST open. Existing files are never overwritten.'
                : 'Keep GGST and OBS open. Existing files are never overwritten.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentRecordings extends StatelessWidget {
  const _RecentRecordings({required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Recent recordings',
      subtitle: 'Open a video again, or the folder it was saved in.',
      trailing: OutlinedButton.icon(
        key: const ValueKey('open-recent-output-folder'),
        onPressed: () => unawaited(controller.openOutputFolder()),
        icon: const Icon(Icons.folder_open_outlined),
        label: const Text('Open folder'),
      ),
      child: Column(
        children: [
          for (final path in controller.recentOutputPaths.take(5))
            ListTile(
              key: ValueKey('recent-output-$path'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.movie_outlined),
              title: Text(
                _fileName(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                key: ValueKey('play-recent-output-$path'),
                onPressed: () => unawaited(controller.openOutput(path)),
                tooltip: 'Play recording',
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ),
        ],
      ),
    );
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    return separator < 0 ? normalized : normalized.substring(separator + 1);
  }
}
