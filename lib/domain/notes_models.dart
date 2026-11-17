import 'dart:convert';

// The finder's sequence list (contract: ggst-input-tracker
// docs/sequences-contract.md). Afterimage reads it and writes recordings; it never
// writes under the finder's `out/` folder.

/// One opponent's sequence list in the list of finder runs.
class NotePreview {
  const NotePreview({
    required this.batchLabel,
    required this.opponent,
    required this.directoryPath,
    required this.documentPath,
    required this.cardCount,
    required this.flaggedCount,
    required this.createdAt,
    required this.modifiedAt,
    this.isReference = false,
    this.replays,
    this.situationCount,
    this.hasReference = false,
  });

  final String batchLabel;
  final String opponent;
  final String directoryPath;
  final String documentPath;
  final int cardCount;
  final int flaggedCount;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool isReference;

  /// Games in the set, when the list says so.
  final int? replays;

  /// Situation cards, without the cards for other ways of getting hit.
  final int? situationCount;

  /// True when the list carries a high-level comparison.
  final bool hasReference;

  DateTime? get sortDate => createdAt ?? modifiedAt;
}

class NoteSequenceData {
  const NoteSequenceData({required this.preview, required this.document});

  final NotePreview preview;
  final SequenceDocument document;
}

/// `sequences.json` for one opponent.
class SequenceDocument {
  const SequenceDocument({
    required this.opponent,
    required this.player,
    required this.batchLabel,
    required this.batchFolder,
    required this.createdAt,
    required this.strivelabsRecordings,
    required this.warnings,
    required this.clipErrors,
    required this.cards,
    this.opponentName,
    this.playerName,
    this.focus = const [],
    this.ledger,
    this.trend,
    this.moves = const {},
    this.isReference = false,
    this.reference,
    this.replays,
  });

  factory SequenceDocument.fromJson(Map<String, Object?> json) {
    final schema = json['schema'];
    if (schema != 1) {
      throw FormatException('Unknown sequence list schema: $schema');
    }
    return SequenceDocument(
      replays: json['replays'] is int && (json['replays'] as int) >= 0
          ? json['replays'] as int
          : null,
      isReference: json['is_reference'] == true,
      reference: DocumentReference.parse(json['reference']),
      trend: SequenceTrend.parse(json['trend']),
      moves: {
        for (final entry in (_readMap(json['moves']) ?? {}).entries)
          if (_readMap(entry.value) case final move?)
            entry.key: MoveCard.fromJson(entry.key, move),
      },
      focus: _typedStrings(json['focus']).take(3).toList(),
      ledger: json['ledger'] is Map<String, Object?>
          ? DamageLedger.fromJson(json['ledger'] as Map<String, Object?>)
          : null,
      opponent: json['opponent']?.toString() ?? '',
      player: _optionalString(json['player']),
      opponentName: _optionalString(json['opponent_name']),
      playerName: _optionalString(json['player_name']),
      batchLabel: json['batch_label']?.toString() ?? '',
      batchFolder: json['batch_folder']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      strivelabsRecordings: _optionalString(json['strivelabs_recordings']),
      warnings: _strings(json['warnings']),
      clipErrors: _strings(json['clip_errors']),
      cards: [
        for (final value in _maps(json['cards'])) SequenceCard.fromJson(value),
      ],
    );
  }

  final String opponent;
  final String? player;
  final String? opponentName;
  final String? playerName;
  final String batchLabel;
  final String batchFolder;
  final DateTime? createdAt;
  final String? strivelabsRecordings;
  final List<String> warnings;
  final List<String> clipErrors;
  final List<SequenceCard> cards;
  final List<String> focus;
  final DamageLedger? ledger;
  final SequenceTrend? trend;
  final bool isReference;
  final DocumentReference? reference;

  /// Games in the set.
  final int? replays;

  /// Move card id (the vault note's name, `Ky 2H`) to the note behind it.
  final Map<String, MoveCard> moves;
}

/// A move note from the vault: frame data, pictures, Dustloop notes, own notes.
class MoveCard {
  MoveCard.fromJson(this.id, Map<String, Object?> json)
      : name = _text(json['name']) ?? id,
        character = _text(json['character']),
        input = _text(json['input']),
        moveName = _text(json['move_name']),
        damage = _text(json['damage']),
        guard = _text(json['guard']),
        startup = _text(json['startup']),
        active = _text(json['active']),
        recovery = _text(json['recovery']),
        level = _text(json['level']),
        onBlock = _text(json['on_block']),
        onHit = _text(json['on_hit']),
        invuln = _text(json['invuln']),
        cancelsInto = _text(json['cancels_into']),
        images = _typedStrings(json['images']),
        notePath = _text(json['note_path']),
        dustloopNotes = _typedStrings(json['dustloop_notes']),
        myNotes = _text(json['my_notes']);

  final String id;
  final String name;
  final String? character;
  final String? input;
  final String? moveName;
  final String? damage;
  final String? guard;
  final String? startup;
  final String? active;
  final String? recovery;
  final String? level;
  final String? onBlock;
  final String? onHit;
  final String? invuln;
  final String? cancelsInto;
  final List<String> images;
  final String? notePath;
  final List<String> dustloopNotes;
  final String? myNotes;

  /// Label and value for every frame-data field the note has, in reading order.
  List<(String, String)> get facts => [
        if (startup != null) ('Startup', startup!),
        if (active != null) ('Active', active!),
        if (recovery != null) ('Recovery', recovery!),
        if (onBlock != null) ('On block', onBlock!),
        if (onHit != null) ('On hit', onHit!),
        if (guard != null) ('Guard', guard!),
        if (damage != null) ('Damage', damage!),
        if (level != null) ('Level', level!),
        if (invuln != null) ('Invuln', invuln!),
        if (cancelsInto != null) ('Cancels into', cancelsInto!),
      ];
}

/// One situation: her last move, his posture and how he got there.
class SequenceCard {
  const SequenceCard({
    required this.id,
    this.kind = 'situation',
    required this.title,
    required this.flagged,
    required this.damage,
    required this.hits,
    required this.decided,
    required this.count,
    required this.flags,
    required this.leadIns,
    required this.sequences,
    required this.mixups,
    this.header,
    this.leadInText,
    this.answers = const [],
    this.reversalNote,
    this.trendText,
    this.read,
    this.eventRead = const [],
    this.moveId,
    this.moveIds = const [],
    this.reference,
  });

  factory SequenceCard.fromJson(Map<String, Object?> json) => SequenceCard(
        reference: CardReference.parse(json['reference']),
        answers: [
          for (final value in _newMaps(json['answers']))
            SequenceAnswer.fromJson(value),
        ],
        read: SituationRead.parse(json['read']),
        eventRead: _typedStrings(json['event_read']),
        moveId: _text(json['move_id']),
        moveIds: _typedStrings(json['move_ids']),
        trendText: _text(json['trend_text']),
        reversalNote: _text(json['reversal_note']),
        id: json['id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'situation',
        title: json['title']?.toString() ?? '',
        header: _optionalString(json['header']),
        leadInText: _optionalString(json['lead_in_text']),
        flagged: json['flagged'] == true,
        damage: _integer(json['damage']) ?? 0,
        hits: _integer(json['hits']) ?? 0,
        decided: _integer(json['decided']) ?? 0,
        count: _integer(json['count']) ?? 0,
        flags: [
          for (final value in _maps(json['flags']))
            SequenceFlag.fromJson(value),
        ],
        leadIns: [
          for (final value in _maps(json['lead_ins']))
            LeadInCount(
              move: _optionalString(value['move']),
              count: _integer(value['count']) ?? 0,
            ),
        ],
        sequences: [
          for (final value in _maps(json['sequences']))
            LabSequence.fromJson(value),
        ],
        mixups: [
          for (final value in _maps(json['mixups']))
            SequenceMixup.fromJson(value),
        ],
      );

  final String id;

  /// Situations, guard crushes, or additive event kinds, including unknown ones.
  final String kind;
  final String title;

  /// Display text from the finder (v0.3.3); `null` in older lists.
  final String? header;
  final String? leadInText;

  /// How a "hit out of a button" card was lost, as ready-to-show sentences.
  final List<String> eventRead;

  /// The opponent's move a situation card is about, as a move card id.
  final String? moveId;

  /// Event cards: the player's button first, then the opponent's moves that hit.
  final List<String> moveIds;
  final List<SequenceAnswer> answers;
  final String? reversalNote;
  final String? trendText;
  final SituationRead? read;
  final CardReference? reference;
  final bool flagged;
  final int damage;
  final int hits;
  final int decided;
  final int count;
  final List<SequenceFlag> flags;
  final List<LeadInCount> leadIns;
  final List<LabSequence> sequences;
  final List<SequenceMixup> mixups;

  bool get isEventCard => kind != 'situation' && kind != 'guard_crush';

  bool get isGuardCrush => kind == 'guard_crush';
}

/// Additive Step 12 situation read. Unknown kinds and fields are retained so a
/// newer finder can still explain its output in an older Afterimage build.
class SituationRead {
  SituationRead._({
    required this.raw,
    required this.version,
    required this.kind,
    required this.adv,
    required this.advCounts,
    required this.scope,
    required this.matrix,
    required this.playerOptions,
    required this.opponentOptions,
    required this.mistakes,
    required this.points,
    required this.mistake,
    required this.reason,
    required this.spacing,
    required this.corner,
    required this.throwRange,
    required this.activeFrames,
    required this.guards,
    required this.fuzzyCandidates,
    required this.additionalDetails,
    required this.summary,
  });

  static SituationRead? parse(Object? value) {
    final json = _readMap(value);
    if (json == null) return null;
    return SituationRead._(
      raw: json,
      version: _integer(json['version']),
      kind: _text(json['kind']) ?? '',
      adv: _integer(json['adv']),
      advCounts: [
        for (final item in _readMaps(json['adv_counts']))
          SituationAdvCount.fromJson(item),
      ],
      scope: _text(json['scope']),
      matrix: SituationMatrix.parse(json['matrix']),
      playerOptions: [
        for (final item in _readMaps(json['player_options']))
          SituationOption.fromJson(item),
      ],
      opponentOptions: [
        for (final item in _readMaps(json['opponent_options']))
          SituationOption.fromJson(item),
      ],
      mistakes: {
        for (final entry in (_readMap(json['mistakes']) ?? {}).entries)
          if (_readMap(entry.value) case final item?)
            entry.key: SituationMistakeCount.fromJson(item),
      },
      points: [
        for (final item in _readMaps(json['points']))
          if (SituationRead.parse(item) case final point?) point,
      ],
      mistake: _text(json['mistake']),
      reason: _text(json['reason']),
      spacing: _text(json['spacing']),
      corner: json['corner'],
      throwRange: json['throw_range'] ?? json['throw_range_bracket'],
      activeFrames: json['active_frames'] ?? json['active_frame'],
      guards: json['guards'],
      fuzzyCandidates: json['fuzzy_candidates'],
      additionalDetails: _situationAdditionalDetails(json),
      summary: SituationSummary.parse(json['summary']),
    );
  }

  /// The original object is retained for future additive fields and diagnostics.
  final Map<String, Object?> raw;
  final int? version;
  final String kind;
  final int? adv;
  final List<SituationAdvCount> advCounts;
  final String? scope;
  final SituationMatrix? matrix;
  final List<SituationOption> playerOptions;
  final List<SituationOption> opponentOptions;
  final Map<String, SituationMistakeCount> mistakes;
  final List<SituationRead> points;

  /// Per-sequence assessment. Unknown values remain ordinary display strings.
  final String? mistake;
  final String? reason;
  final String? spacing;
  final Object? corner;
  final Object? throwRange;
  final Object? activeFrames;
  final Object? guards;
  final Object? fuzzyCandidates;

  /// Unrecognised and newly additive details, flattened to plain text for display.
  final List<String> additionalDetails;

  /// The plain reading of the card: per spot, both sides' options and who beats
  /// who. Null on lists written before the finder produced it.
  final SituationSummary? summary;
}

class SituationSummary {
  SituationSummary._({
    required this.spots,
    required this.note,
    required this.unread,
  });

  static SituationSummary? parse(Object? value) {
    final json = _readMap(value);
    if (json == null) return null;
    return SituationSummary._(
      spots: [
        for (final item in _readMaps(json['spots']))
          SituationSpot.fromJson(item),
      ],
      note: _text(json['note']),
      unread: SituationUnread.parse(json['unread']),
    );
  }

  final List<SituationSpot> spots;
  final String? note;
  final SituationUnread? unread;
}

class SituationUnread {
  SituationUnread.fromJson(Map<String, Object?> json)
      : count = _count(json['count']),
        reason = _text(json['reason']);

  static SituationUnread? parse(Object? value) {
    final json = _readMap(value);
    return json == null ? null : SituationUnread.fromJson(json);
  }

  final int count;
  final String? reason;
}

class SituationSpot {
  SituationSpot.fromJson(Map<String, Object?> json)
      : kind = _text(json['kind']) ?? '',
        title = _text(json['title']) ?? '',
        count = _count(json['count']),
        context = _text(json['context']),
        where = _typedStrings(json['where']),
        player = _text(json['player']),
        opponent = _text(json['opponent']),
        opponentRows = [
          for (final item in _readMaps(json['opponent_rows']))
            SituationSummaryRow.fromJson(item),
        ],
        playerRows = [
          for (final item in _readMaps(json['player_rows']))
            SituationSummaryRow.fromJson(item),
        ],
        lines = _typedStrings(json['lines']),
        notes = [
          for (final item in _readMaps(json['notes']))
            SituationSummaryNote.fromJson(item),
        ];

  final String kind;
  final String title;
  final int count;
  final String? context;
  final List<String> where;
  final String? player;
  final String? opponent;
  final List<SituationSummaryRow> opponentRows;
  final List<SituationSummaryRow> playerRows;
  final List<String> lines;
  final List<SituationSummaryNote> notes;
}

class SituationSummaryNote {
  SituationSummaryNote.fromJson(Map<String, Object?> json)
      : kind = _text(json['kind']) ?? '',
        text = _text(json['text']) ?? '',
        rows = _typedStrings(json['rows']),
        versus = _text(json['versus']),
        points = _typedStrings(json['points']);

  final String kind;
  final String text;
  final List<String> rows;
  final String? versus;
  final List<String> points;
}

class SituationSummaryRow {
  SituationSummaryRow.fromJson(Map<String, Object?> json)
      : name = _text(json['name']) ?? '',
        count = _count(json['count']),
        of = _count(json['of']),
        seen = json['seen'] == true,
        how = _text(json['how']) ?? '',
        beats = _typedStrings(json['beats']),
        losesTo = _typedStrings(json['loses_to']),
        theory = json['theory'] == true,
        hit = _count(json['hit']),
        moves = _typedStrings(json['moves']),
        disproved = {
          for (final entry in (_readMap(json['disproved']) ?? {}).entries)
            entry.key: _count(entry.value),
        },
        basis = {
          for (final entry in (_readMap(json['basis']) ?? {}).entries)
            if (entry.value is String) entry.key: entry.value as String,
        },
        proof = {
          for (final entry in (_readMap(json['proof']) ?? {}).entries)
            if (entry.value is String) entry.key: entry.value as String,
        },
        seenVs = {
          for (final entry in (_readMap(json['seen_vs']) ?? {}).entries)
            if (SituationSeen.parse(entry.value) case final seen?)
              entry.key: seen,
        };

  final String name;
  final int count;
  final int of;
  final bool seen;
  final String how;
  final List<String> beats;
  final List<String> losesTo;
  final bool theory;
  final int hit;

  /// Move card ids of the notes behind this row's options.
  final List<String> moves;

  /// Other side's row name to the times this row lost to it here although the
  /// timing rules call it a win.
  final Map<String, int> disproved;
  final Map<String, String> basis;
  final Map<String, String> proof;
  final Map<String, SituationSeen> seenVs;
}

class SituationAdvCount {
  SituationAdvCount.fromJson(Map<String, Object?> json)
      : adv = _integer(json['adv']),
        count = _count(json['count']);

  final int? adv;
  final int count;
}

class SituationMistakeCount {
  SituationMistakeCount.fromJson(Map<String, Object?> json)
      : count = _count(json['count']),
        points = _typedStrings(json['points']);

  final int count;
  final List<String> points;
}

class SituationMatrix {
  SituationMatrix._({
    required this.playerOptions,
    required this.opponentOptions,
    required this.rows,
    required this.neverWorksHere,
    required this.dominantRows,
    required this.note,
    required this.spacingCutRaw,
    required this.routes,
  });

  static SituationMatrix? parse(Object? value) {
    final json = _readMap(value);
    if (json == null) return null;
    return SituationMatrix._(
      playerOptions: [
        for (final item in _readMaps(json['player_options']))
          SituationOption.fromJson(item),
      ],
      opponentOptions: [
        for (final item in _readMaps(json['opponent_options']))
          SituationOption.fromJson(item),
      ],
      rows: [
        for (final item in _readMaps(json['rows']))
          SituationMatrixRow.fromJson(item),
      ],
      neverWorksHere: _rawList(json['never_works_here']),
      dominantRows: _rawList(json['dominant_rows']),
      note: _text(json['note']),
      spacingCutRaw: _number(json['spacing_cut_raw']),
      routes: [
        for (final item in _readMaps(json['routes']))
          SituationRoute.fromJson(item),
      ],
    );
  }

  final List<SituationOption> playerOptions;
  final List<SituationOption> opponentOptions;
  final List<SituationMatrixRow> rows;
  final List<Object?> neverWorksHere;
  final List<Object?> dominantRows;
  final String? note;
  final double? spacingCutRaw;
  final List<SituationRoute> routes;
}

class SituationOption {
  SituationOption.fromJson(Map<String, Object?> json)
      : id = _text(json['id']) ?? '',
        label = _text(json['label']) ?? '',
        kind = _text(json['kind']) ?? '',
        guard = _text(json['guard']),
        startup = _integer(json['startup']),
        sources = _typedStrings(json['sources']),
        tensionCost = _integer(json['tension_cost']),
        availability = _text(json['availability']),
        available = _integer(json['available']),
        tensionUnknown = _integer(json['tension_unknown']),
        possible = _integer(json['possible']),
        reach = _text(json['reach']),
        activeFrames = json['active_frames'] ?? json['active_frame'],
        guards = json['guards'],
        fuzzyCandidates = json['fuzzy_candidates'],
        corner = json['corner'],
        throwRange = json['throw_range'] ?? json['throw_range_bracket'];

  final String id;
  final String label;
  final String kind;
  final String? guard;
  final int? startup;
  final List<String> sources;
  final int? tensionCost;
  final String? availability;
  final int? available;
  final int? tensionUnknown;
  final int? possible;
  final String? reach;
  final Object? activeFrames;
  final Object? guards;
  final Object? fuzzyCandidates;
  final Object? corner;
  final Object? throwRange;
}

class SituationMatrixRow {
  SituationMatrixRow.fromJson(Map<String, Object?> json)
      : options = _typedStrings(json['options']),
        cells = {
          for (final entry in (_readMap(json['cells']) ?? {}).entries)
            if (_readMap(entry.value) case final cell?)
              entry.key: SituationMatrixCell.fromJson(cell),
        };

  final List<String> options;
  final Map<String, SituationMatrixCell> cells;
}

class SituationMatrixCell {
  SituationMatrixCell.fromJson(Map<String, Object?> json)
      : value = _text(json['value']) ?? '',
        winner = _text(json['winner']),
        values = {
          for (final entry in (_readMap(json['values']) ?? {}).entries)
            if (entry.value is num && (entry.value as num).isFinite)
              entry.key: (entry.value as num).toInt(),
        },
        seen = SituationSeen.parse(json['seen']);

  final String value;
  final String? winner;
  final Map<String, int> values;
  final SituationSeen? seen;
}

class SituationSeen {
  SituationSeen.fromJson(Map<String, Object?> json)
      : count = _count(json['count']),
        won = _count(json['won']),
        lost = _count(json['lost']),
        pressure = _count(json['pressure']),
        neutral = _count(json['neutral']),
        points = _typedStrings(json['points']);

  static SituationSeen? parse(Object? value) {
    final json = _readMap(value);
    return json == null ? null : SituationSeen.fromJson(json);
  }

  final int count;
  final int won;
  final int lost;
  final int pressure;
  final int neutral;
  final List<String> points;
}

class SituationRoute {
  SituationRoute.fromJson(Map<String, Object?> json)
      : leadIn = _text(json['lead_in']),
        spacing = _text(json['spacing']),
        corner = json['corner'],
        count = _count(json['count']),
        options = [
          for (final item in _readMaps(json['options']))
            SituationRouteOption.fromJson(item),
        ];

  final String? leadIn;
  final String? spacing;
  final Object? corner;
  final int count;
  final List<SituationRouteOption> options;
}

class SituationRouteOption {
  SituationRouteOption.fromJson(Map<String, Object?> json)
      : option = _text(json['option']) ?? '',
        count = _count(json['count']);

  final String option;
  final int count;
}

const _situationKnownKeys = <String>{
  'version',
  'kind',
  'adv',
  'adv_counts',
  'scope',
  'matrix',
  'mistakes',
  'points',
  'throw',
  'throw_options',
  'tension',
  'distance',
  'answer_delay',
  'visible_frames',
  'timing_complete',
  'player_options',
  'opponent_options',
  'spacing',
  'corner',
  'mistake',
  'reason',
  'active_frame',
  'active_frames',
  'guards',
  'fuzzy_candidates',
  'throw_range',
  'throw_range_bracket',
  'id',
  'label',
  'startup',
  'sources',
  'tension_cost',
  'availability',
  'available',
  'tension_unknown',
  'possible',
  'reach',
  'rows',
  'options',
  'cells',
  'never_works_here',
  'dominant_rows',
  'note',
  'spacing_cut_raw',
  'routes',
  'value',
  'winner',
  'values',
  'seen',
  'count',
  'won',
  'lost',
  'pressure',
  'neutral',
  'sequence_id',
  'replay',
  'frame',
  'assessed',
  'status',
  'range',
  'source',
  'player',
  'opponent',
  'scale',
  'lead_in',
  'option',
  'unc check',
  'guard',
  'timings',
  'base_option',
  'start_frame',
  'reactable',
  'capture_gap',
  'approach',
  'distance_at_start',
  'throw_at_start',
  'fuzzy_note',
  'corner_note',
  'corner_margin_raw',
  'bracket',
  'farthest_connect',
  'nearest_whiff',
  'connected',
  'whiffed',
  'unknown',
};

const _situationAdditiveTextKeys = <String>{
  'active_frame',
  'active_frames',
  'guards',
  'fuzzy_candidates',
  'corner',
  'throw_range',
  'throw_range_bracket',
};

List<String> _situationAdditionalDetails(Map<String, Object?> json) {
  final details = <String>[];

  void visit(Object? value, String path, {String? shape}) {
    if (value is List) {
      for (var index = 0; index < value.length; index++) {
        visit(value[index], '$path[$index]', shape: shape);
      }
      return;
    }
    final map = _readMap(value);
    if (map == null) return;
    for (final entry in map.entries) {
      final key = entry.key;
      final childPath = path.isEmpty ? key : '$path.$key';
      // The summary has its own model and its own place on the card.
      if (key == 'summary' && path.isEmpty) continue;
      if (_situationAdditiveTextKeys.contains(key)) {
        if (entry.value != null) {
          details.add('$childPath: ${_plainSituationValue(entry.value)}');
        }
        continue;
      }
      if (shape == 'values') continue;
      if (shape == 'cells') {
        visit(entry.value, childPath, shape: 'cell');
        continue;
      }
      if (shape == 'mistakes') {
        visit(entry.value, childPath, shape: 'mistake');
        continue;
      }
      if (shape == 'throwOptions') {
        visit(entry.value, childPath, shape: 'throwOptionSide');
        continue;
      }
      if (shape == 'throwOptionSide') {
        visit(entry.value, childPath, shape: 'throwOption');
        continue;
      }
      if (!_situationKnownKeys.contains(key)) {
        details.add('$childPath: ${_plainSituationValue(entry.value)}');
        continue;
      }
      final childShape = switch (key) {
        'cells' => 'cells',
        'values' => 'values',
        'mistakes' => 'mistakes',
        'throw_options' => 'throwOptions',
        _ => null,
      };
      // Sequence reads are rendered under their own row, so avoid duplicating
      // their point-specific extensions at the card level.
      if (key == 'points' && path.isEmpty) continue;
      visit(entry.value, childPath, shape: childShape);
    }
  }

  visit(json, '');
  return details;
}

String _plainSituationValue(Object? value) {
  if (value is String) return value;
  try {
    return jsonEncode(value);
  } on Object {
    return value.toString();
  }
}

Map<String, Object?>? _readMap(Object? value) {
  if (value is! Map) return null;
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

List<Map<String, Object?>> _readMaps(Object? value) => value is List
    ? [
        for (final item in value)
          if (_readMap(item) case final map?) map
      ]
    : const [];

List<Object?> _rawList(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

// Optional additive finder data is strictly typed and defaults safely.
String? _text(Object? value) => value is String ? value : null;
int _count(Object? value) => value is num && value.isFinite ? value.toInt() : 0;
double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
List<String> _typedStrings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];
List<Map<String, Object?>> _newMaps(Object? value) =>
    value is List ? value.whereType<Map<String, Object?>>().toList() : const [];

/// Additive cross-set comparisons. Invalid objects are omitted, never coerced.
class SequenceTrend {
  SequenceTrend._(this.sets, this.ledger, this.cards);

  static SequenceTrend? parse(Object? raw) {
    if (raw is! Map<String, Object?> || raw['sets'] is! List) return null;
    final sets = [
      for (final value in _newMaps(raw['sets']))
        if (TrendSet.parse(value) case final set?) set,
    ];
    if (sets.isEmpty) return null;
    return SequenceTrend._(
        sets, LedgerTrend.parse(raw['ledger']), CardsTrend.parse(raw['cards']));
  }

  final List<TrendSet> sets;
  final LedgerTrend? ledger;
  final CardsTrend? cards;
}

class TrendPrevious {
  TrendPrevious._(this.batchLabel, this.date, this.replays);

  static TrendPrevious? parse(Object? raw) {
    if (raw is! Map<String, Object?> ||
        raw['batch_label'] is! String ||
        raw['date'] is! String ||
        !_trendCount(raw['replays'])) {
      return null;
    }
    return TrendPrevious._(raw['batch_label'] as String, raw['date'] as String,
        _count(raw['replays']));
  }

  final String batchLabel;
  final String date;
  final int replays;
}

bool _trendCount(Object? value) =>
    value is num &&
    value.isFinite &&
    value >= 0 &&
    value == value.truncateToDouble();

class TrendSet extends TrendPrevious {
  TrendSet._(TrendPrevious previous, this.hpReplays, this.damagePerReplay,
      this.current)
      : super._(previous.batchLabel, previous.date, previous.replays);

  static TrendSet? parse(Object? raw) {
    final previous = TrendPrevious.parse(raw);
    if (previous == null ||
        raw is! Map<String, Object?> ||
        !_trendCount(raw['hp_replays']) ||
        raw['current'] is! bool ||
        (raw['damage_per_replay'] != null &&
            _number(raw['damage_per_replay']) == null)) {
      return null;
    }
    return TrendSet._(previous, _count(raw['hp_replays']),
        _number(raw['damage_per_replay']), raw['current'] as bool);
  }

  final int hpReplays;
  final double? damagePerReplay;
  final bool current;
}

class TrendDamage {
  TrendDamage._(this.now, this.before, this.delta);

  static TrendDamage? parse(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final now = _number(raw['now']);
    final before = _number(raw['before']);
    final delta = _number(raw['delta']);
    if (now == null || before == null || delta == null) return null;
    return TrendDamage._(now, before, delta);
  }

  final double now;
  final double before;
  final double delta;
}

class TrendCategory extends TrendDamage {
  TrendCategory._(this.key, this.label, TrendDamage damage)
      : super._(damage.now, damage.before, damage.delta);

  static TrendCategory? parse(Object? raw) {
    final damage = TrendDamage.parse(raw);
    if (damage == null ||
        raw is! Map<String, Object?> ||
        raw['key'] is! String ||
        raw['label'] is! String) {
      return null;
    }
    return TrendCategory._(
        raw['key'] as String, raw['label'] as String, damage);
  }

  final String key;
  final String label;
}

class LedgerTrend {
  LedgerTrend._(this.previous, this.text, this.total, this.categories);

  static LedgerTrend? parse(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final previous = TrendPrevious.parse(raw['previous']);
    final total = TrendDamage.parse(raw['total']);
    if (previous == null ||
        total == null ||
        raw['text'] is! String ||
        raw['categories'] is! List) {
      return null;
    }
    return LedgerTrend._(previous, raw['text'] as String, total, [
      for (final value in _newMaps(raw['categories']))
        if (TrendCategory.parse(value) case final category?) category,
    ]);
  }

  final TrendPrevious previous;
  final String text;
  final TrendDamage total;
  final List<TrendCategory> categories;
}

class GoneTrendCard {
  GoneTrendCard._(this.title, this.kind, this.text);

  static GoneTrendCard? parse(Object? raw) {
    if (raw is! Map<String, Object?> ||
        raw['title'] is! String ||
        raw['kind'] is! String ||
        raw['text'] is! String) {
      return null;
    }
    return GoneTrendCard._(
        raw['title'] as String, raw['kind'] as String, raw['text'] as String);
  }

  final String title;
  final String kind;
  final String text;
}

class CardsTrend {
  CardsTrend._(this.previous, this.text, this.gone);

  static CardsTrend? parse(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final previous = TrendPrevious.parse(raw['previous']);
    if (previous == null || raw['text'] is! String || raw['gone'] is! List) {
      return null;
    }
    return CardsTrend._(previous, raw['text'] as String, [
      for (final value in _newMaps(raw['gone']))
        if (GoneTrendCard.parse(value) case final card?) card,
    ]);
  }

  final TrendPrevious previous;
  final String text;
  final List<GoneTrendCard> gone;
}

class DamageLedger {
  DamageLedger.fromJson(Map<String, Object?> json)
      : totalDamage = _count(json['total_damage']),
        damagePerReplay = _number(json['damage_per_replay']),
        replays = _count(json['replays']),
        coveredByCards = _count(json['covered_by_cards']),
        categories = [
          for (final value in _newMaps(json['categories']))
            LedgerCategory.fromJson(value),
        ];

  final int totalDamage;
  final double? damagePerReplay;
  final int replays;
  final int coveredByCards;
  final List<LedgerCategory> categories;
}

class LedgerCategory {
  LedgerCategory.fromJson(Map<String, Object?> json)
      : key = _text(json['key']) ?? '',
        label = _text(json['label']) ?? '',
        damage = _count(json['damage']),
        events = _count(json['events']),
        share = _number(json['share']) ?? 0,
        damagePerReplay = _number(json['damage_per_replay']),
        cards = _typedStrings(json['cards']),
        starters = [
          for (final value in _newMaps(json['starters']))
            LedgerStarter.fromJson(value),
        ],
        hisMoves = [
          for (final value in _newMaps(json['his_moves']))
            LedgerMove.fromJson(value),
        ];

  final String key;
  final String label;
  final int damage;
  final int events;
  final double share;
  final double? damagePerReplay;
  final List<String> cards;
  final List<LedgerStarter> starters;
  final List<LedgerMove> hisMoves;
}

class LedgerMove {
  LedgerMove.fromJson(Map<String, Object?> json)
      : move = _text(json['move']) ?? '',
        damage = _count(json['damage']),
        events = _count(json['events']);

  final String move;
  final int damage;
  final int events;
}

class LedgerStarter extends LedgerMove {
  LedgerStarter.fromJson(super.json)
      : counterHits = _count(json['counter_hits']),
        examples = [
          for (final value in _newMaps(json['examples']))
            LedgerExample.fromJson(value),
        ],
        super.fromJson();

  final int counterHits;
  final List<LedgerExample> examples;
}

class LedgerExample {
  LedgerExample.fromJson(Map<String, Object?> json)
      : replay = _count(json['replay']),
        round = _count(json['round']),
        videoTime = _number(json['video_time']),
        damage = _count(json['damage']);

  final int replay;
  final int round;
  final double? videoTime;
  final int damage;
}

class SequenceAnswer {
  SequenceAnswer.fromJson(Map<String, Object?> json)
      : text = _text(json['text']) ?? '',
        count = _count(json['count']),
        gotHit = _count(json['got_hit']),
        won = _count(json['won']),
        pressure = _count(json['pressure']),
        neutral = _count(json['neutral']),
        damage = _count(json['damage']);

  final String text;
  final int count;
  final int gotHit;
  final int won;
  final int pressure;
  final int neutral;
  final int damage;
}

class DocumentReference {
  DocumentReference.fromJson(Map<String, Object?> json)
      : replays = _integerReference(json['replays']),
        batches = _typedStrings(json['batches']),
        ledger = _referenceLedger(json['ledger']),
        afterBlock = ReferenceAfterBlock.parse(json['after_block']);

  static DocumentReference? parse(Object? value) {
    final map = _readMap(value);
    return map == null ? null : DocumentReference.fromJson(map);
  }

  final int? replays;
  final List<String> batches;
  final DamageLedger? ledger;
  final ReferenceAfterBlock? afterBlock;
}

DamageLedger? _referenceLedger(Object? value) {
  final map = _readMap(value);
  return map == null ? null : DamageLedger.fromJson(map);
}

int? _integerReference(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

class ReferenceAfterBlock {
  ReferenceAfterBlock.fromJson(Map<String, Object?> json)
      : own = ReferenceAnswers.parse(json['own']),
        reference = ReferenceAnswers.parse(json['reference']);

  static ReferenceAfterBlock? parse(Object? value) {
    final map = _readMap(value);
    return map == null ? null : ReferenceAfterBlock.fromJson(map);
  }

  final ReferenceAnswers? own;
  final ReferenceAnswers? reference;
}

class ReferenceAnswers {
  ReferenceAnswers.fromJson(Map<String, Object?> json)
      : count = _integerReference(json['count']),
        hits = _integerReference(json['hits']),
        answers = [
          for (final item in _readMaps(json['answers']))
            SequenceAnswer.fromJson(item),
        ];

  static ReferenceAnswers? parse(Object? value) {
    final map = _readMap(value);
    return map == null ? null : ReferenceAnswers.fromJson(map);
  }

  final int? count;
  final int? hits;
  final List<SequenceAnswer> answers;
}

class CardReference {
  CardReference.fromJson(Map<String, Object?> json)
      : replays = _integerReference(json['replays']),
        count = _integerReference(json['count']),
        hits = _integerReference(json['hits']),
        damage = _integerReference(json['damage']),
        decided = _integerReference(json['decided']),
        answers = [
          for (final item in _readMaps(json['answers']))
            SequenceAnswer.fromJson(item),
        ],
        spots = [
          for (final item in _readMaps(json['spots']))
            ReferenceSpot.fromJson(item),
        ];

  static CardReference? parse(Object? value) {
    final map = _readMap(value);
    return map == null ? null : CardReference.fromJson(map);
  }

  final int? replays;
  final int? count;
  final int? hits;
  final int? damage;
  final int? decided;
  final List<SequenceAnswer> answers;
  final List<ReferenceSpot> spots;
}

class ReferenceSpot {
  ReferenceSpot.fromJson(Map<String, Object?> json)
      : kind = _text(json['kind']),
        count = _integerReference(json['count']),
        playerRows = [
          for (final item in _readMaps(json['player_rows']))
            ReferenceRow.fromJson(item),
        ],
        opponentRows = [
          for (final item in _readMaps(json['opponent_rows']))
            ReferenceRow.fromJson(item),
        ];

  final String? kind;
  final int? count;
  final List<ReferenceRow> playerRows;
  final List<ReferenceRow> opponentRows;
}

class ReferenceRow {
  ReferenceRow.fromJson(Map<String, Object?> json)
      : name = _text(json['name']),
        count = _integerReference(json['count']),
        hit = _integerReference(json['hit']);

  final String? name;
  final int? count;
  final int? hit;
}

class SequenceFlag {
  const SequenceFlag({
    required this.kind,
    required this.reason,
    required this.player,
  });

  factory SequenceFlag.fromJson(Map<String, Object?> json) => SequenceFlag(
        kind: json['kind']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        player: _optionalString(json['player']),
      );

  final String kind;
  final String reason;
  final String? player;
}

/// The move before her last move; `null` when her last move opened the string.
class LeadInCount {
  const LeadInCount({required this.move, required this.count});

  final String? move;
  final int count;

  String get label => move ?? 'string opener';
}

/// One decision point and her inputs for it.
class LabSequence {
  const LabSequence({
    required this.id,
    required this.replay,
    required this.round,
    required this.videoTime,
    required this.leadIn,
    required this.followUp,
    required this.answer,
    required this.outcome,
    required this.counterHit,
    required this.damage,
    required this.flags,
    required this.recording,
    required this.recordingError,
    required this.clip,
    this.line,
    this.result,
    this.read,
  });

  factory LabSequence.fromJson(Map<String, Object?> json) {
    final recording = json['recording'];
    final clip = json['clip'];
    return LabSequence(
      id: json['id']?.toString() ?? '',
      replay: _integer(json['replay']),
      round: _integer(json['round']),
      videoTime: json['video_time']?.toString() ?? '',
      leadIn: _optionalString(json['lead_in']),
      followUp: json['follow_up']?.toString() ?? '',
      answer: json['answer']?.toString() ?? '',
      outcome: json['outcome']?.toString() ?? '',
      counterHit: json['counter_hit'] == true,
      damage: _integer(json['damage']) ?? 0,
      flags: _strings(json['flags']),
      recording: recording is Map
          ? LabRecording.fromJson(Map<String, Object?>.from(recording))
          : null,
      recordingError: _optionalString(json['recording_error']),
      clip: clip is Map
          ? NoteClip.fromJson(Map<String, Object?>.from(clip))
          : null,
      line: _optionalString(json['line']),
      result: _optionalString(json['result']),
      read: SituationRead.parse(json['read']),
    );
  }

  final String id;

  /// `2K > S Mr. Dolphin Vertical > 5H` and `Ky crouch-blocked · May hit Ky
  /// (70 damage)` from the finder (v0.3.3); `null` in older lists.
  final String? line;
  final String? result;
  final SituationRead? read;
  final int? replay;
  final int? round;
  final String videoTime;
  final String? leadIn;
  final String followUp;
  final String answer;
  final String outcome;
  final bool counterHit;
  final int damage;
  final List<String> flags;
  final LabRecording? recording;
  final String? recordingError;
  final NoteClip? clip;

  /// `r3 · round 1 · 06:57.1`
  String get where => [
        if (replay != null) 'r$replay',
        if (round != null) 'round $round',
        if (videoTime.isNotEmpty) videoTime,
      ].join(' · ');

  /// `2K > S Mr. Dolphin Vertical` is on the card; this is what followed.
  String get summary {
    final parts = <String>[
      if (leadIn != null) 'after $leadIn',
      'then $followUp',
      if (answer.isNotEmpty) 'you: $answer',
      '$outcome${counterHit ? ' (CH)' : ''}',
      if (damage > 0) '-$damage',
    ];
    return parts.join(' · ');
  }
}

/// One StriveLabs `.txt` file ready to write.
class LabRecording {
  const LabRecording({
    required this.fileName,
    required this.text,
    required this.frames,
  });

  factory LabRecording.fromJson(Map<String, Object?> json) => LabRecording(
        fileName: json['file_name']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        frames: _integer(json['frames']) ?? 0,
      );

  final String fileName;
  final String text;
  final int frames;

  /// Only a plain `.txt` name is written: no folders, no hidden files.
  bool get hasSafeFileName =>
      fileName.isNotEmpty &&
      fileName.endsWith('.txt') &&
      !fileName.startsWith('.') &&
      !fileName.contains('/') &&
      !fileName.contains('\\') &&
      !fileName.contains('\u0000');
}

/// Her options after one lead-in, one file each.
class SequenceMixup {
  const SequenceMixup({
    required this.leadIn,
    required this.files,
    this.heading,
  });

  factory SequenceMixup.fromJson(Map<String, Object?> json) => SequenceMixup(
        leadIn: _optionalString(json['lead_in']),
        heading: _optionalString(json['label']),
        files: [
          for (final value in _maps(json['files']))
            MixupFile(
              recording: LabRecording.fromJson(value),
              followUp: value['follow_up']?.toString() ?? '',
              count: _integer(value['count']) ?? 0,
            ),
        ],
      );

  final String? leadIn;
  final List<MixupFile> files;

  /// `May's mixup after 2K > S Mr. Dolphin Vertical:` from the finder (v0.3.3).
  final String? heading;

  String get label => leadIn == null ? 'as an opener' : 'after $leadIn';
}

class MixupFile {
  const MixupFile({
    required this.recording,
    required this.followUp,
    required this.count,
  });

  final LabRecording recording;
  final String followUp;
  final int count;
}

/// Where Save wrote files, and whether StriveLabs got them too.
class RecordingSaveResult {
  const RecordingSaveResult({
    required this.batchDirectory,
    required this.strivelabsDirectory,
    required this.fileNames,
    this.strivelabsError,
  });

  final String batchDirectory;

  /// `null` when StriveLabs was not found or could not be written.
  final String? strivelabsDirectory;

  /// Why the StriveLabs copy failed; the batch copy was still written.
  final String? strivelabsError;
  final List<String> fileNames;

  String get message {
    final what =
        fileNames.length == 1 ? fileNames.single : '${fileNames.length} files';
    if (strivelabsDirectory != null) {
      return 'Saved $what to StriveLabs recordings and $batchDirectory.';
    }
    if (strivelabsError != null) {
      return 'Saved $what to $batchDirectory, but not to StriveLabs: '
          '$strivelabsError';
    }
    return 'Saved $what to $batchDirectory. StriveLabs was not found, so copy '
        'it to ue4ss/recordings yourself.';
  }
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
    return NoteClip(
      file: json['file']?.toString() ?? '',
      poster: json['poster']?.toString(),
      replay: _integer(json['replay']),
      videoTime: json['video_time']?.toString(),
      videoTimeMs: _integer(json['video_time_ms']),
      startMs: _integer(json['start_ms']),
      endMs: _integer(json['end_ms']),
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

  /// What she did after her last move.
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
      message = 'The sequence finder stopped before it finished.';
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
          situations: _integer(value['situations']),
          error: value['error']?.toString(),
        ),
  ];
}

int? _integer(Object? value) => value is num
    ? value.toInt()
    : value == null
        ? null
        : int.tryParse('$value');

String? _optionalString(Object? value) => value?.toString();

List<String> _strings(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const <String>[];

List<Map<String, Object?>> _maps(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Map<String, Object?>.from(item),
      ]
    : const <Map<String, Object?>>[];

/// Keeps JSON decoding at the edge of the application.
Map<String, Object?> decodeObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) throw const FormatException('Expected a JSON object.');
  return Map<String, Object?>.from(decoded);
}
