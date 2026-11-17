import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/notes_models.dart';

/// The move's first picture, tappable to open the whole note.
class MoveThumb extends StatelessWidget {
  const MoveThumb({super.key, required this.move, this.size = 56});

  final MoveCard move;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open ${move.id}',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showMoveCard(context, move),
        child: Container(
          width: size * 1.35,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AfterimageTheme.canvas,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AfterimageTheme.hairline),
          ),
          child: move.images.isEmpty
              ? const Icon(Icons.image_not_supported_outlined, size: 18)
              : _MoveImage(path: move.images.first),
        ),
      ),
    );
  }
}

class _MoveImage extends StatelessWidget {
  const _MoveImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Image.file(
        File(path),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined, size: 18),
      );
}

/// Picture plus the frame data on one line: the header of a card about a move.
class MoveStrip extends StatelessWidget {
  const MoveStrip(
      {super.key, required this.move, this.label, this.size = 96, this.title});

  final MoveCard move;
  final String? label;
  final double size;

  /// Shown in place of the move's own name line, for a page header.
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MoveThumb(move: move, size: size),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                title!
              else
                Text(
                  [
                    if (label != null) label!,
                    move.id,
                    if (move.input != null && move.input != move.name)
                      '(${move.input})',
                  ].join(' '),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              SizedBox(height: title == null ? 4 : 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (name, value) in move.facts.take(6))
                    _FactChip(name: name, value: value),
                ],
              ),
              if (move.myNotes case final notes?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'My note: $notes',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AfterimageTheme.blockedText),
                  ),
                )
              else if (move.facts.isEmpty)
                Text('No frame data in the note.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AfterimageTheme.panelRaised,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AfterimageTheme.hairline),
      ),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '$name ',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        TextSpan(
            text: value,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ])),
    );
  }
}

/// The whole note: every picture, all frame data, Dustloop notes, own notes.
Future<void> showMoveCard(BuildContext context, MoveCard move) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurfaceVariant;
      return Dialog(
        key: ValueKey('move-dialog-${move.id}'),
        backgroundColor: AfterimageTheme.panel,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 820),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      [
                        move.id,
                        if (move.input != null && move.input != move.name)
                          '· ${move.input}',
                      ].join(' '),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('close-move-dialog'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (move.images.isNotEmpty)
                          SizedBox(
                            height: 300,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: move.images.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, index) => Container(
                                constraints:
                                    const BoxConstraints(minWidth: 260),
                                decoration: BoxDecoration(
                                  color: AfterimageTheme.canvas,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AfterimageTheme.hairline),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _MoveImage(path: move.images[index]),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final (name, value) in move.facts)
                              _FactChip(name: name, value: value),
                          ],
                        ),
                        if (move.myNotes case final notes?) ...[
                          const SizedBox(height: 16),
                          Text('MY NOTES',
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: AfterimageTheme.blockedText,
                                  letterSpacing: 0.6)),
                          const SizedBox(height: 4),
                          Text(notes, style: theme.textTheme.bodyMedium),
                        ],
                        if (move.dustloopNotes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('DUSTLOOP NOTES',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: muted, letterSpacing: 0.6)),
                          const SizedBox(height: 4),
                          for (final note in move.dustloopNotes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• $note',
                                  style: theme.textTheme.bodyMedium),
                            ),
                        ],
                        if (move.notePath case final path?)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(path,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
