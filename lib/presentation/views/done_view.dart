import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/replay_batch.dart';
import '../../domain/notes_models.dart';
import '../../services/notes_repository.dart';
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
  const DoneView({
    super.key,
    required this.controller,
    this.notesRepository,
    this.onOpenNotes,
    this.now = DateTime.now,
  });

  final RecorderController controller;
  final NotesRepository? notesRepository;
  final VoidCallback? onOpenNotes;
  final DateTime Function() now;

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
              if (notesRepository != null && onOpenNotes != null)
                _NotesStatusPanel(
                  controller: controller,
                  repository: notesRepository!,
                  onOpen: onOpenNotes!,
                  now: now,
                ),
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

class _NotesStatusPanel extends StatefulWidget {
  const _NotesStatusPanel({
    required this.controller,
    required this.repository,
    required this.onOpen,
    required this.now,
  });

  final RecorderController controller;
  final NotesRepository repository;
  final VoidCallback onOpen;
  final DateTime Function() now;

  @override
  State<_NotesStatusPanel> createState() => _NotesStatusPanelState();
}

class _NotesStatusPanelState extends State<_NotesStatusPanel> {
  static const _runFileTimeout = Duration(seconds: 60);

  Timer? _poll;
  List<NotePreview> _previews = const <NotePreview>[];
  Object? _error;
  String? _missingRunMessage;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = widget.now();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final label = widget.controller.finderBatchLabel;
    if (label == null) return;
    try {
      await widget.controller.refreshFinderStatus();
      final previews = await widget.repository.list();
      if (!mounted) return;
      final run = widget.controller.finderRun;
      final now = widget.now();
      final missingTooLong = run == null && _hasFinderTimedOut(label, now);
      if ((run != null && run.state != FinderRunState.running) ||
          missingTooLong) {
        _poll?.cancel();
        _poll = null;
      }
      setState(() {
        _previews = previews
            .where((preview) => preview.batchLabel == label)
            .toList(growable: false);
        _error = null;
        _missingRunMessage = missingTooLong
            ? 'The notes finder did not start. See ${widget.repository.runLogPath(label)}.'
            : null;
        _now = now;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _now = widget.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.controller.finderBatchLabel;
    if (label == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final run = widget.controller.finderRun;
    final finderError = widget.controller.finderError;
    final missingRunMessage = _missingRunMessage;
    if (_error != null ||
        finderError != null ||
        missingRunMessage != null ||
        run?.state == FinderRunState.failed) {
      final message = finderError ??
          missingRunMessage ??
          run?.message ??
          'The notes finder could not finish.';
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: StatusSurface(
          tone: StatusTone.failed,
          icon: Icons.error_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notes failed: $message'),
              const SizedBox(height: 5),
              Text(
                'Log: ${widget.repository.runLogPath(label)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (run == null || run.state == FinderRunState.running) {
      final started = run?.startedAt;
      final elapsed =
          started == null ? null : _now.difference(started.toLocal());
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Card(
          key: const ValueKey('notes-status'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    elapsed == null
                        ? 'Writing notes...'
                        : 'Writing notes... ${formatElapsed(elapsed)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (run.state == FinderRunState.nothing) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: StatusSurface(
          tone: StatusTone.blocked,
          icon: Icons.notes_outlined,
          child: Text('No situation came up often enough.'),
        ),
      );
    }

    final written = _previews.where((preview) => !preview.isLegacy).toList();
    final opponents = written.isNotEmpty
        ? written
            .map((preview) =>
                '${preview.opponent} (${preview.cardCount} ${preview.cardCount == 1 ? 'situation' : 'situations'})')
            .join(', ')
        : run.opponents
            .where((opponent) => opponent.status == 'written')
            .map((opponent) =>
                '${opponent.name} (${opponent.situations ?? 0} ${opponent.situations == 1 ? 'situation' : 'situations'})')
            .join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Card(
        key: const ValueKey('notes-status'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  opponents.isEmpty
                      ? 'No situation came up often enough.'
                      : 'Notes ready: $opponents',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AfterimageTheme.readyText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (opponents.isNotEmpty)
                TextButton(
                  key: const ValueKey('open-notes-from-done'),
                  onPressed: widget.onOpen,
                  child: const Text('Open'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasFinderTimedOut(String label, DateTime now) {
    final started = widget.controller.finderStartedAt;
    return started != null &&
        now.difference(started) >= _runFileTimeout &&
        widget.controller.finderBatchLabel == label;
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
