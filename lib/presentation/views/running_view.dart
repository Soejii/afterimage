import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../recorder_controller.dart';
import '../replay_timeline.dart';
import '../widgets/replay_list.dart';
import '../widgets/status_surface.dart';
import '../widgets/viewfinder_frame.dart';

/// What is on screen while a batch runs.
///
/// A batch can run for hours, so this takes the whole window rather than
/// sharing it with a disabled copy of the settings form. The engine already
/// reported every state change and every finished replay; this is the first
/// version of the interface that shows any of it.
class RunningView extends StatefulWidget {
  const RunningView({super.key, required this.controller});

  final RecorderController controller;

  @override
  State<RunningView> createState() => _RunningViewState();
}

class _RunningViewState extends State<RunningView> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The controller notifies on engine events, which can be minutes apart.
    // Elapsed time has to advance between them.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final progress = controller.progress;
    final rows = timelineFromOutcomes(controller.replayOutcomes, progress);
    final elapsed = controller.elapsed;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ViewfinderFrame(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const RecordDot(size: 11),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            phaseLabelFor(progress.state),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (elapsed != null)
                          Text(
                            formatElapsed(elapsed),
                            key: const ValueKey('elapsed-time'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progress.currentReplay == 0
                          ? 'Preparing the first replay'
                          : 'Replay ${progress.currentReplay} of '
                              '${progress.totalReplays}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: progress.totalReplays > 0
                            ? progress.fraction
                            : null,
                      ),
                    ),
                    if (progress.outputPath != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Writing ${progress.outputPath}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              ReplayList(rows: rows),
              if (controller.error != null) ...[
                const SizedBox(height: 18),
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
              const SizedBox(height: 22),
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  key: const ValueKey('stop-batch'),
                  onPressed: controller.isStopping
                      ? null
                      : () => unawaited(controller.requestStop()),
                  icon: controller.isStopping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop_circle_outlined),
                  label: Text(
                    controller.isStopping
                        ? 'Saving before stopping…'
                        : 'Stop safely',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Stopping keeps whatever has been recorded so far. '
                  'Do not use the replay menu while this runs.',
                  textAlign: TextAlign.center,
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
