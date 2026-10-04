import 'dart:convert';

/// One `###` card from a finder section.
class NoteCard {
  const NoteCard(this.text, {this.id});

  final String text;
  final String? id;

  String get heading {
    final line = text.replaceAll('\r\n', '\n').split('\n').first;
    return line.startsWith('### ') ? line : '### $line';
  }

  String get body {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    return lines.length <= 1 ? '' : lines.skip(1).join('\n');
  }

  NoteCard copyWith({String? text}) => NoteCard(text ?? this.text, id: id);
}

/// The editable structure of one `section.md` file.
class NoteSectionDocument {
  const NoteSectionDocument({
    required this.preamble,
    required this.cards,
  });

  final String preamble;
  final List<NoteCard> cards;

  String toMarkdown() {
    final parts = <String>[];
    final cleanPreamble = _trimTrailingNewlines(preamble);
    if (cleanPreamble.isNotEmpty) {
      parts.add(cleanPreamble);
    }
    for (final card in cards) {
      final text = _trimTrailingNewlines(card.text);
      if (text.isNotEmpty) {
        parts.add(text);
      }
    }
    if (parts.isEmpty) {
      return '\n';
    }
    return '${parts.join('\n\n')}\n';
  }

  NoteSectionDocument replaceCard(int index, NoteCard card) {
    final next = List<NoteCard>.of(cards);
    next[index] = card;
    return NoteSectionDocument(preamble: preamble, cards: next);
  }

  NoteSectionDocument removeCard(int index) {
    final next = List<NoteCard>.of(cards)..removeAt(index);
    return NoteSectionDocument(preamble: preamble, cards: next);
  }

  NoteSectionDocument insertCard(int index, NoteCard card) {
    final next = List<NoteCard>.of(cards);
    final position = index.clamp(0, next.length).toInt();
    next.insert(position, card);
    return NoteSectionDocument(preamble: preamble, cards: next);
  }
}

/// Splits a finder section while retaining all text before its first card.
NoteSectionDocument splitNoteSection(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  while (lines.length > 1 && lines.last.isEmpty) {
    lines.removeLast();
  }

  final starts = <int>[];
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].startsWith('### ')) {
      starts.add(index);
    }
  }
  if (starts.isEmpty) {
    return NoteSectionDocument(
      preamble: lines.join('\n'),
      cards: const <NoteCard>[],
    );
  }

  final preamble = _trimTrailingNewlines(lines.take(starts.first).join('\n'));
  final cards = <NoteCard>[];
  for (var index = 0; index < starts.length; index++) {
    final start = starts[index];
    final end = index + 1 < starts.length ? starts[index + 1] : lines.length;
    cards
        .add(NoteCard(lines.sublist(start, end).join('\n'), id: 'card-$start'));
  }
  return NoteSectionDocument(preamble: preamble, cards: cards);
}

String joinNoteSection(NoteSectionDocument document) => document.toMarkdown();

String _trimTrailingNewlines(String value) =>
    value.replaceFirst(RegExp(r'\n+$'), '');

/// Metadata written by the finder beside a section.
class NoteMetadata {
  const NoteMetadata({
    required this.opponent,
    required this.player,
    required this.batchLabel,
    required this.batchFolder,
    required this.notePath,
    required this.createdAt,
    required this.previous,
    required this.status,
    required this.appliedAt,
  });

  factory NoteMetadata.fromJson(Map<String, Object?> json) {
    final created = DateTime.tryParse(json['created_at']?.toString() ?? '');
    final applied = DateTime.tryParse(json['applied_at']?.toString() ?? '');
    return NoteMetadata(
      opponent: json['opponent']?.toString() ?? '',
      player: json['player']?.toString() ?? '',
      batchLabel: json['batch_label']?.toString() ?? '',
      batchFolder: json['batch_folder']?.toString() ?? '',
      notePath: json['note_path']?.toString() ?? '',
      createdAt: created,
      previous: json['previous'] is String ? json['previous'] as String : null,
      status: json['status']?.toString() == 'applied'
          ? NoteMetadataStatus.applied
          : NoteMetadataStatus.draft,
      appliedAt: applied,
    );
  }

  final String opponent;
  final String player;
  final String batchLabel;
  final String batchFolder;
  final String notePath;
  final DateTime? createdAt;
  final String? previous;
  final NoteMetadataStatus status;
  final DateTime? appliedAt;

  bool get isApplied => status == NoteMetadataStatus.applied;
}

enum NoteMetadataStatus { draft, applied }

/// An entry in the notes list. Legacy entries intentionally have no metadata.
class NotePreview {
  const NotePreview({
    required this.batchLabel,
    required this.opponent,
    required this.directoryPath,
    required this.sectionPath,
    required this.metadata,
    required this.cardCount,
    required this.modifiedAt,
  });

  final String batchLabel;
  final String opponent;
  final String directoryPath;
  final String sectionPath;
  final NoteMetadata? metadata;
  final int cardCount;
  final DateTime? modifiedAt;

  bool get isLegacy => metadata == null;
  bool get isApplied => metadata?.isApplied ?? false;
  DateTime? get createdAt => metadata?.createdAt ?? modifiedAt;
}

class NoteSectionData {
  const NoteSectionData({
    required this.preview,
    required this.document,
    required this.warnings,
    required this.clipIndex,
  });

  final NotePreview preview;
  final NoteSectionDocument document;
  final List<String> warnings;
  final ClipIndex? clipIndex;
}

class ClipIndex {
  const ClipIndex({
    required this.video,
    required this.situations,
    required this.errors,
  });

  factory ClipIndex.fromJson(Map<String, Object?> json) {
    final rawSituations = json['situations'];
    final situations = <ClipSituation>[];
    if (rawSituations is List) {
      for (final value in rawSituations) {
        if (value is Map) {
          situations.add(
            ClipSituation.fromJson(Map<String, Object?>.from(value)),
          );
        }
      }
    }
    final rawErrors = json['errors'];
    return ClipIndex(
      video: json['video']?.toString(),
      situations: situations,
      errors: rawErrors is List
          ? rawErrors.map((value) => value.toString()).toList(growable: false)
          : const <String>[],
    );
  }

  final String? video;
  final List<ClipSituation> situations;
  final List<String> errors;
}

class ClipSituation {
  const ClipSituation({
    required this.heading,
    required this.entry,
    required this.posture,
    required this.herMoveLink,
    required this.clips,
  });

  factory ClipSituation.fromJson(Map<String, Object?> json) {
    final rawClips = json['clips'];
    final clips = <NoteClip>[];
    if (rawClips is List) {
      for (final value in rawClips) {
        if (value is Map) {
          clips.add(NoteClip.fromJson(Map<String, Object?>.from(value)));
        }
      }
    }
    return ClipSituation(
      heading: json['heading'] is String ? json['heading'] as String : null,
      entry: json['entry']?.toString() ?? '',
      posture: json['posture']?.toString() ?? '',
      herMoveLink: json['her_move_link']?.toString(),
      clips: clips,
    );
  }

  final String? heading;
  final String entry;
  final String posture;
  final String? herMoveLink;
  final List<NoteClip> clips;
}

class NoteClip {
  const NoteClip({
    required this.file,
    required this.poster,
    required this.replay,
    required this.videoTime,
    required this.videoTimeMs,
    required this.startMs,
    required this.endMs,
    required this.herNext,
    required this.answer,
    required this.outcome,
    required this.counterHit,
    this.option,
  });

  factory NoteClip.fromJson(Map<String, Object?> json) {
    int? integer(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value');
    return NoteClip(
      file: json['file']?.toString() ?? '',
      poster: json['poster']?.toString(),
      replay: integer(json['replay']),
      videoTime: json['video_time']?.toString(),
      videoTimeMs: integer(json['video_time_ms']),
      startMs: integer(json['start_ms']),
      endMs: integer(json['end_ms']),
      herNext: json['her_next']?.toString(),
      answer: json['answer']?.toString(),
      outcome: json['outcome']?.toString() ?? '',
      counterHit: json['counter_hit'] == true,
      option: json['option']?.toString(),
    );
  }

  final String file;
  final String? poster;
  final int? replay;
  final String? videoTime;
  final int? videoTimeMs;
  final int? startMs;
  final int? endMs;
  final String? herNext;
  final String? answer;
  final String outcome;
  final bool counterHit;

  /// The table row this clip belongs to: her option, or `no attack`.
  final String? option;

  String caption() {
    final parts = <String>[];
    if (videoTime != null && videoTime!.isNotEmpty) parts.add(videoTime!);
    if (answer != null && answer!.isNotEmpty) parts.add(answer!);
    if (outcome.isNotEmpty) {
      parts.add('$outcome${counterHit ? ' (CH)' : ''}');
    }
    if (herNext != null && herNext!.isNotEmpty) parts.add('vs $herNext');
    return parts.join(' · ');
  }
}

/// Returns the clips attached to [card] under the contract's exact/fallback rules.
List<NoteClip> matchClipsForCard(NoteCard card, ClipIndex? index) {
  if (index == null) return const <NoteClip>[];
  ClipSituation? exact;
  for (final situation in index.situations) {
    if (situation.heading == card.heading) {
      exact = situation;
      break;
    }
  }
  final situation = exact ?? _fallbackSituation(card, index.situations);
  if (situation == null) return const <NoteClip>[];

  final indexed = situation.clips.asMap().entries.toList();
  indexed.sort((left, right) {
    final leftHit = left.value.outcome.toLowerCase() == 'hit';
    final rightHit = right.value.outcome.toLowerCase() == 'hit';
    if (leftHit != rightHit) return leftHit ? -1 : 1;
    return left.key.compareTo(right.key);
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}

/// Name of the row for clips she answered with nothing.
const noAttackOption = 'no attack';

/// The clips cut for one table row (her option), in index order.
List<NoteClip> clipsForOption(List<NoteClip> clips, String option) => [
      for (final clip in clips)
        if ((clip.option ?? clip.herNext ?? noAttackOption) == option) clip,
    ];

/// One piece of a card body: a text line or a markdown table.
sealed class NoteBodyBlock {
  const NoteBodyBlock();
}

/// A text line; `habit: ...` style lines expose their [label].
class NoteTextLine extends NoteBodyBlock {
  const NoteTextLine(this.text);

  final String text;

  static final _labelled = RegExp(r'^(habit|rps|lab|seen|holding):\s?(.*)$');

  String? get label => _labelled.firstMatch(text)?.group(1);

  String get rest => _labelled.firstMatch(text)?.group(2) ?? text;
}

class NoteTable extends NoteBodyBlock {
  const NoteTable({required this.header, required this.rows});

  final List<String> header;
  final List<NoteTableRow> rows;
}

class NoteTableRow {
  const NoteTableRow(this.cells);

  final List<String> cells;

  /// Her option: the first cell's wikilink target, or its plain text.
  String get option {
    final first = cells.isEmpty ? '' : cells.first;
    final link = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]').firstMatch(first);
    return (link?.group(1) ?? first).trim();
  }
}

/// Splits a card body into lines and tables. Consecutive `|` lines form a table;
/// its first line is the header and `| --- |` separator lines are skipped.
List<NoteBodyBlock> parseNoteBody(String body) {
  final blocks = <NoteBodyBlock>[];
  List<List<String>>? table;

  void closeTable() {
    final rows = table;
    if (rows == null) return;
    blocks.add(NoteTable(
      header: rows.first,
      rows: [for (final row in rows.skip(1)) NoteTableRow(row)],
    ));
    table = null;
  }

  for (final raw in body.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trimLeft().startsWith('|')) {
      final cells = _tableCells(line);
      if (cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell))) {
        continue;
      }
      (table ??= <List<String>>[]).add(cells);
      continue;
    }
    closeTable();
    blocks.add(NoteTextLine(line));
  }
  closeTable();
  while (blocks.isNotEmpty &&
      blocks.last is NoteTextLine &&
      (blocks.last as NoteTextLine).text.isEmpty) {
    blocks.removeLast();
  }
  return blocks;
}

List<String> _tableCells(String line) {
  var text = line.trim();
  if (text.startsWith('|')) text = text.substring(1);
  if (text.endsWith('|')) text = text.substring(0, text.length - 1);
  // Split on `|`, but not inside a `[[target|alias]]` wikilink.
  final cells = <String>[];
  final cell = StringBuffer();
  var depth = 0;
  for (var index = 0; index < text.length; index++) {
    if (text.startsWith('[[', index)) {
      depth++;
    } else if (text.startsWith(']]', index) && depth > 0) {
      depth--;
    }
    final char = text[index];
    if (char == '|' && depth == 0) {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(char);
    }
  }
  cells.add(cell.toString().trim());
  return cells;
}

ClipSituation? _fallbackSituation(
    NoteCard card, List<ClipSituation> situations) {
  final stagger = card.heading.startsWith('### staggered');
  final links = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]')
      .allMatches(card.heading)
      .map((match) => match.group(1)!)
      .toSet();
  for (final situation in situations) {
    if (situation.herMoveLink != null &&
        links.contains(situation.herMoveLink) &&
        ((stagger && situation.entry == 'stagger') ||
            (!stagger && situation.entry == 'block'))) {
      return situation;
    }
  }
  return null;
}

enum FinderRunState { running, done, nothing, failed }

class FinderRunInfo {
  const FinderRunInfo({
    required this.state,
    required this.pid,
    required this.batchFolder,
    required this.startedAt,
    required this.finishedAt,
    required this.opponents,
    required this.message,
  });

  factory FinderRunInfo.fromJson(
    Map<String, Object?> json, {
    bool Function(int pid)? isPidAlive,
  }) {
    final rawStatus = json['status']?.toString();
    FinderRunState? state;
    for (final candidate in FinderRunState.values) {
      if (candidate.name == rawStatus) {
        state = candidate;
        break;
      }
    }
    final pid = json['pid'] is num
        ? (json['pid'] as num).toInt()
        : int.tryParse('${json['pid']}');
    var message = json['message']?.toString();
    if (state == FinderRunState.running &&
        (pid == null || !(isPidAlive?.call(pid) ?? true))) {
      state = FinderRunState.failed;
      message = 'The notes finder stopped before it finished.';
    }
    return FinderRunInfo(
      state: state ?? FinderRunState.failed,
      pid: pid,
      batchFolder: json['batch_folder']?.toString(),
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      finishedAt: DateTime.tryParse(json['finished_at']?.toString() ?? ''),
      opponents: _parseFinderOpponents(json['opponents']),
      message: message,
    );
  }

  final FinderRunState state;
  final int? pid;
  final String? batchFolder;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<FinderOpponentRun> opponents;
  final String? message;

  bool get isRunning => state == FinderRunState.running;
}

class FinderOpponentRun {
  const FinderOpponentRun({
    required this.name,
    required this.status,
    required this.situations,
    required this.error,
  });

  final String name;
  final String status;
  final int? situations;
  final String? error;
}

List<FinderOpponentRun> _parseFinderOpponents(Object? raw) {
  if (raw is! List) return const <FinderOpponentRun>[];
  return [
    for (final value in raw)
      if (value is Map)
        FinderOpponentRun(
          name: value['name']?.toString() ?? '',
          status: value['status']?.toString() ?? '',
          situations: value['situations'] is num
              ? (value['situations'] as num).toInt()
              : int.tryParse('${value['situations']}'),
          error: value['error']?.toString(),
        ),
  ];
}

enum ApplySectionState { applied, failed, changed, invalid }

class ApplySectionResult {
  const ApplySectionResult({
    required this.exitCode,
    required this.state,
    required this.message,
  });

  factory ApplySectionResult.fromExitCode(
    int exitCode, {
    required String opponent,
    String stderr = '',
  }) {
    final error = stderr.trim();
    return switch (exitCode) {
      0 => ApplySectionResult(
          exitCode: exitCode,
          state: ApplySectionState.applied,
          message: 'Applied to the $opponent note.',
        ),
      2 => ApplySectionResult(
          exitCode: exitCode,
          state: ApplySectionState.changed,
          message:
              "Your $opponent note's finder notes changed since this draft. Nothing was written.",
        ),
      3 => ApplySectionResult(
          exitCode: exitCode,
          state: ApplySectionState.invalid,
          message: error.isEmpty ? 'The draft could not be applied.' : error,
        ),
      _ => ApplySectionResult(
          exitCode: exitCode,
          state: ApplySectionState.failed,
          message: error.isEmpty ? 'The draft could not be applied.' : error,
        ),
    };
  }

  final int exitCode;
  final ApplySectionState state;
  final String message;

  bool get succeeded => state == ApplySectionState.applied;
}

/// Keeps JSON decoding at the edge of the application.
Map<String, Object?> decodeObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) throw const FormatException('Expected a JSON object.');
  return Map<String, Object?>.from(decoded);
}
