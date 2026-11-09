import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/notes_models.dart';
import '../services/notes_repository.dart';
import 'widgets/notes_clip_player.dart';
import 'widgets/status_surface.dart';

// The sequence list: the finder's situations per opponent, with Save and Save
// mixup writing StriveLabs recordings. Code names keep "notes" from the page this
// replaced.

class NotesListPage extends StatefulWidget {
  const NotesListPage({
    super.key,
    required this.repository,
    required this.onOpen,
    required this.onClose,
  });

  final NotesRepository repository;
  final ValueChanged<NotePreview> onOpen;
  final VoidCallback onClose;

  @override
  State<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends State<NotesListPage> {
  List<NotePreview>? _previews;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final previews = await widget.repository.list();
      if (!mounted) return;
      setState(() {
        _previews = previews;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const ValueKey('notes-list'),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'SEQUENCES',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('close-notes'),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Defensive situations from your replay batches. Save one as a '
                'StriveLabs recording to lab it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                StatusSurface(
                  tone: StatusTone.failed,
                  icon: Icons.error_outline,
                  child: Text('Sequences could not be loaded: $_error'),
                )
              else if (_previews == null)
                const Center(child: CircularProgressIndicator())
              else if (_previews!.isEmpty)
                const _EmptyNotes()
              else
                for (final preview in _previews!)
                  _NotesListTile(
                    preview: preview,
                    onOpen: () => widget.onOpen(preview),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesListTile extends StatelessWidget {
  const _NotesListTile({required this.preview, required this.onOpen});

  final NotePreview preview;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = formatNoteDate(preview.createdAt);
    final cards = preview.cardCount;
    final flagged = preview.flaggedCount;
    return Card(
      key: ValueKey('notes-entry-${preview.documentPath}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 15, 14, 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date == null
                        ? preview.batchLabel
                        : '${preview.batchLabel}  ·  $date',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'vs ${preview.opponent}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$cards ${cards == 1 ? 'situation' : 'situations'}'
                    '  ·  $flagged flagged',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('open-notes-entry'),
              onPressed: onOpen,
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();
  @override
  Widget build(BuildContext context) {
    return const StatusSurface(
      tone: StatusTone.blocked,
      icon: Icons.playlist_play_rounded,
      child: Text('No sequences yet. They appear after a recorded batch.'),
    );
  }
}

class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.repository,
    required this.preview,
    required this.onBack,
    this.playerFactory = createMediaKitClipPlayer,
    this.onSavingChanged,
  });

  final NotesRepository repository;
  final NotePreview preview;
  final VoidCallback onBack;
  final NotesClipPlayerSessionFactory playerFactory;
  final ValueChanged<bool>? onSavingChanged;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  NoteSequenceData? _data;
  Object? _error;
  bool _saving = false;
  final Set<String> _saved = <String>{};
  final Set<String> _expanded = <String>{};
  // The one sequence whose clip is open, under its row; null when none is.
  String? _openSequence;
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    final messenger = _scaffoldMessenger;
    if (messenger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger.mounted) messenger.hideCurrentSnackBar();
      });
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.repository.read(widget.preview);
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _save(String savedKey, List<LabRecording> recordings) async {
    final data = _data;
    if (data == null || _saving || recordings.isEmpty) return;
    setState(() => _saving = true);
    widget.onSavingChanged?.call(true);
    String message;
    var succeeded = false;
    try {
      final result =
          await widget.repository.saveRecordings(data.document, recordings);
      message = result.message;
      succeeded = true;
    } on Object catch (error) {
      message = 'Could not save: $error';
    }
    widget.onSavingChanged?.call(false);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (succeeded) _saved.add(savedKey);
    });
    _scaffoldMessenger?.hideCurrentSnackBar();
    _scaffoldMessenger?.showSnackBar(
      SnackBar(
        key: ValueKey(succeeded ? 'save-done' : 'save-failed'),
        content: Text(message),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const ValueKey('notes-page'),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'SEQUENCES  ·  ${widget.preview.batchLabel}  ·  vs ${widget.preview.opponent}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('back-from-sequences'),
                    onPressed: _saving ? null : widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null)
                StatusSurface(
                  tone: StatusTone.failed,
                  icon: Icons.error_outline,
                  child: Text('These sequences could not be opened: $_error'),
                )
              else if (data == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                _PageNotices(document: data.document),
                for (final card in data.document.cards)
                  _buildCard(context, data, card),
                if (data.document.cards.isEmpty)
                  const StatusSurface(
                    tone: StatusTone.blocked,
                    icon: Icons.playlist_play_rounded,
                    child: Text('No defensive situations in this batch.'),
                  ),
                if (data.document.clipErrors.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    data.document.clipErrors.join('\n'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    NoteSequenceData data,
    SequenceCard card,
  ) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final crush = card.isGuardCrush;
    final expanded = card.flagged || crush || _expanded.contains(card.id);
    final header = card.header ??
        [
          '${card.count} ${card.count == 1 ? 'time' : 'times'}',
          if (card.decided > 0) 'hit ${card.hits} of ${card.decided}',
          if (card.damage > 0) '${card.damage} damage',
        ].join('  ·  ');
    final leadIns = card.leadInText ??
        (card.leadIns.isEmpty
            ? null
            : 'lead-ins: ${card.leadIns.map((leadIn) => '${leadIn.label} x${leadIn.count}').join(', ')}');
    return Card(
      key: ValueKey('sequence-card-${card.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: crush
            ? const EdgeInsets.fromLTRB(18, 12, 18, 10)
            : const EdgeInsets.fromLTRB(18, 16, 18, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    card.title,
                    style: (crush
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(
                      color: crush
                          ? AfterimageTheme.blockedText
                          : AfterimageTheme.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  header,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            for (final flag in card.flags)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  flag.player == null
                      ? flag.reason
                      : '${flag.reason} (${flag.player})',
                  key: ValueKey('flag-${card.id}-${flag.kind}'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AfterimageTheme.blockedText,
                  ),
                ),
              ),
            if (leadIns != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  leadIns,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            for (var index = 0; index < card.mixups.length; index++)
              _buildMixup(card, index),
            if (!expanded)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('show-sequences-${card.id}'),
                  onPressed: () => setState(() => _expanded.add(card.id)),
                  child: Text(
                    'Show ${card.sequences.length} '
                    '${card.sequences.length == 1 ? 'sequence' : 'sequences'}',
                  ),
                ),
              )
            else ...[
              SizedBox(height: crush ? 6 : 10),
              for (final sequence in card.sequences) ...[
                _buildSequence(sequence),
                if (_openSequence == sequence.id && sequence.clip != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
                    child: NotesClipPlayer(
                      key: ValueKey('clip-${sequence.id}'),
                      playerCardKey: ValueKey('clip-player-${sequence.id}'),
                      clip: sequence.clip!,
                      filePath: _clipPath(data.preview, sequence.clip!),
                      playerFactory: widget.playerFactory,
                      playOnOpen: true,
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMixup(SequenceCard card, int index) {
    final mixup = card.mixups[index];
    final theme = Theme.of(context);
    final savedKey = 'mixup-${card.id}-$index';
    final options =
        mixup.files.map((file) => '${file.followUp} x${file.count}').join(', ');
    final heading = mixup.heading;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: heading == null
                ? Text(
                    'mixup ${mixup.label}: $options',
                    style: theme.textTheme.bodyMedium,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(heading, style: theme.textTheme.bodyMedium),
                      Padding(
                        padding: const EdgeInsets.only(left: 14, top: 2),
                        child: Text(options, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 10),
          _SaveButton(
            buttonKey: ValueKey('save-mixup-${card.id}-$index'),
            label: 'Save mixup (${mixup.files.length})',
            saved: _saved.contains(savedKey),
            onPressed: _saving
                ? null
                : () => unawaited(_save(
                      savedKey,
                      [for (final file in mixup.files) file.recording],
                    )),
          ),
        ],
      ),
    );
  }

  Widget _buildSequence(LabSequence sequence) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final recording = sequence.recording;
    final open = _openSequence == sequence.id;
    final line = sequence.line;
    final result = sequence.result;
    return Container(
      key: ValueKey('sequence-${sequence.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      decoration: BoxDecoration(
        color: open ? AfterimageTheme.panelRaised : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          IconButton(
            key: ValueKey('play-${sequence.id}'),
            tooltip: sequence.clip == null
                ? 'No clip'
                : open
                    ? 'Close clip'
                    : 'Play clip',
            onPressed: sequence.clip == null
                ? null
                : () => setState(
                      () => _openSequence = open ? null : sequence.id,
                    ),
            icon: Icon(open ? Icons.stop_rounded : Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sequence.where,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (line != null && result != null) ...[
                  Text(line, style: theme.textTheme.bodyMedium),
                  Text(
                    result,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ] else
                  Text(sequence.summary, style: theme.textTheme.bodyMedium),
                if (recording == null && sequence.recordingError != null)
                  Text(
                    'cannot save: ${sequence.recordingError}',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _SaveButton(
            buttonKey: ValueKey('save-${sequence.id}'),
            label: recording == null ? 'Save' : 'Save (${recording.frames}f)',
            saved: _saved.contains(sequence.id),
            onPressed: recording == null || _saving
                ? null
                : () => unawaited(_save(sequence.id, [recording])),
          ),
        ],
      ),
    );
  }

  String _clipPath(NotePreview preview, NoteClip clip) {
    final clipsDirectory = _joinPath(preview.directoryPath, 'clips');
    return _joinPath(clipsDirectory, clip.file);
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.buttonKey,
    required this.label,
    required this.saved,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool saved;
  final VoidCallback? onPressed;

  /// One width for every Save button, so they line up down the page whatever
  /// the frame count in the label.
  static const double width = 172;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: OutlinedButton.icon(
        key: buttonKey,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        icon: Icon(
          saved ? Icons.check_rounded : Icons.save_alt_rounded,
          size: 18,
        ),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(saved ? 'Saved' : label, maxLines: 1),
        ),
      ),
    );
  }
}

class _PageNotices extends StatelessWidget {
  const _PageNotices({required this.document});

  final SequenceDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strivelabs = document.strivelabsRecordings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (document.warnings.isNotEmpty) ...[
          StatusSurface(
            tone: StatusTone.blocked,
            icon: Icons.warning_amber_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final warning in document.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(warning),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          strivelabs == null
              ? 'StriveLabs was not found. Save writes to the batch folder only.'
              : 'Save writes to StriveLabs recordings and the batch folder. '
                  'In game: F5, Recordings, Load into Game\'s Slot N, Player '
                  'Side = the dummy\'s side.',
          key: const ValueKey('strivelabs-notice'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

String? formatNoteDate(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _joinPath(String base, String child) {
  if (child.isEmpty) return base;
  if (child.startsWith('/') || child.startsWith('\\')) return child;
  if (base.endsWith('/') || base.endsWith('\\')) return '$base$child';
  return '$base${Platform.pathSeparator}$child';
}
