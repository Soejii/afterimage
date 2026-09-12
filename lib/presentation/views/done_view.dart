import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/replay_batch.dart';
import '../batch_outcome_summary.dart';
import '../recorder_controller.dart';
import '../replay_timeline.dart';
import '../widgets/replay_list.dart';
import '../widgets/status_surface.dart';

/// What is on screen after a batch ends.
///
/// A batch that ran for hours has earned the whole window. The three questions
/// a user has here are "did it work", "where is it", and "what failed", and the
/// settings form answers none of them. The per-replay list is kept from the
/// running state, because with one combined video it is the only record of
/// which replays actually made it in.
class DoneView extends StatelessWidget {
  const DoneView({super.key, required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    if (result == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final rows = timelineFromResult(result);
    final elapsed = controller.elapsed;

    final summary = BatchOutcomeSummary.of(result);

    // Every batch records one combined video, and per-replay results stay
    // `recorded` even when finalizing that video fails. Counting them without
    // checking for the file would report "5 replays saved" directly above
    // "No video file was produced".
    final videoProduced = result.combinedOutput != null ||
        result.combinedSourceOutput != null ||
        controller.outputPaths.isNotEmpty;
    // A replay whose own output was written completely still counts as saved
    // even when the batch later failed, because that file is on disk.
    final reachedTheVideo = result.replays
        .where((replay) =>
            replay.status == ReplayResultStatus.recorded ||
            replay.output?.partial == false)
        .length;
    final saved = videoProduced ? reachedTheVideo : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatusSurface(
                tone: summary.tone,
                icon: summary.icon,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.headline,
                      key: const ValueKey('result-headline'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: summary.tone.color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      !videoProduced
                          ? '$reachedTheVideo '
                              '${reachedTheVideo == 1 ? 'replay was' : 'replays were'} '
                              'recorded, but the video could not be saved.'
                          : elapsed == null
                              ? '$saved ${saved == 1 ? 'replay' : 'replays'} saved.'
                              : '$saved ${saved == 1 ? 'replay' : 'replays'} saved '
                                  'in ${formatElapsed(elapsed)}.',
                      key: const ValueKey('result-summary'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.error != null) ...[
                const SizedBox(height: 14),
                StatusSurface(
                  tone: StatusTone.failed,
                  icon: Icons.error_outline,
                  child: Text(
                    controller.error.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AfterimageTheme.failedText,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _OutputPanel(controller: controller),
              const SizedBox(height: 22),
              ReplayList(rows: rows, maxHeight: 300),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  key: const ValueKey('record-another-batch'),
                  onPressed: controller.clearResult,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Record another batch'),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Your settings are kept. The next batch gets its own folder.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutputPanel extends StatelessWidget {
  const _OutputPanel({required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paths = controller.outputPaths;
    final directory = controller.batchOutputDirectory;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your video',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (paths.isEmpty)
              Text(
                'No video file was produced. Anything OBS had already written '
                'has been left in place.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              )
            else
              for (final path in paths)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.movie_outlined, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          path,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            if (directory != null && directory.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Batch folder: $directory',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('open-output-folder'),
                  onPressed: () => unawaited(controller.openOutputFolder()),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open folder'),
                ),
                if (paths.isNotEmpty)
                  OutlinedButton.icon(
                    key: const ValueKey('play-latest-output'),
                    onPressed: () =>
                        unawaited(controller.openOutput(paths.last)),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play it'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
