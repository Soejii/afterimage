import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../replay_timeline.dart';

/// The per-replay timeline for a batch, live or finished.
///
/// A long batch is the whole point of Afterimage, so this is virtualised and
/// keeps the active replay in view. A dense counts line sits above it, because
/// the list alone answers "what is happening" but not "how much is left", and a
/// 200-replay batch is mostly rows saying "waiting".
class ReplayList extends StatefulWidget {
  const ReplayList({
    super.key,
    required this.rows,
    this.maxHeight = 260,
  });

  final List<ReplayRow> rows;
  final double maxHeight;

  @override
  State<ReplayList> createState() => _ReplayListState();
}

class _ReplayListState extends State<ReplayList> {
  static const double _rowExtent = 38;
  final ScrollController _scrollController = ScrollController();
  int? _lastActiveIndex;

  @override
  void didUpdateWidget(ReplayList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followActiveRow();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _followActiveRow() {
    int? found;
    for (final row in widget.rows) {
      if (row.status == ReplayRowStatus.active) {
        found = row.index;
        break;
      }
    }
    final active = found;
    if (active == null || active == _lastActiveIndex) {
      return;
    }
    _lastActiveIndex = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      // Keep the active row roughly a third of the way down, so the user can
      // see both what just finished and what is coming.
      final target = ((active - 1) * _rowExtent) - (widget.maxHeight / 3);
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountsLine(rows: widget.rows),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AfterimageTheme.canvas.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AfterimageTheme.hairline),
            ),
            child: ListView.builder(
              key: const ValueKey('replay-timeline'),
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemExtent: _rowExtent,
              itemCount: widget.rows.length,
              itemBuilder: (context, position) =>
                  _ReplayRowTile(row: widget.rows[position]),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountsLine extends StatelessWidget {
  const _CountsLine({required this.rows});

  final List<ReplayRow> rows;

  @override
  Widget build(BuildContext context) {
    int count(ReplayRowStatus status) =>
        rows.where((row) => row.status == status).length;
    final done = count(ReplayRowStatus.done);
    final failed = count(ReplayRowStatus.failed);
    final stopped = count(ReplayRowStatus.stopped);
    final pending = count(ReplayRowStatus.pending);

    final parts = <String>[
      '$done saved',
      if (failed > 0) '$failed failed',
      if (stopped > 0) '$stopped stopped',
      if (pending > 0) '$pending to go',
    ];

    return Text(
      parts.join(' · '),
      key: const ValueKey('replay-counts'),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _ReplayRowTile extends StatelessWidget {
  const _ReplayRowTile({required this.row});

  final ReplayRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (row.status) {
      ReplayRowStatus.done => (
          Icons.check_circle_outline,
          AfterimageTheme.ready,
          'Saved',
        ),
      ReplayRowStatus.failed => (
          Icons.error_outline,
          AfterimageTheme.failed,
          'Failed',
        ),
      ReplayRowStatus.stopped => (
          Icons.stop_circle_outlined,
          AfterimageTheme.blocked,
          'Stopped',
        ),
      ReplayRowStatus.active => (
          Icons.fiber_manual_record,
          AfterimageTheme.recording,
          'Recording now',
        ),
      ReplayRowStatus.pending => (
          Icons.schedule,
          theme.colorScheme.onSurfaceVariant,
          'Waiting',
        ),
    };
    final active = row.status == ReplayRowStatus.active;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 74,
            child: Text(
              'Replay ${row.index}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.detail ?? label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
