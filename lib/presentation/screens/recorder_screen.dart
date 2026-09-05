import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/replay_batch.dart';
import '../../domain/setup_models.dart';
import '../recorder_controller.dart';
import '../widgets/section_card.dart';

class RecorderScreen extends StatelessWidget {
  const RecorderScreen({
    super.key,
    required this.report,
    required this.options,
    required this.onOptionsChanged,
    this.controller,
    this.onBrowseOutputDirectory,
  });

  final SetupReport? report;
  final RecordingOptions options;
  final ValueChanged<RecordingOptions> onOptionsChanged;
  final RecorderController? controller;
  final Future<void> Function()? onBrowseOutputDirectory;

  @override
  Widget build(BuildContext context) {
    final recorderController = controller;
    if (recorderController == null) {
      return _RecorderBody(
        report: report,
        options: options,
        onOptionsChanged: onOptionsChanged,
        onBrowseOutputDirectory: onBrowseOutputDirectory,
      );
    }

    return AnimatedBuilder(
      animation: recorderController,
      builder: (context, child) => _RecorderBody(
        report: recorderController.setupReport ?? report,
        options: recorderController.options,
        controller: recorderController,
        onOptionsChanged: recorderController.updateOptions,
        onBrowseOutputDirectory: recorderController.browseOutputDirectory,
      ),
    );
  }
}

class _RecorderBody extends StatelessWidget {
  const _RecorderBody({
    required this.report,
    required this.options,
    required this.onOptionsChanged,
    this.controller,
    this.onBrowseOutputDirectory,
  });

  final SetupReport? report;
  final RecordingOptions options;
  final ValueChanged<RecordingOptions> onOptionsChanged;
  final RecorderController? controller;
  final Future<void> Function()? onBrowseOutputDirectory;

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
              _RecorderHeading(controller: controller),
              if (controller?.preferenceNotice != null) ...[
                const SizedBox(height: 12),
                Text(controller!.preferenceNotice!),
              ],
              const SizedBox(height: 26),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final optionsPanel = _OptionsPanel(
                    controller: controller,
                    options: options,
                    onOptionsChanged: onOptionsChanged,
                    onBrowseOutputDirectory: onBrowseOutputDirectory,
                  );
                  final lockPanel = _PreflightPanel(
                    controller: controller,
                    report: report,
                    options: options,
                  );
                  if (compact) {
                    return Column(
                      children: [
                        optionsPanel,
                        const SizedBox(height: 16),
                        lockPanel,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: optionsPanel),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: lockPanel),
                    ],
                  );
                },
              ),
              if (controller != null &&
                  controller!.recentOutputPaths.isNotEmpty) ...[
                const SizedBox(height: 16),
                _RecentRecordings(
                  paths: controller!.recentOutputPaths,
                  onOpenOutput: controller!.openOutput,
                  onOpenFolder: controller!.openOutputFolder,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecorderHeading extends StatelessWidget {
  const _RecorderHeading({required this.controller});

  final RecorderController? controller;

  @override
  Widget build(BuildContext context) {
    final busy = controller?.isBusy ?? false;
    final ready = controller?.canStart ?? false;
    final label = controller == null
        ? 'PREVIEW LOCK'
        : busy
            ? 'RECORDING'
            : ready
                ? 'READY'
                : 'SETUP NEEDED';
    final color =
        busy || ready ? const Color(0xFFB8F1D3) : const Color(0xFFFFC67A);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record saved replays',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                busy
                    ? 'Afterimage is working through the batch. You can stop safely at any time.'
                    : 'Start with one replay to check the picture and sound. Choose more after the test works.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                busy ? Icons.fiber_manual_record : Icons.lock_outline,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentRecordings extends StatelessWidget {
  const _RecentRecordings({
    required this.paths,
    required this.onOpenOutput,
    required this.onOpenFolder,
  });

  final List<String> paths;
  final Future<void> Function(String path) onOpenOutput;
  final Future<void> Function() onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Recent recordings',
      subtitle: 'Open a video again or open the folder where it was saved.',
      trailing: OutlinedButton.icon(
        key: const ValueKey('open-recent-output-folder'),
        onPressed: () => unawaited(onOpenFolder()),
        icon: const Icon(Icons.folder_open_outlined),
        label: const Text('Open folder'),
      ),
      child: Column(
        children: [
          for (final path in paths.take(5))
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
                onPressed: () => unawaited(onOpenOutput(path)),
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

class _OptionsPanel extends StatelessWidget {
  const _OptionsPanel({
    required this.controller,
    required this.options,
    required this.onOptionsChanged,
    this.onBrowseOutputDirectory,
  });

  final RecorderController? controller;
  final RecordingOptions options;
  final ValueChanged<RecordingOptions> onOptionsChanged;
  final Future<void> Function()? onBrowseOutputDirectory;

  @override
  Widget build(BuildContext context) {
    final busy = controller?.isBusy ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          title: 'Batch size',
          subtitle:
              'Afterimage starts at the replay you highlight and moves upward through the list.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: ReplayCountOption.values
                    .map(
                      (choice) => ChoiceChip(
                        key: ValueKey('replay-count-${choice.name}'),
                        label: Text(choice.label),
                        selected: options.replayCount == choice,
                        onSelected: busy
                            ? null
                            : (_) => onOptionsChanged(
                                  options.copyWith(replayCount: choice),
                                ),
                      ),
                    )
                    .toList(),
              ),
              if (options.replayCount == ReplayCountOption.custom) ...[
                const SizedBox(height: 14),
                _CustomReplayCountField(
                  value: options.customReplayCount,
                  enabled: !busy,
                  onChanged: (value) => onOptionsChanged(
                    options.copyWith(customReplayCount: value),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Video output',
          subtitle: 'Choose how the completed captures should be grouped.',
          child: RadioGroup<VideoMode>(
            groupValue: options.videoMode,
            onChanged: (value) {
              if (!busy && value != null) {
                onOptionsChanged(options.copyWith(videoMode: value));
              }
            },
            child: Column(
              children: VideoMode.values
                  .map(
                    (mode) => RadioListTile<VideoMode>(
                      key: ValueKey('video-mode-${mode.name}'),
                      value: mode,
                      title: Text(mode.label),
                      subtitle: Text(mode.description),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      enabled: !busy,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Replay controls',
          subtitle:
              'Choose how Afterimage should move through the saved replay list.',
          child: RadioGroup<InputMode>(
            groupValue: options.inputMode,
            onChanged: (value) {
              if (!busy && value != null) {
                onOptionsChanged(options.copyWith(inputMode: value));
              }
            },
            child: Column(
              children: InputMode.values.map(
                (mode) {
                  final readiness = controller?.readinessFor(mode);
                  return _InputModeTile(
                    tileKey: ValueKey('input-mode-${mode.name}'),
                    mode: mode,
                    available: readiness?.available ?? false,
                    availabilityDetail: readiness?.detail,
                    checking:
                        readiness == null && (controller?.isChecking ?? false),
                    enabled: !busy &&
                        (options.inputMode == mode ||
                            (readiness?.available ?? false)),
                  );
                },
              ).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Output folder',
          subtitle: 'Where Afterimage will save the finished recordings.',
          child: _OutputFolderField(
            value: options.outputDirectory,
            enabled: !busy,
            isPicking: controller?.isPickingDirectory ?? false,
            onChanged: (value) => onOptionsChanged(
              options.copyWith(outputDirectory: value),
            ),
            onBrowse: onBrowseOutputDirectory,
          ),
        ),
      ],
    );
  }
}

class _CustomReplayCountField extends StatefulWidget {
  const _CustomReplayCountField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_CustomReplayCountField> createState() =>
      _CustomReplayCountFieldState();
}

class _CustomReplayCountFieldState extends State<_CustomReplayCountField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value.toString());

  @override
  void didUpdateWidget(covariant _CustomReplayCountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value.toString()) {
      _controller.value = TextEditingValue(
        text: widget.value.toString(),
        selection:
            TextSelection.collapsed(offset: widget.value.toString().length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const ValueKey('custom-replay-count'),
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        final count = int.tryParse(value);
        if (count != null) {
          widget.onChanged(count);
        }
      },
      decoration: const InputDecoration(
        labelText: 'Number of replays',
        helperText: 'Choose a positive number for a custom batch.',
        prefixIcon: Icon(Icons.format_list_numbered_rounded),
      ),
    );
  }
}

class _InputModeTile extends StatelessWidget {
  const _InputModeTile({
    required this.tileKey,
    required this.mode,
    required this.available,
    required this.availabilityDetail,
    required this.checking,
    required this.enabled,
  });

  final Key tileKey;
  final InputMode mode;
  final bool available;
  final String? availabilityDetail;
  final bool checking;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final reportedDetail = availabilityDetail?.trim();
    final availability = checking
        ? 'Checking availability…'
        : reportedDetail != null && reportedDetail.isNotEmpty
            ? reportedDetail
            : available
                ? 'Ready on this machine.'
                : 'Availability could not be determined.';
    return RadioListTile<InputMode>(
      key: tileKey,
      value: mode,
      enabled: enabled,
      title: Text(_friendlyInputTitle(mode)),
      subtitle: Text('${_friendlyInputDescription(mode)} $availability'),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  String _friendlyInputTitle(InputMode mode) {
    return mode == InputMode.keyboard
        ? 'Use keyboard controls'
        : 'Use a virtual gamepad';
  }

  String _friendlyInputDescription(InputMode mode) {
    return mode == InputMode.keyboard
        ? 'Afterimage sends the replay menu keys for you.'
        : 'Afterimage uses a separate gamepad for the replay menu.';
  }
}

class _OutputFolderField extends StatefulWidget {
  const _OutputFolderField({
    required this.value,
    required this.enabled,
    required this.isPicking,
    required this.onChanged,
    required this.onBrowse,
  });

  final String value;
  final bool enabled;
  final bool isPicking;
  final ValueChanged<String> onChanged;
  final Future<void> Function()? onBrowse;

  @override
  State<_OutputFolderField> createState() => _OutputFolderFieldState();
}

class _OutputFolderFieldState extends State<_OutputFolderField> {
  late final TextEditingController _textController =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _OutputFolderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_textController.text != widget.value &&
        widget.value != oldWidget.value) {
      _textController.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const ValueKey('output-folder'),
      controller: _textController,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: 'Choose an output folder…',
        prefixIcon: const Icon(Icons.folder_outlined),
        suffixIcon: widget.isPicking
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                key: const ValueKey('browse-output-folder'),
                onPressed: widget.enabled && widget.onBrowse != null
                    ? () => unawaited(widget.onBrowse!())
                    : null,
                tooltip: 'Choose an output folder',
                icon: const Icon(Icons.folder_open_outlined),
              ),
      ),
    );
  }
}

class _PreflightPanel extends StatelessWidget {
  const _PreflightPanel({
    required this.controller,
    required this.report,
    required this.options,
  });

  final RecorderController? controller;
  final SetupReport? report;
  final RecordingOptions options;

  @override
  Widget build(BuildContext context) {
    final active = controller != null;
    final busy = controller?.isBusy ?? false;
    final blockers =
        active ? controller!.blockers : _legacyBlockers(report, options);
    final progress = controller?.progress;
    final isReady = blockers.isEmpty && active;
    final color =
        busy || isReady ? const Color(0xFFB8F1D3) : const Color(0xFFFFC67A);

    return SectionCard(
      title: busy ? 'Recording progress' : 'Ready to record',
      subtitle: busy
          ? 'Afterimage is waiting for each replay to finish before it moves on.'
          : 'You can see exactly what is ready before the start button unlocks.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy && progress != null) ...[
            _ProgressSummary(progress: progress),
            const SizedBox(height: 16),
          ] else if (controller?.result != null) ...[
            _TerminalResult(
              result: controller!.result!,
              outputPaths: controller!.outputPaths,
              outputDirectory: controller!.batchOutputDirectory,
              onOpenOutputFolder: controller!.openOutputFolder,
              onOpenOutput: controller!.openOutput,
            ),
            const SizedBox(height: 16),
          ],
          if (controller?.error != null) ...[
            _ErrorNotice(message: controller!.error.toString()),
            const SizedBox(height: 14),
          ],
          if (controller?.enforceGuidedChecks == true) ...[
            _GuidedRecorderChecks(controller: controller!),
            const SizedBox(height: 14),
          ],
          if (!busy) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: color.withValues(alpha: 0.24)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isReady ? Icons.check_circle_outline : Icons.lock_outline,
                    color: color,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      isReady
                          ? 'Everything is ready. Start when you are ready, and Afterimage will preserve partial output if you stop.'
                          : 'Recording stays locked until every required check, the selected input mode, and the output folder are ready.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isReady
                                ? const Color(0xFFD1F7DF)
                                : const Color(0xFFFFD9A8),
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              blockers.isEmpty ? 'READY' : 'NEXT ACTION',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
            ),
            const SizedBox(height: 9),
            if (blockers.isEmpty)
              Text(
                'The selected controls and required services passed their checks.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              )
            else
              ...blockers.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          color: Color(0xFFFFC67A),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          reason,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    height: 1.35,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: busy
                ? FilledButton.icon(
                    key: const ValueKey('stop-batch'),
                    onPressed: controller!.isStopping
                        ? null
                        : () => unawaited(controller!.requestStop()),
                    icon: controller!.isStopping
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      controller!.isStopping
                          ? 'Saving before stopping…'
                          : 'Stop safely',
                    ),
                  )
                : FilledButton.icon(
                    key: const ValueKey('start-batch'),
                    onPressed: controller?.canStart == true
                        ? () => unawaited(controller!.startBatch())
                        : null,
                    icon: Icon(
                      controller?.canStart == true
                          ? Icons.fiber_manual_record
                          : Icons.lock_outline,
                    ),
                    label: Text(
                      controller?.isChecking == true
                          ? 'Checking readiness…'
                          : 'Start batch',
                    ),
                  ),
          ),
          const SizedBox(height: 11),
          Center(
            child: Text(
              busy
                  ? 'Stop keeps the current recording as a partial output.'
                  : active
                      ? 'Existing files are never overwritten.'
                      : 'The recorder backend is not connected in this build.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _legacyBlockers(SetupReport? report, RecordingOptions options) {
    final reasons = <String>[];
    if (report == null) {
      reasons.add('Local checks are still running.');
    } else {
      reasons.addAll(
        report.blockingChecks.map((check) => '${check.title}: ${check.detail}'),
      );
    }
    if (options.outputDirectory.trim().isEmpty) {
      reasons.add('Choose an output folder before starting a batch.');
    }
    if (reasons.isEmpty) {
      reasons.add('The recording engine is not available in this build.');
    }
    return reasons;
  }
}

class _GuidedRecorderChecks extends StatelessWidget {
  const _GuidedRecorderChecks({required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            CheckboxListTile(
              key: const ValueKey('recorder-replay-list-prepared'),
              value: controller.replayListPrepared,
              onChanged: controller.isBusy
                  ? null
                  : (value) => controller.setReplayListPrepared(value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('The bottom replay is highlighted in GGST.'),
              subtitle: const Text(
                'Afterimage will move upward from the replay you selected.',
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('recorder-picture-and-sound-confirmed'),
              value: controller.pictureAndSoundConfirmed,
              onChanged: controller.isBusy
                  ? null
                  : (value) =>
                      controller.confirmPictureAndSound(value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('The one replay test has picture and sound.'),
              subtitle: const Text(
                'Check the saved test before choosing more than one replay.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.progress});

  final ReplayBatchProgress progress;

  @override
  Widget build(BuildContext context) {
    final current = progress.currentReplay == 0
        ? 'Preparing the first replay…'
        : 'Replay ${progress.currentReplay} of ${progress.totalReplays}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                current,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text(
              '${progress.completedReplays}/${progress.totalReplays}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: progress.totalReplays > 0 ? progress.fraction : null,
          ),
        ),
        const SizedBox(height: 11),
        Text(
          progress.detail ?? 'Working safely…',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
        ),
      ],
    );
  }
}

class _TerminalResult extends StatelessWidget {
  const _TerminalResult({
    required this.result,
    required this.outputPaths,
    this.outputDirectory,
    this.onOpenOutputFolder,
    this.onOpenOutput,
  });

  final ReplayBatchResult result;
  final List<String> outputPaths;
  final String? outputDirectory;
  final Future<void> Function()? onOpenOutputFolder;
  final Future<void> Function(String path)? onOpenOutput;

  @override
  Widget build(BuildContext context) {
    final saved = result.replays
        .where(
          (replay) =>
              replay.status == ReplayResultStatus.recorded ||
              replay.output?.partial == false,
        )
        .length;
    final stopped = result.outcome == ReplayBatchOutcome.stopped;
    final needsAttention = stopped && result.error != null;
    final failed =
        result.outcome == ReplayBatchOutcome.failed || needsAttention;
    final color = failed
        ? const Color(0xFFFF9E9E)
        : stopped
            ? const Color(0xFFFFC67A)
            : const Color(0xFFB8F1D3);
    final headline = needsAttention
        ? 'Recording stopped, but saving needs attention'
        : failed
            ? 'Batch stopped after a failure'
            : stopped
                ? 'Batch stopped safely'
                : 'Batch completed';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.error_outline
                    : stopped
                        ? Icons.stop_circle_outlined
                        : Icons.check_circle_outline,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '$saved replay${saved == 1 ? '' : 's'} saved.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          if (outputPaths.isNotEmpty) ...[
            const SizedBox(height: 9),
            ...outputPaths.take(3).map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: color.withValues(alpha: 0.9),
                          ),
                    ),
                  ),
                ),
          ],
          if (outputDirectory != null && outputDirectory!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Saved in $outputDirectory',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color.withValues(alpha: 0.9),
                  ),
            ),
          ],
          if (onOpenOutputFolder != null ||
              (onOpenOutput != null && outputPaths.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                if (onOpenOutputFolder != null)
                  OutlinedButton.icon(
                    key: const ValueKey('open-output-folder'),
                    onPressed: () => unawaited(onOpenOutputFolder!()),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open folder'),
                  ),
                if (onOpenOutput != null && outputPaths.isNotEmpty)
                  OutlinedButton.icon(
                    key: const ValueKey('play-latest-output'),
                    onPressed: () => unawaited(onOpenOutput!(outputPaths.last)),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play latest'),
                  ),
              ],
            ),
          ],
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
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9E9E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF9E9E).withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF9E9E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFFFCACA),
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
