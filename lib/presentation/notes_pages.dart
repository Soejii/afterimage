import 'dart:async';
import 'dart:convert';
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
  final Map<String, GlobalKey> _cardAnchors = {};
  final _flaggedController = ExpansibleController();
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
    _flaggedController.dispose();
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
                if (data.document.ledger case final ledger?
                    when ledger.totalDamage > 0)
                  _DamageLedgerPanel(
                      ledger: ledger,
                      player: data.document.player,
                      cards: data.document.cards,
                      onCard: _revealCard),
                if (data.document.trend case final trend?)
                  _TrendPanel(trend: trend),
                ..._buildGroups(context, data),
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

  List<Widget> _buildGroups(BuildContext context, NoteSequenceData data) {
    final document = data.document;
    final events = document.cards.where((card) => card.isEventCard).toList();
    Widget eventGroup(Iterable<SequenceCard> cards) => Column(
          key: const ValueKey('event-cards'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('HOW ELSE ${document.player?.toUpperCase() ?? 'YOU'} GOT HIT',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            for (final card in cards) _buildCard(context, data, card),
          ],
        );
    if (document.focus.isEmpty) {
      return [
        for (final card in document.cards.where((card) => !card.isEventCard))
          _buildCard(context, data, card),
        if (events.isNotEmpty) eventGroup(events),
      ];
    }
    final focus = <SequenceCard>[];
    for (final id in document.focus) {
      for (final card in document.cards) {
        if (card.id == id && !focus.contains(card)) {
          focus.add(card);
          break;
        }
      }
    }
    final others = document.cards.where((card) => !focus.contains(card));
    final flagged = others
        .where(
            (card) => !card.isEventCard && (card.flagged || card.isGuardCrush))
        .toList();
    return [
      Column(
        key: const ValueKey('focus-group'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('WORK ON THESE', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          for (var index = 0; index < focus.length; index++)
            _buildCard(context, data, focus[index], focusNumber: index + 1),
        ],
      ),
      ExpansionTile(
        key: const ValueKey('other-flagged'),
        controller: _flaggedController,
        title: Text('Other flagged situations (${flagged.length})'),
        children: [for (final card in flagged) _buildCard(context, data, card)],
      ),
      if (others.any((card) => card.isEventCard))
        eventGroup(others.where((card) => card.isEventCard)),
      for (final card in others.where(
          (card) => !card.isEventCard && !card.flagged && !card.isGuardCrush))
        _buildCard(context, data, card),
    ];
  }

  Future<void> _revealCard(SequenceCard card) async {
    setState(() => _expanded.add(card.id));
    final document = _data!.document;
    if (document.focus.isNotEmpty &&
        !document.focus.contains(card.id) &&
        !card.isEventCard &&
        (card.flagged || card.isGuardCrush)) {
      _flaggedController.expand();
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = _cardAnchors[card.id]?.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 300));
    }
  }

  Widget _buildCard(
    BuildContext context,
    NoteSequenceData data,
    SequenceCard card, {
    int? focusNumber,
  }) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final crush = card.isGuardCrush;
    final small = crush || card.isEventCard;
    final expanded = focusNumber != null ||
        (!card.isEventCard && card.flagged) ||
        crush ||
        _expanded.contains(card.id);
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
    return KeyedSubtree(
      key: _cardAnchors.putIfAbsent(card.id, () => GlobalKey()),
      child: Card(
        key: ValueKey('sequence-card-${card.id}'),
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: small
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
                      focusNumber == null
                          ? card.title
                          : '$focusNumber. ${card.title}',
                      style: (small
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                        color: small
                            ? AfterimageTheme.blockedText
                            : AfterimageTheme.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (card.isEventCard)
                    Flexible(
                      child: Text(
                        header,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    )
                  else
                    Text(
                      header,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              if (card.trendText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(card.trendText!,
                      key: ValueKey('trend-text-${card.id}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
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
              if (card.read case final read?)
                _SituationReadPanel(
                  read: read,
                  player: data.document.playerName ?? data.document.player,
                  opponent:
                      data.document.opponentName ?? data.document.opponent,
                ),
              if (card.reversalNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    card.reversalNote!,
                    key: ValueKey('reversal-note-${card.id}'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              if (card.answers.isNotEmpty) _AnswerScoreboard(card: card),
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
              if (card.isEventCard && card.count > card.sequences.length)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Showing the ${card.sequences.length} most damaging of ${card.count}.',
                    key: ValueKey('event-more-${card.id}'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
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
                SizedBox(height: small ? 6 : 10),
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
                if (sequence.read case final read?) ...[
                  if (read.kind.isNotEmpty &&
                      !const {
                        'punish',
                        "player's turn",
                        "opponent's turn",
                        'even',
                        'unclear',
                        'mixed',
                      }.contains(read.kind))
                    Text(
                      'Spot: ${read.kind}',
                      key: ValueKey('sequence-read-kind-${sequence.id}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  if (read.mistake != null || read.reason != null)
                    Text(
                      read.mistake == null
                          ? 'Read: ${read.reason}'
                          : 'Mistake: ${read.mistake}'
                              '${read.reason == null || read.reason!.isEmpty ? '' : ' · ${read.reason}'}',
                      key: ValueKey('sequence-read-${sequence.id}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  if (read.additionalDetails.isNotEmpty)
                    Text(
                      read.additionalDetails.join('\n'),
                      key: ValueKey('sequence-read-details-${sequence.id}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                ],
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

String _groupedNumber(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},');

String _times(int count) => count == 1 ? '1 time' : '$count times';

String _ledgerTime(double seconds) {
  final whole = seconds.clamp(0, double.maxFinite).floor();
  return '${(whole ~/ 60).toString().padLeft(2, '0')}:'
      '${(whole % 60).toString().padLeft(2, '0')}';
}

String _trendNumber(double value) => value.toStringAsFixed(1);

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.trend});

  final SequenceTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final earlier = trend.sets.length > 4 ? trend.sets.length - 4 : 0;
    final ledger = trend.ledger;
    final cards = trend.cards;
    return Card(
      key: const ValueKey('trend-panel'),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ACROSS SETS', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
                [
                  if (earlier > 0) '$earlier earlier',
                  for (final set in trend.sets.skip(earlier))
                    '${set.date} · ${set.replays} ${set.replays == 1 ? 'replay' : 'replays'}'
                        '${set.damagePerReplay == null ? '' : ' · ${_groupedNumber(set.damagePerReplay!.round())} HP per replay'}'
                        '${set.current ? ' · this set' : ''}',
                ].join('\n'),
                key: const ValueKey('trend-sets'),
                style: muted),
            if (ledger != null)
              Column(
                key: const ValueKey('trend-ledger'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Text(ledger.text, style: theme.textTheme.bodySmall),
                  _TrendDamageRow(label: 'Total', damage: ledger.total),
                  for (final category in ledger.categories)
                    _TrendDamageRow(
                        key: ValueKey('trend-category-${category.key}'),
                        label: category.label,
                        damage: category),
                ],
              )
            else if (trend.sets.any((set) => !set.current))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                    'No earlier set with HP data and at least 3 replays to compare damage with.',
                    style: muted),
              ),
            if (cards != null) ...[
              const SizedBox(height: 10),
              Text(cards.text, style: theme.textTheme.bodySmall),
              if (cards.gone.isNotEmpty)
                Column(
                  key: const ValueKey('trend-gone'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    Text('No longer seen:', style: theme.textTheme.bodySmall),
                    for (final card in cards.gone)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(card.title),
                            Text(card.text, style: muted)
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendDamageRow extends StatelessWidget {
  const _TrendDamageRow({super.key, required this.label, required this.damage});

  final String label;
  final TrendDamage damage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = damage.delta;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          Wrap(
            spacing: 12,
            children: [
              Text('Now ${_trendNumber(damage.now)}',
                  style: theme.textTheme.bodySmall),
              Text('Before ${_trendNumber(damage.before)}',
                  style: theme.textTheme.bodySmall),
              Text(
                  '${delta > 0 ? '+' : ''}${_trendNumber(delta == 0 ? 0 : delta)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: delta < 0
                        ? AfterimageTheme.readyText
                        : delta > 0
                            ? AfterimageTheme.failedText
                            : null,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

class _DamageLedgerPanel extends StatelessWidget {
  const _DamageLedgerPanel(
      {required this.ledger,
      required this.player,
      required this.cards,
      required this.onCard});

  final List<SequenceCard> cards;
  final ValueChanged<SequenceCard> onCard;

  final DamageLedger ledger;
  final String? player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = player ?? 'You';
    final largest = ledger.categories.fold<int>(
        0,
        (largest, category) =>
            category.damage > largest ? category.damage : largest);
    return Card(
      key: const ValueKey('damage-ledger'),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('WHERE THE DAMAGE CAME FROM',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text('$name lost ${_groupedNumber(ledger.totalDamage)} HP over '
                '${ledger.replays} ${ledger.replays == 1 ? 'replay' : 'replays'}. The cards below cover '
                '${_groupedNumber(ledger.coveredByCards)} '
                '(${(100 * ledger.coveredByCards / ledger.totalDamage).round()}%).'),
            for (final category in ledger.categories)
              ExpansionTile(
                key: ValueKey('ledger-category-${category.key}'),
                tilePadding: EdgeInsets.zero,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(category.label),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: largest > 0
                          ? (category.damage / largest).clamp(0, 1)
                          : 0,
                      color: AfterimageTheme.accent,
                      backgroundColor: AfterimageTheme.panelRaised,
                    ),
                    const SizedBox(height: 4),
                    Text(
                        '${_groupedNumber(category.damage)} damage '
                        '(${(100 * category.damage / ledger.totalDamage).round()}%)'
                        ' · ${category.events} events',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                children: [
                  Column(
                    key: ValueKey('ledger-starters-${category.key}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final starter in category.starters) ...[
                        Text('${starter.move} · ${_times(starter.events)} · '
                            '${_groupedNumber(starter.damage)} damage'
                            '${starter.counterHits > 0 ? ' · ${starter.counterHits} on counter hit' : ''}'),
                        for (final example in starter.examples)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 14, top: 2, bottom: 4),
                            child: Text(
                                'replay ${example.replay}, round ${example.round}'
                                '${example.videoTime == null ? '' : ' at ${_ledgerTime(example.videoTime!)}'}'
                                ' (${example.damage})',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ),
                      ],
                      for (final id in category.cards)
                        for (final card in cards.where((card) => card.id == id))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: ValueKey('ledger-card-${card.id}'),
                              onPressed: () => onCard(card),
                              child: Text(card.title),
                            ),
                          ),
                      if (category.key == 'pressing' &&
                          category.hisMoves.isNotEmpty)
                        Text(
                            '${player == null ? 'You were' : '$name was'} pressing: ${category.hisMoves.map((move) => '${move.move} x${move.events}').join(', ')}'),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AnswerScoreboard extends StatelessWidget {
  const _AnswerScoreboard({required this.card});

  final SequenceCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('answers-${card.id}'),
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final answer in card.answers)
            Builder(builder: (context) {
              final most = [
                answer.gotHit,
                answer.won,
                answer.pressure,
                answer.neutral
              ].reduce((a, b) => a > b ? a : b);
              TextSpan outcome(String text, int count, [Color? color]) =>
                  TextSpan(
                    text: text,
                    style: TextStyle(
                      color: count > 0 ? color : null,
                      fontWeight:
                          count > 0 && count == most ? FontWeight.w800 : null,
                    ),
                  );
              return Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${answer.text} · ${_times(answer.count)} · '),
                    outcome('hit ${answer.gotHit}', answer.gotHit,
                        AfterimageTheme.failedText),
                    const TextSpan(text: ' · '),
                    outcome('won ${answer.won}', answer.won,
                        AfterimageTheme.readyText),
                    const TextSpan(text: ' · '),
                    outcome('still under pressure ${answer.pressure}',
                        answer.pressure),
                    const TextSpan(text: ' · '),
                    outcome(
                        'back to neutral ${answer.neutral}', answer.neutral),
                    TextSpan(text: ' · ${answer.damage} damage'),
                  ]),
                  style: theme.textTheme.bodySmall);
            }),
        ],
      ),
    );
  }
}

class _SituationColumnGroup {
  const _SituationColumnGroup({
    required this.options,
    required this.label,
  });

  final List<SituationOption> options;
  final String label;

  bool get hasSeenOption => options.any(_situationOptionWasSeen);
}

bool _situationOptionWasSeen(SituationOption option) =>
    option.sources.any((source) => source.trim().toLowerCase() == 'seen');

List<_SituationColumnGroup> _situationColumnGroups(
  SituationMatrix matrix,
  String opponent,
) {
  final grouped = <String, List<SituationOption>>{};
  for (final option in matrix.opponentOptions) {
    final signature = jsonEncode([
      for (final row in matrix.rows)
        [
          row.cells[option.id]?.value,
          row.cells[option.id]?.winner,
          // Different "varies" distributions are different results (peer review P2).
          [
            for (final entry
                in (row.cells[option.id]?.values.entries.toList() ??
                    <MapEntry<String, int>>[])
                  ..sort((a, b) => a.key.compareTo(b.key)))
              [entry.key, entry.value],
          ],
        ],
    ]);
    (grouped[signature] ??= []).add(option);
  }
  return [
    for (final options in grouped.values)
      _SituationColumnGroup(
        options: options,
        label: _situationOptionGroupLabel(options, opponent),
      ),
  ];
}

String _situationOptionGroupLabel(
  List<SituationOption> options,
  String character,
) {
  final labels = [
    for (final option in options)
      _situationOptionLabel(option, option.id, character, markTension: false),
  ];
  if (labels.isEmpty) return '';
  if (labels.length == 1) return labels.first;
  final prefix = '$character ';
  final rest = labels.skip(1).map((label) =>
      label.startsWith(prefix) ? label.substring(prefix.length) : label);
  return '${labels.first}, ${rest.join(', ')}';
}

List<SituationMatrixCell> _situationCellsForGroup(
  SituationMatrixRow row,
  _SituationColumnGroup group,
) =>
    [
      for (final option in group.options)
        if (row.cells[option.id] case final cell?) cell,
    ];

int _situationGroupSeenCount(
  SituationMatrixRow row,
  _SituationColumnGroup group,
) =>
    group.options.where(_situationOptionWasSeen).fold(
        0, (total, option) => total + (row.cells[option.id]?.seen?.count ?? 0));

int _situationRowSeenCount(
  SituationMatrixRow row,
  List<_SituationColumnGroup> groups,
) =>
    groups.where((group) => group.hasSeenOption).fold(
        0, (total, group) => total + _situationGroupSeenCount(row, group));

class _SituationReadPanel extends StatelessWidget {
  const _SituationReadPanel({
    required this.read,
    required this.player,
    required this.opponent,
  });

  final SituationRead read;
  final String? player;
  final String opponent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final matrix = read.matrix;
    final playerOptions = matrix?.playerOptions ?? read.playerOptions;
    final opponentOptions = matrix?.opponentOptions ?? read.opponentOptions;
    final columnGroups = matrix == null
        ? const <_SituationColumnGroup>[]
        : _situationColumnGroups(matrix, opponent);
    final additionalDetails = _visibleSituationAdditionalDetails(read);
    final observedOpponentOptions = _hasOpponentTurnOrWakeup(read)
        ? _observedOpponentOptionText(read, opponentOptions, opponent)
        : null;
    final fuzzyCandidateText =
        _situationFuzzyCandidateText(read, player, opponent);
    final throwSummary = _situationThrowSummary(read);
    final throwDetails = _situationThrowDetails(read, player, opponent);
    final showSeenMeteredOnly = _hasOpponentTurnOrWakeup(read);
    const mistakeKinds = [
      'knowledge',
      'execution',
      'guess',
      'unc check',
      'unclear',
    ];
    bool needsUnknownTension(SituationOption option) =>
        option.availability == 'tension unknown' ||
        (option.tensionUnknown ?? 0) > 0;
    final meterOptions = [
      for (final option in playerOptions)
        if (needsUnknownTension(option) &&
            (!showSeenMeteredOnly || _situationOptionWasSeen(option)))
          _situationOptionLabel(option, option.id, player ?? 'Player',
              markTension: false),
      for (final option in opponentOptions)
        if (needsUnknownTension(option) &&
            (!showSeenMeteredOnly || _situationOptionWasSeen(option)))
          _situationOptionLabel(option, option.id, opponent,
              markTension: false),
    ];

    return Padding(
      key: const ValueKey('situation-read'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _situationReadHeadline(read, player, opponent),
            key: const ValueKey('read-headline'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: AfterimageTheme.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (read.scope != null && read.scope != read.kind)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Scope: ${read.scope}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ),
          if (matrix != null) ...[
            const SizedBox(height: 5),
            Column(
              key: const ValueKey('read-rows'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in _seenSituationRows(matrix, columnGroups))
                  _compactSituationMatrixRow(
                    entry.row,
                    entry.index,
                    entry.seenCount,
                    matrix,
                    player: player ?? 'Player',
                    opponent: opponent,
                    style: theme.textTheme.bodySmall,
                  ),
                if (matrix.neverWorksHere.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      'Never works here: ${_specialSituationOptions(matrix.neverWorksHere, matrix, player ?? 'Player')}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
          ],
          if (matrix == null &&
              (playerOptions.isNotEmpty || opponentOptions.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                [
                  if (playerOptions.isNotEmpty)
                    'Options for ${player ?? 'Player'}: ${playerOptions.map((option) => _situationOptionLabel(option, option.id, player ?? 'Player')).join(', ')}',
                  if (opponentOptions.isNotEmpty)
                    'Options for $opponent: ${opponentOptions.map((option) => _situationOptionLabel(option, option.id, opponent)).join(', ')}',
                ].join('\n'),
                key: const ValueKey('read-options'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (observedOpponentOptions != null &&
              observedOpponentOptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                observedOpponentOptions,
                key: const ValueKey('read-opponent-options'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (fuzzyCandidateText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                fuzzyCandidateText,
                key: const ValueKey('read-fuzzy-candidates'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (throwSummary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                throwSummary,
                key: const ValueKey('read-throw-summary'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (meterOptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Tension unknown for: ${meterOptions.join(', ')}',
                key: const ValueKey('read-metered'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (read.mistakes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Mistakes · ${[
                for (final kind in mistakeKinds)
                  '$kind ${read.mistakes[kind]?.count ?? 0}',
                for (final entry in read.mistakes.entries)
                  if (!mistakeKinds.contains(entry.key))
                    '${entry.key} ${entry.value.count}',
              ].join(' · ')}',
              key: const ValueKey('read-mistakes'),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if (matrix != null)
            ExpansionTile(
              key: const ValueKey('read-show-all'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                'Show every option (${matrix.rows.length} ${player ?? 'Player'}, '
                '${matrix.opponentOptions.length} $opponent)',
                style: theme.textTheme.bodySmall,
              ),
              children: [
                Column(
                  key: const ValueKey('read-full-rows'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in matrix.rows.asMap().entries)
                      Padding(
                        key: ValueKey('read-full-row-${entry.key}'),
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _situationMatrixRowText(
                            entry.value,
                            matrix,
                            columnGroups: columnGroups,
                            player: player ?? 'Player',
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (matrix.rows.isEmpty)
                      Text(
                        'No collapsed matchup rows.',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    if (read.points.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Spot details', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 3),
                      Column(
                        key: const ValueKey('read-full-spots'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0;
                              index < read.points.length;
                              index++)
                            Padding(
                              key: ValueKey('read-full-spot-$index'),
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _situationPointDetail(
                                  read.points[index],
                                  player: player ?? 'Player',
                                  opponent: opponent,
                                ),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (throwDetails.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      throwDetails,
                      key: const ValueKey('read-full-throws'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                if (matrix.dominantRows.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      'Wins against every listed option: ${_specialSituationOptions(matrix.dominantRows, matrix, player ?? 'Player')}',
                      key: const ValueKey('read-dominant-rows'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                if (matrix.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      matrix.note!,
                      key: const ValueKey('read-matrix-note'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                if (additionalDetails.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      additionalDetails.join('\n'),
                      key: const ValueKey('read-additional-details'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
              ],
            )
          else if (additionalDetails.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                additionalDetails.join('\n'),
                key: const ValueKey('read-additional-details'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

List<({int index, SituationMatrixRow row, int seenCount})> _seenSituationRows(
  SituationMatrix matrix,
  List<_SituationColumnGroup> columnGroups,
) {
  final playerOptions = {
    for (final option in matrix.playerOptions) option.id: option,
  };
  final rows = <({int index, SituationMatrixRow row, int seenCount})>[];
  bool playerOptionWasSeen(String id) {
    final option = playerOptions[id];
    return option != null && _situationOptionWasSeen(option);
  }

  for (final entry in matrix.rows.asMap().entries) {
    if (!entry.value.options.any(playerOptionWasSeen)) {
      continue;
    }
    rows.add((
      index: entry.key,
      row: entry.value,
      seenCount: _situationRowSeenCount(entry.value, columnGroups),
    ));
  }
  rows.sort((left, right) {
    final countOrder = right.seenCount.compareTo(left.seenCount);
    return countOrder != 0 ? countOrder : left.index.compareTo(right.index);
  });
  return rows;
}

Widget _compactSituationMatrixRow(
  SituationMatrixRow row,
  int index,
  int seenCount,
  SituationMatrix matrix, {
  required String player,
  required String opponent,
  required TextStyle? style,
}) {
  final playerOptions = {
    for (final option in matrix.playerOptions) option.id: option,
  };
  final choices = _situationOptionGroupLabel(
    [
      for (final id in row.options)
        if (playerOptions[id] case final option?) option,
    ],
    player,
  );
  final wins = <String, Map<int, List<SituationOption>>>{};
  final losesTo = <String, Map<int, List<SituationOption>>>{};
  final sameFrame = <int, List<SituationOption>>{};
  final unresolved = <String, Map<int, List<SituationOption>>>{};

  for (final option in matrix.opponentOptions.where(_situationOptionWasSeen)) {
    final cell = row.cells[option.id];
    if (cell == null) continue;
    final optionSeen = cell.seen?.count ?? 0;
    if (cell.winner == 'player') {
      ((wins[cell.value] ??= <int, List<SituationOption>>{})[optionSeen] ??=
              <SituationOption>[])
          .add(option);
    } else if (cell.value == 'same frame') {
      (sameFrame[optionSeen] ??= <SituationOption>[]).add(option);
    } else if (cell.winner == 'opponent' ||
        _isLosingSituationValue(cell.value)) {
      ((losesTo[cell.value] ??= <int, List<SituationOption>>{})[optionSeen] ??=
              <SituationOption>[])
          .add(option);
    } else {
      ((unresolved[cell.value] ??=
                  <int, List<SituationOption>>{})[optionSeen] ??=
              <SituationOption>[])
          .add(option);
    }
  }

  String outcomeGroups(Map<String, Map<int, List<SituationOption>>> values) =>
      values.entries.map((entry) {
        final options = [
          for (final optionGroup in entry.value.entries)
            '${_situationOptionGroupLabel(optionGroup.value, opponent)}'
                '${optionGroup.key > 0 ? ' (seen ${optionGroup.key})' : ''}',
        ];
        return '${entry.key} vs ${options.join(', ')}';
      }).join('; ');

  String sameFrameGroups() => sameFrame.entries
      .map((entry) => '${_situationOptionGroupLabel(entry.value, opponent)}'
          '${entry.key > 0 ? ' (seen ${entry.key})' : ''}')
      .join('; ');

  return Padding(
    key: ValueKey('read-default-row-$index'),
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            '${choices.isEmpty ? 'Unknown option' : choices} · seen $seenCount',
            style: style),
        if (wins.isNotEmpty)
          Text('Wins vs: ${outcomeGroups(wins)}', style: style),
        if (losesTo.isNotEmpty)
          Text('Loses to: ${outcomeGroups(losesTo)}', style: style),
        if (sameFrame.isNotEmpty)
          Text('Same frame: ${sameFrameGroups()}', style: style),
        if (unresolved.isNotEmpty)
          Text('Unresolved: ${outcomeGroups(unresolved)}', style: style),
      ],
    ),
  );
}

const _situationReadKinds = <String>{
  'punish',
  "player's turn",
  "opponent's turn",
  'even',
  'mixed',
  'unclear',
};

List<String> _visibleSituationAdditionalDetails(SituationRead read) {
  if (!_situationReadKinds.contains(read.kind)) return read.additionalDetails;
  const renderedFields = {
    'active_frame',
    'active_frames',
    'guards',
    'fuzzy_candidates',
    'corner',
    'throw_range',
    'throw_range_bracket',
    'bracket',
    'fuzzy_note',
  };
  return [
    for (final detail in read.additionalDetails)
      if (!renderedFields.contains(_situationDetailKey(detail))) detail,
  ];
}

String _situationDetailKey(String detail) {
  final separator = detail.indexOf(':');
  final path = separator < 0 ? detail : detail.substring(0, separator);
  return path.split('.').last;
}

bool _hasOpponentTurnOrWakeup(SituationRead read) =>
    read.kind == "opponent's turn" ||
    read.points.any((point) =>
        point.kind == "opponent's turn" || point.raw['clock'] == 'wakeup');

String _observedOpponentOptionText(
  SituationRead read,
  List<SituationOption> options,
  String opponent,
) {
  final reactable = _reactableSituationOptions(read);
  final seen = options.where(_situationOptionWasSeen);
  return seen.map((option) {
    final label = _situationOptionLabel(
      option,
      option.id,
      opponent,
      markTension: false,
    );
    final guard = option.guard?.trim();
    final guardText = guard == null || guard.isEmpty ? 'guard unknown' : guard;
    final timings = _situationActiveFrameHistogram(option.activeFrames);
    final timingText = timings.isEmpty
        ? 'active frame unmeasured'
        : 'active at ${timings.map((timing) => '${timing.frame} (seen ${timing.count})').join(', ')}';
    return '$label: $guardText, $timingText'
        '${reactable.contains(option.id) ? ' (unc check)' : ''}';
  }).join('\n');
}

Set<String> _reactableSituationOptions(SituationRead read) {
  final matrix = _situationMap(read.raw['matrix']);
  final result = <String>{};
  for (final route in _situationMaps(matrix?['routes'])) {
    for (final timing in _situationMaps(route['timings'])) {
      if (timing['reactable'] != true) continue;
      for (final key in ['base_option', 'option']) {
        final option = timing[key];
        if (option is String && option.isNotEmpty) result.add(option);
      }
    }
  }
  return result;
}

List<({int frame, int count})> _situationActiveFrameHistogram(Object? value) {
  if (value is num && value.isFinite) {
    return [(frame: value.toInt(), count: 1)];
  }
  return [
    for (final item in value is List ? value : const [])
      if (_situationMap(item) case final entry?)
        if (_situationInteger(entry['frame']) case final frame?)
          (
            frame: frame,
            count: _situationInteger(entry['count']) ?? 1,
          ),
  ];
}

String _situationFuzzyCandidateText(
  SituationRead read,
  String? player,
  String opponent,
) {
  final matrix = _situationMap(read.raw['matrix']);
  final candidates = _situationMaps(
    matrix?['fuzzy_candidates'] ?? read.raw['fuzzy_candidates'],
  );
  return candidates.map((candidate) {
    final options = [
      for (final option in _situationMaps(candidate['options']))
        _situationFuzzyOptionText(option, player, opponent),
    ];
    final context = [
      if (_situationString(candidate['spacing']) case final spacing?) spacing,
      if (_situationCornerLabel(candidate['corner'], player, opponent)
          case final corner?)
        corner,
    ];
    final label = _situationString(candidate['label']) ?? 'Fuzzy pair';
    return '$label: ${options.join(' / ')}'
        '${context.isEmpty ? '' : ' · ${context.join(' · ')}'}';
  }).join('\n');
}

String _situationFuzzyOptionText(
  Map<String, Object?> option,
  String? player,
  String opponent,
) {
  final rawLabel = _situationString(option['option']) ?? 'Unknown option';
  final character = rawLabel.startsWith('${opponent.trim()} ')
      ? opponent
      : player ?? 'Player';
  final label = _situationNamedOption(rawLabel, character);
  final guard = _situationString(option['guard']) ?? 'guard unknown';
  final frame = _situationInteger(option['frame']);
  return '$label ($guard, ${frame == null ? 'frame unknown' : 'active at $frame'})';
}

String _situationNamedOption(String rawLabel, String character) {
  final label = rawLabel.trim();
  if (label.startsWith('${character.trim()} ')) return label;
  return '${character.trim()} $label';
}

String _situationThrowSummary(
  SituationRead read,
) {
  if (read.points.isEmpty) return '';
  final statusesBySpot = [
    for (final point in read.points) _situationThrowStatuses(point.raw),
  ];
  final inRange =
      statusesBySpot.where((statuses) => statuses.contains('in range')).length;
  if (inRange > 0) {
    return 'Throw in range at $inRange of ${read.points.length} spots';
  }
  final outOfRange = statusesBySpot
      .where((statuses) => statuses.contains('out of range'))
      .length;
  if (outOfRange > 0) {
    return 'Throw out of range at $outOfRange of ${read.points.length} spots';
  }
  final needsReachCheck = statusesBySpot
      .where((statuses) => statuses.contains('check reach'))
      .length;
  if (needsReachCheck > 0) {
    return 'Throw reach needs checking at $needsReachCheck of '
        '${read.points.length} spots';
  }
  final observed =
      statusesBySpot.where((statuses) => statuses.isNotEmpty).length;
  if (observed == 0) return '';
  return 'Throw reach unresolved at $observed of ${read.points.length} spots';
}

List<String> _situationThrowStatuses(Map<String, Object?> raw) {
  final result = <String>[];
  final throws = _situationMap(raw['throw']);
  for (final side in ['player', 'opponent']) {
    final value = _situationMap(throws?[side]);
    if (_situationString(value?['status']) case final status?) {
      result.add(status);
    }
  }
  final throwOptions = _situationMap(raw['throw_options']);
  for (final side in ['player', 'opponent']) {
    final sideOptions = _situationMap(throwOptions?[side]);
    for (final option in sideOptions?.values ?? const <Object?>[]) {
      final value = _situationMap(option);
      if (_situationString(value?['status']) case final status?) {
        result.add(status);
      }
    }
  }
  return result;
}

String _situationThrowDetails(
  SituationRead read,
  String? player,
  String opponent,
) {
  final groupedSpots = <String, int>{};
  for (final point in read.points) {
    final statuses = _situationThrowStatusLines(
      point.raw,
      player: player ?? 'Player',
      opponent: opponent,
    );
    if (statuses.isEmpty) continue;
    final context = <String>[
      if (read.kind == 'mixed')
        _situationShortKind(point.kind, player ?? 'Player', opponent),
      if (point.spacing case final spacing? when spacing.isNotEmpty) spacing,
      if (_situationCornerLabel(point.corner, player, opponent)
          case final corner?)
        corner,
    ];
    final label = '${context.join(' / ')}: '
        '${_compactSituationThrowStatuses(statuses, player ?? 'Player', opponent)}';
    groupedSpots.update(label, (count) => count + 1, ifAbsent: () => 1);
  }
  if (groupedSpots.isEmpty) return '';
  return 'Throws: ${groupedSpots.entries.map((entry) => '${entry.key}'
      '${entry.value > 1 ? ' ×${entry.value}' : ''}').join('; ')}';
}

String _compactSituationThrowStatuses(
  List<String> statuses,
  String player,
  String opponent,
) {
  if (statuses.length == 2) {
    final playerPrefix = '$player throw ';
    final opponentPrefix = '$opponent throw ';
    final playerStatuses = statuses
        .where((status) => status.startsWith(playerPrefix))
        .map((status) => status.substring(playerPrefix.length))
        .toList();
    final opponentStatuses = statuses
        .where((status) => status.startsWith(opponentPrefix))
        .map((status) => status.substring(opponentPrefix.length))
        .toList();
    final playerStatus = playerStatuses.isEmpty ? null : playerStatuses.first;
    final opponentStatus =
        opponentStatuses.isEmpty ? null : opponentStatuses.first;
    if (playerStatus != null && playerStatus == opponentStatus) {
      return '$player and $opponent throw $playerStatus';
    }
  }
  return statuses
      .map((status) => status
          .replaceFirst('$player throw ', '$player ')
          .replaceFirst('$opponent throw ', '$opponent '))
      .join('; ');
}

String _situationShortKind(String kind, String player, String opponent) =>
    switch (kind) {
      "player's turn" => '$player turn',
      "opponent's turn" => '$opponent turn',
      'mixed' => 'Mixed',
      _ => _situationKindHeadline(kind, player, opponent),
    };

List<String> _situationThrowStatusLines(
  Map<String, Object?> raw, {
  required String player,
  required String opponent,
}) {
  final result = <String>[];
  final throws = _situationMap(raw['throw']);
  for (final side in ['player', 'opponent']) {
    final value = _situationMap(throws?[side]);
    final status = _situationString(value?['status']);
    if (status != null) {
      result.add('${side == 'player' ? player : opponent} throw $status');
    }
  }
  final throwOptions = _situationMap(raw['throw_options']);
  for (final side in ['player', 'opponent']) {
    final sideOptions = _situationMap(throwOptions?[side]);
    for (final entry
        in sideOptions?.entries ?? const <MapEntry<String, Object?>>[]) {
      final value = _situationMap(entry.value);
      final status = _situationString(value?['status']);
      if (status != null) {
        final character = side == 'player' ? player : opponent;
        result.add(
          '${_situationNamedOption(entry.key, character)} $status',
        );
      }
    }
  }
  return result;
}

List<String> _situationPointContext(
  SituationRead point, {
  required String player,
  required String opponent,
}) {
  final context = <String>[];
  final clock = _situationString(point.raw['clock']);
  if (clock == 'wakeup') context.add('Wakeup');
  final kind = _situationKindHeadline(point.kind, player, opponent);
  if (kind.isNotEmpty && kind != 'Mixed situation') context.add(kind);
  if (point.spacing case final spacing? when spacing.isNotEmpty) {
    context.add(spacing);
  }
  if (_situationCornerLabel(point.corner, player, opponent)
      case final corner?) {
    context.add(corner);
  }
  return context;
}

String _situationPointDetail(
  SituationRead point, {
  required String player,
  required String opponent,
}) {
  final id = _situationString(point.raw['sequence_id']);
  final parts = <String>[
    if (id != null && id.isNotEmpty) id,
    ..._situationPointContext(point, player: player, opponent: opponent),
    ..._situationThrowEvidenceLines(
      point.raw,
      player: player,
      opponent: opponent,
    ),
  ];
  return parts.isEmpty ? 'Spot detail unavailable.' : parts.join(' · ');
}

List<String> _situationThrowEvidenceLines(
  Map<String, Object?> raw, {
  required String player,
  required String opponent,
}) {
  final result = <String>[];
  final throws = _situationMap(raw['throw']);
  for (final side in ['player', 'opponent']) {
    final value = _situationMap(throws?[side]);
    if (value != null) {
      result.add(_situationThrowEvidence(
        side == 'player' ? player : opponent,
        'throw',
        value,
      ));
    }
  }
  final throwOptions = _situationMap(raw['throw_options']);
  for (final side in ['player', 'opponent']) {
    final sideOptions = _situationMap(throwOptions?[side]);
    for (final entry
        in sideOptions?.entries ?? const <MapEntry<String, Object?>>[]) {
      final value = _situationMap(entry.value);
      if (value != null) {
        result.add(_situationThrowEvidence(
          side == 'player' ? player : opponent,
          entry.key,
          value,
        ));
      }
    }
  }
  return result;
}

String _situationThrowEvidence(
  String character,
  String option,
  Map<String, Object?> value,
) {
  final status = _situationString(value['status']) ?? 'status unknown';
  final bracket = _situationMap(value['bracket']);
  final evidence = <String>[];
  if (_situationInteger(bracket?['farthest_connect']) case final farthest?) {
    evidence.add('farthest connection distance ${_groupedNumber(farthest)}');
  }
  if (_situationInteger(bracket?['nearest_whiff']) case final nearest?) {
    evidence.add('nearest whiff distance ${_groupedNumber(nearest)}');
  }
  final connected = _situationInteger(bracket?['connected']);
  final whiffed = _situationInteger(bracket?['whiffed']);
  final unknown = _situationInteger(bracket?['unknown']);
  if (connected != null) evidence.add('$connected connected');
  if (whiffed != null) evidence.add('$whiffed whiffed');
  if (unknown != null) evidence.add('$unknown unknown');
  return '$character $option $status'
      '${evidence.isEmpty ? '' : ': ${evidence.join('; ')}'}';
}

Map<String, Object?>? _situationMap(Object? value) {
  if (value is! Map) return null;
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

List<Map<String, Object?>> _situationMaps(Object? value) => value is List
    ? [
        for (final item in value)
          if (_situationMap(item) case final map?) map,
      ]
    : const [];

String? _situationString(Object? value) => value is String ? value : null;

int? _situationInteger(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

String? _situationCornerLabel(
  Object? rawCorner,
  String? player,
  String opponent,
) {
  if (rawCorner == null) return null;
  final corner = rawCorner.toString().trim();
  if (corner.isEmpty) return null;
  return switch (corner) {
    'player cornered' => '${player ?? 'Player'} cornered',
    'opponent cornered' => '$opponent cornered',
    'none' => 'no corner',
    _ => corner,
  };
}

String _situationReadHeadline(
  SituationRead read,
  String? player,
  String opponent,
) {
  final playerName = player ?? 'Player';
  final isWakeup = read.points.isNotEmpty &&
      read.points.every((point) => point.raw['clock'] == 'wakeup');
  final label = _situationKindHeadline(read.kind, playerName, opponent);
  if (read.kind.isNotEmpty && !_situationReadKinds.contains(read.kind)) {
    return read.kind;
  }
  final corners = <String>{
    if (_situationCornerLabel(read.corner, playerName, opponent)
        case final corner?)
      corner,
    for (final point in read.points)
      if (_situationCornerLabel(point.corner, playerName, opponent)
          case final corner?)
        corner,
  };
  final cornerSuffix = corners.isEmpty ? '' : ' · ${corners.join(', ')}';
  final wakeupPrefix = isWakeup ? 'Wakeup · ' : '';
  if (read.kind == 'mixed' && read.points.isNotEmpty) {
    final kinds = <String, int>{};
    for (final point in read.points) {
      final kind = _situationKindHeadline(point.kind, playerName, opponent);
      kinds.update(kind, (count) => count + 1, ifAbsent: () => 1);
    }
    final spotKinds = kinds.entries
        .map((entry) => '${entry.key} ×${entry.value}')
        .join(' · ');
    return '$wakeupPrefix$label: $spotKinds$cornerSuffix';
  }
  if (read.adv != null && read.kind != 'even') {
    final adv = read.adv!;
    return '$wakeupPrefix$label (${adv > 0 ? '+' : ''}$adv)$cornerSuffix';
  }
  if (read.kind.isEmpty) return '${wakeupPrefix}Situation read$cornerSuffix';
  if (read.advCounts.isNotEmpty) {
    final counts = read.advCounts.map((item) =>
        '${item.adv == null ? 'unclear' : '${item.adv! > 0 ? '+' : ''}${item.adv}'} ×${item.count}');
    return '$wakeupPrefix$label (adv varies: ${counts.join(', ')})$cornerSuffix';
  }
  return '$wakeupPrefix$label$cornerSuffix';
}

String _situationKindHeadline(
  String kind,
  String player,
  String opponent,
) =>
    switch (kind) {
      "player's turn" => "$player's turn",
      "opponent's turn" => "$opponent's turn",
      'punish' => 'Punish',
      'even' => 'Even',
      'mixed' => 'Mixed situation',
      'unclear' => 'Unclear',
      _ => kind,
    };

String _situationMatrixRowText(
  SituationMatrixRow row,
  SituationMatrix matrix, {
  required List<_SituationColumnGroup> columnGroups,
  required String player,
}) {
  final playerOptions = {
    for (final option in matrix.playerOptions) option.id: option,
  };
  final choices = _situationOptionGroupLabel([
    for (final id in row.options)
      if (playerOptions[id] case final option?) option,
  ], player);
  final activeFirst = <String>[];
  final losesTo = <String>[];
  final unresolved = <String>[];
  final otherWins = <String>[];
  final sameFrame = <String>[];

  for (final group in columnGroups) {
    final cells = _situationCellsForGroup(row, group);
    if (cells.isEmpty) continue;
    final cell = cells.first;
    final seenCount = cells.fold<int>(
      0,
      (total, current) => total + (current.seen?.count ?? 0),
    );
    final values = <String, int>{};
    if (cell.value == 'varies') {
      for (final current in cells) {
        for (final entry in current.values.entries) {
          values.update(entry.key, (count) => count + entry.value,
              ifAbsent: () => entry.value);
        }
      }
    }
    final outcomes = cell.value == 'varies' && values.isNotEmpty
        ? values.entries
        : [MapEntry(cell.value, 0)];
    for (final outcome in outcomes) {
      final value = outcome.key;
      final countText = cell.value == 'varies' && outcome.value > 0
          ? ', ${outcome.value} spots'
          : '';
      final seenText = seenCount > 0 ? ', seen $seenCount' : '';
      final detail = ' ($value$countText$seenText)';
      if (value == 'same frame') {
        sameFrame.add('${group.label}$detail');
      } else if (value == 'active first' && cell.winner != 'opponent') {
        activeFirst.add('${group.label}$detail');
      } else if (cell.winner == 'opponent' ||
          (cell.winner != 'player' && _isLosingSituationValue(value))) {
        losesTo.add('${group.label}$detail');
      } else if (_isUnresolvedSituationValue(value) || cell.winner == null) {
        unresolved.add('${group.label}$detail');
      } else if (cell.winner == 'player') {
        otherWins.add('${group.label}$detail');
      } else {
        unresolved.add('${group.label}$detail');
      }
    }
  }

  final outcomes = <String>[
    if (activeFirst.isNotEmpty)
      'Active first against ${activeFirst.join(', ')}',
    if (losesTo.isNotEmpty) 'Loses to ${losesTo.join(', ')}',
    if (unresolved.isNotEmpty) 'Unresolved: ${unresolved.join(', ')}',
    if (sameFrame.isNotEmpty) 'Same frame with ${sameFrame.join(', ')}',
    if (otherWins.isNotEmpty) 'Beats by rule: ${otherWins.join(', ')}',
  ];
  return '${choices.isEmpty ? 'Unknown option' : choices} — '
      '${outcomes.isEmpty ? 'No matchup cells' : outcomes.join('; ')}';
}

bool _isUnresolvedSituationValue(String value) =>
    value == 'check reach' ||
    value == 'check anti-air' ||
    value == 'seen only' ||
    value == 'unavailable' ||
    value == 'varies';

bool _isLosingSituationValue(String value) =>
    value == 'active after' ||
    value == 'throw whiffs' ||
    value == 'gives up turn';

String _situationOptionLabel(
  SituationOption? option,
  String id,
  String character, {
  bool markTension = true,
}) {
  var label = option?.label.trim() ?? '';
  if (label.isEmpty) {
    label =
        id.startsWith('$character ') ? id.substring(character.length + 1) : id;
  }
  if (character.isNotEmpty && !label.startsWith('$character ')) {
    label = '$character $label';
  }
  if (markTension &&
      (option?.availability == 'tension unknown' ||
          (option?.tensionUnknown ?? 0) > 0)) {
    label = '$label (tension unknown)';
  }
  return label;
}

String _specialSituationOptions(
  List<Object?> values,
  SituationMatrix matrix,
  String player,
) {
  final options = {
    for (final option in matrix.playerOptions) option.id: option
  };
  final labels = <String>[];
  for (final value in values) {
    if (value is String) {
      labels.add(_situationOptionLabel(options[value], value, player));
    } else if (value is Map) {
      final json = <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      final rowOptions = json['options'];
      if (rowOptions is List) {
        labels.addAll(rowOptions.map((item) {
          final id = item?.toString() ?? '';
          return _situationOptionLabel(options[id], id, player);
        }));
      } else {
        final id = (json['option'] ?? json['id'] ?? json['label'])?.toString();
        if (id != null) {
          labels.add(_situationOptionLabel(options[id], id, player));
        }
      }
    } else if (value != null) {
      labels.add(value.toString());
    }
  }
  return labels.join(', ');
}
