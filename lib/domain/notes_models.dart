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
  });

  final String batchLabel;
  final String opponent;
  final String directoryPath;
  final String documentPath;
  final int cardCount;
  final int flaggedCount;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

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
  });

  factory SequenceDocument.fromJson(Map<String, Object?> json) {
    final schema = json['schema'];
    if (schema != 1) {
      throw FormatException('Unknown sequence list schema: $schema');
    }
    return SequenceDocument(
      opponent: json['opponent']?.toString() ?? '',
      player: _optionalString(json['player']),
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
  final String batchLabel;
  final String batchFolder;
  final DateTime? createdAt;
  final String? strivelabsRecordings;
  final List<String> warnings;
  final List<String> clipErrors;
  final List<SequenceCard> cards;
}

/// One situation: her last move, his posture and how he got there.
class SequenceCard {
  const SequenceCard({
    required this.id,
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
  });

  factory SequenceCard.fromJson(Map<String, Object?> json) => SequenceCard(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
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
  final String title;
  final bool flagged;
  final int damage;
  final int hits;
  final int decided;
  final int count;
  final List<SequenceFlag> flags;
  final List<LeadInCount> leadIns;
  final List<LabSequence> sequences;
  final List<SequenceMixup> mixups;
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
    );
  }

  final String id;
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
  const SequenceMixup({required this.leadIn, required this.files});

  factory SequenceMixup.fromJson(Map<String, Object?> json) => SequenceMixup(
        leadIn: _optionalString(json['lead_in']),
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
