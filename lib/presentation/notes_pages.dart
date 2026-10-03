import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/notes_models.dart';
import '../services/notes_repository.dart';
import 'widgets/notes_clip_player.dart';
import 'widgets/status_surface.dart';

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
                      'NOTES',
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
                'Draft notes from the replay batches. Legacy previews can be read, but not applied.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                StatusSurface(
                  tone: StatusTone.failed,
                  icon: Icons.error_outline,
                  child: Text('Notes could not be loaded: $_error'),
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
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = preview.isLegacy;
    final foreground = muted
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : theme.colorScheme.onSurface;
    final date = formatNoteDate(preview.createdAt);
    return Card(
      key: ValueKey('notes-entry-${preview.sectionPath}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: muted ? 0.62 : 1,
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
                        color: foreground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'vs ${preview.opponent}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      preview.isLegacy
                          ? 'made before the notes page; cannot be applied'
                          : '${preview.cardCount} ${preview.cardCount == 1 ? 'situation' : 'situations'}  ·  ${preview.isApplied ? 'Applied' : 'Draft'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted
                            ? foreground
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onOpen != null)
                TextButton(
                  key: ValueKey(
                    preview.isLegacy
                        ? 'open-legacy-notes-entry'
                        : 'open-notes-entry',
                  ),
                  onPressed: onOpen,
                  child: const Text('Open'),
                ),
            ],
          ),
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
      icon: Icons.notes_outlined,
      child: Text('No notes have been generated yet.'),
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
    this.onEditingChanged,
    this.onSavingChanged,
  });

  final NotesRepository repository;
  final NotePreview preview;
  final VoidCallback onBack;
  final NotesClipPlayerSessionFactory playerFactory;
  final ValueChanged<bool>? onEditingChanged;
  final ValueChanged<bool>? onSavingChanged;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  NoteSectionData? _data;
  Object? _error;
  int? _editingIndex;
  TextEditingController? _editor;
  bool _saving = false;
  bool _applying = false;
  final Map<String, int> _selectedClips = <String, int>{};
  String? _playingCard;
  ApplySectionResult? _applyResult;
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
    _editor?.dispose();
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

  void _beginEdit(int index) {
    final data = _data;
    if (data == null ||
        data.preview.isLegacy ||
        _editingIndex != null ||
        _saving) {
      return;
    }
    _editor?.dispose();
    _editor = TextEditingController(text: data.document.cards[index].text);
    setState(() => _editingIndex = index);
    widget.onEditingChanged?.call(true);
  }

  void _cancelEdit() {
    if (_editingIndex == null) return;
    _editor?.dispose();
    _editor = null;
    setState(() => _editingIndex = null);
    widget.onEditingChanged?.call(false);
  }

  Future<void> _saveEdit() async {
    final data = _data;
    final index = _editingIndex;
    final editor = _editor;
    if (data == null || index == null || editor == null || _saving) return;
    setState(() => _saving = true);
    widget.onSavingChanged?.call(true);
    try {
      final document = data.document.replaceCard(
        index,
        data.document.cards[index].copyWith(text: editor.text),
      );
      await widget.repository.write(widget.preview, document);
      if (!mounted) {
        widget.onSavingChanged?.call(false);
        return;
      }
      _editor?.dispose();
      _editor = null;
      setState(() {
        _data = NoteSectionData(
          preview: data.preview,
          document: document,
          warnings: data.warnings,
          clipIndex: data.clipIndex,
        );
        _editingIndex = null;
        _saving = false;
      });
      widget.onEditingChanged?.call(false);
      widget.onSavingChanged?.call(false);
    } on Object catch (error) {
      if (!mounted) {
        widget.onSavingChanged?.call(false);
        return;
      }
      setState(() => _saving = false);
      widget.onSavingChanged?.call(false);
      _showError(error);
    }
  }

  Future<void> _deleteCard(int index) async {
    final data = _data;
    if (data == null ||
        data.preview.isLegacy ||
        _editingIndex != null ||
        _saving) {
      return;
    }
    final deleted = data.document.cards[index];
    final deletedKey = _cardKey(deleted, index);
    setState(() => _saving = true);
    widget.onSavingChanged?.call(true);
    try {
      final document = data.document.removeCard(index);
      await widget.repository.write(widget.preview, document);
      if (!mounted) {
        widget.onSavingChanged?.call(false);
        return;
      }
      setState(() {
        _data = NoteSectionData(
          preview: data.preview,
          document: document,
          warnings: data.warnings,
          clipIndex: data.clipIndex,
        );
        _saving = false;
        _selectedClips.remove(deletedKey);
        if (_playingCard == deletedKey) _playingCard = null;
      });
      widget.onSavingChanged?.call(false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Situation deleted.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(_undoDelete(index, deleted)),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) {
        widget.onSavingChanged?.call(false);
        return;
      }
      setState(() => _saving = false);
      widget.onSavingChanged?.call(false);
      _showError(error);
    }
  }

  Future<void> _undoDelete(int index, NoteCard card) async {
    if (!mounted) return;
    final data = _data;
    if (data == null || _editingIndex != null || _saving) return;
    setState(() => _saving = true);
    widget.onSavingChanged?.call(true);
    try {
      final document = data.document.insertCard(index, card);
      await widget.repository.write(widget.preview, document);
      if (!mounted) {
        widget.onSavingChanged?.call(false);
        return;
      }
      setState(() {
        _data = NoteSectionData(
          preview: data.preview,
          document: document,
          warnings: data.warnings,
          clipIndex: data.clipIndex,
        );
        _saving = false;
      });
      widget.onSavingChanged?.call(false);
    } on Object catch (error) {
      if (!mounted) {
        widget.onSavingChanged?.call(false);
        return;
      }
      setState(() => _saving = false);
      widget.onSavingChanged?.call(false);
      _showError(error);
    }
  }

  Future<void> _apply() async {
    final data = _data;
    if (data == null ||
        data.preview.isLegacy ||
        _editingIndex != null ||
        _saving ||
        data.preview.isApplied ||
        _applying) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply notes?'),
        content:
            Text('Write these notes into the ${data.preview.opponent} note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _applying = true);
    late ApplySectionResult result;
    try {
      result = await widget.repository.apply(data.preview);
    } on Object catch (error) {
      result = ApplySectionResult.fromExitCode(
        1,
        opponent: data.preview.opponent,
        stderr: error.toString(),
      );
    }
    if (!mounted) return;
    if (result.succeeded) {
      NoteSectionData? refreshedData;
      try {
        final refreshed = await widget.repository.refreshPreview(data.preview);
        if (refreshed != null) {
          try {
            refreshedData = await widget.repository.read(refreshed);
          } on Object {
            // The successful apply message remains useful if metadata refresh fails.
          }
        }
      } on Object {
        // The successful apply message remains useful if metadata refresh fails.
      }
      if (!mounted) return;
      if (refreshedData != null) _data = refreshedData;
    }
    setState(() {
      _applyResult = result;
      _applying = false;
    });
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Notes could not be saved: $error')),
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
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      data == null
                          ? 'NOTES'
                          : 'NOTES  ·  ${data.preview.batchLabel}  ·  vs ${data.preview.opponent}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('discard-notes'),
                    onPressed: _saving || _applying || _editingIndex != null
                        ? null
                        : widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Discard'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null)
                StatusSurface(
                  tone: StatusTone.failed,
                  icon: Icons.error_outline,
                  child: Text('This notes draft could not be opened: $_error'),
                )
              else if (data == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (data.preview.isLegacy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Made before the notes page; cannot be applied.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (data.warnings.isNotEmpty) ...[
                  StatusSurface(
                    tone: StatusTone.blocked,
                    icon: Icons.warning_amber_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final warning in data.warnings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(warning),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (var index = 0; index < data.document.cards.length; index++)
                  _buildCard(context, data, index),
                if (data.document.cards.isEmpty)
                  const StatusSurface(
                    tone: StatusTone.blocked,
                    icon: Icons.notes_outlined,
                    child: Text('There are no situations left in this draft.'),
                  ),
                if (data.clipIndex?.errors.isNotEmpty == true) ...[
                  const SizedBox(height: 14),
                  Text(
                    data.clipIndex!.errors.join('\n'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (_applyResult != null)
                  StatusSurface(
                    tone: _applyResult!.succeeded
                        ? StatusTone.ready
                        : StatusTone.failed,
                    icon: _applyResult!.succeeded
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    child: Text(_applyResult!.message),
                  ),
                const SizedBox(height: 14),
                _buildApplyActions(data),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, NoteSectionData data, int index) {
    final card = data.document.cards[index];
    final cardKey = _cardKey(card, index);
    final editing = _editingIndex == index;
    final locked = _editingIndex != null;
    final legacy = data.preview.isLegacy;
    final clips = matchClipsForCard(card, data.clipIndex);
    final playerCardKey = card.id == null && data.document.cards.length == 1
        ? null
        : ValueKey('clip-player-$cardKey');
    final selected = (_selectedClips[cardKey] ?? 0) < clips.length
        ? _selectedClips[cardKey] ?? 0
        : 0;
    return Card(
      key: ValueKey('note-card-${card.id ?? index}'),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _NoteHeadingText(heading: card.heading),
                ),
                if (!editing && !legacy) ...[
                  TextButton(
                    key: ValueKey('edit-note-$index'),
                    onPressed:
                        locked || _saving ? null : () => _beginEdit(index),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    key: ValueKey('delete-note-$index'),
                    onPressed:
                        locked || _saving ? null : () => _deleteCard(index),
                    child: const Text('Delete'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (editing)
              TextField(
                key: const ValueKey('note-edit-field'),
                controller: _editor,
                autofocus: true,
                readOnly: _saving,
                maxLines: null,
                minLines: 8,
                textCapitalization: TextCapitalization.sentences,
              )
            else
              _MarkdownNoteText(text: card.body),
            if (editing) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('cancel-note-edit'),
                    onPressed: _saving ? null : _cancelEdit,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('save-note-edit'),
                    onPressed: _saving ? null : _saveEdit,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
            if (!editing && clips.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (var clipIndex = 0; clipIndex < clips.length; clipIndex++)
                    ChoiceChip(
                      key: ValueKey('clip-chip-$cardKey-$clipIndex'),
                      label: Text(clips[clipIndex].caption()),
                      selected: selected == clipIndex,
                      onSelected: (_) => setState(() {
                        _selectedClips[cardKey] = clipIndex;
                        _playingCard = null;
                      }),
                    ),
                ],
              ),
              NotesClipPlayer(
                playerCardKey: playerCardKey,
                clip: clips[selected],
                filePath: _clipPath(data.preview, clips[selected]),
                playerFactory: widget.playerFactory,
                pauseRequested: _playingCard != null && _playingCard != cardKey,
                onStarted: () {
                  if (mounted) setState(() => _playingCard = cardKey);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApplyActions(NoteSectionData data) {
    if (data.preview.isLegacy) return const SizedBox.shrink();
    final applied = data.preview.isApplied || _applyResult?.succeeded == true;
    final appliedAt = data.preview.metadata?.appliedAt;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (applied)
          Text(
            'Applied ${formatNoteDate(appliedAt) ?? 'just now'}',
            key: const ValueKey('notes-applied'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AfterimageTheme.ready,
                  fontWeight: FontWeight.w700,
                ),
          )
        else
          FilledButton.icon(
            key: const ValueKey('apply-notes'),
            onPressed:
                _applying || _saving || _editingIndex != null ? null : _apply,
            icon: _applying
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text('Apply to ${data.preview.opponent} note'),
          ),
      ],
    );
  }

  String _clipPath(NotePreview preview, NoteClip clip) {
    final clipsDirectory = _joinPath(preview.directoryPath, 'clips');
    return _joinPath(clipsDirectory, clip.file);
  }

  String _cardKey(NoteCard card, int index) => card.id ?? '$index';
}

class _MarkdownNoteText extends StatelessWidget {
  const _MarkdownNoteText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final subtle = line.startsWith('lab:') || line.startsWith('seen:');
      spans.addAll(
        _wikilinkSpans(
          line,
          baseStyle: theme.textTheme.bodyMedium?.copyWith(
            color: subtle
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
            height: 1.45,
            fontStyle: subtle ? FontStyle.italic : FontStyle.normal,
          ),
          linkStyle: theme.textTheme.bodyMedium?.copyWith(
            color: AfterimageTheme.accent,
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
      );
      if (index < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

class _NoteHeadingText extends StatelessWidget {
  const _NoteHeadingText({required this.heading});

  final String heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = heading.replaceFirst(RegExp(r'^### '), '');
    return Text.rich(
      TextSpan(
        children: _wikilinkSpans(
          text,
          baseStyle: theme.textTheme.titleMedium?.copyWith(
            color: AfterimageTheme.accent,
            fontWeight: FontWeight.w800,
          ),
          linkStyle: theme.textTheme.titleMedium?.copyWith(
            color: AfterimageTheme.accent,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.underline,
            decorationColor: AfterimageTheme.accentStrong,
          ),
        ),
      ),
    );
  }
}

List<InlineSpan> _wikilinkSpans(
  String text, {
  TextStyle? baseStyle,
  TextStyle? linkStyle,
}) {
  final spans = <InlineSpan>[];
  final expression = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');
  var cursor = 0;
  for (final match in expression.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(
          text: text.substring(cursor, match.start), style: baseStyle));
    }
    spans.add(
      TextSpan(
        text: match.group(2) ?? match.group(1),
        style: linkStyle,
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
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
