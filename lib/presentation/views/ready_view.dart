import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/setup_models.dart';
import '../recorder_controller.dart';
import '../widgets/batch_form_fields.dart';
import '../widgets/diagnostics_drawer.dart';
import '../widgets/section_card.dart';
import '../widgets/status_surface.dart';

/// What is on screen when a batch can start.
///
/// Two decisions are visible: how many replays, and where to save them. The
/// replay-control choice is defaulted and demoted, because it asks the user to
/// evaluate a capability the application has already measured. There is no
/// video-mode choice at all; every batch produces one video.
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
              SectionCard(
                title: 'How many replays',
                subtitle: 'Afterimage records one video for the whole batch.',
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text('Replay controls'),
          subtitle: Text(
            options.inputMode == InputMode.keyboard
                ? 'Keyboard'
                : 'Virtual gamepad',
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
                    child: Text(
                      '${blocker.label}: ${blocker.message}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AfterimageTheme.blockedText,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
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
              label: const Text('Start recording'),
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
                    'GGST and records $count '
                    '${count == 1 ? 'replay' : 'replays'} upward from there, '
                    'into one video.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AfterimageTheme.readyText,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
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
              controller.isChecking ? 'Checking…' : 'Start recording',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Keep GGST and OBS open. Existing files are never overwritten.',
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
