import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/theme.dart';
import '../../domain/notes_models.dart';

abstract interface class NotesClipPlayerSession {
  Stream<Duration> get position;

  Stream<Duration> get duration;

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> setRate(double rate);

  Future<void> setLoop(bool loop);

  Future<Duration> currentPosition();

  Widget buildVideo(BuildContext context);

  Future<void> dispose();
}

typedef NotesClipPlayerSessionFactory = NotesClipPlayerSession Function(
  String path,
);

NotesClipPlayerSession createMediaKitClipPlayer(String path) =>
    MediaKitNotesClipPlayerSession(path);

/// A small seam around media_kit. Tests can provide a fake session and never
/// initialize libmpv.
class MediaKitNotesClipPlayerSession implements NotesClipPlayerSession {
  MediaKitNotesClipPlayerSession(String path) : _player = Player() {
    _videoController = VideoController(_player);
    _ready = _open(path);
  }

  final Player _player;
  late final VideoController _videoController;
  late final Future<void> _ready;

  Future<void> _open(String path) async {
    if (!await File(path).exists()) {
      throw StateError('The clip file is no longer available.');
    }
    await _player.open(Media(path), play: false);
    await _player.setVolume(0);
  }

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Future<void> play() async {
    await _ready;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _ready;
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _ready;
    await _player.seek(position);
  }

  @override
  Future<void> setRate(double rate) async {
    await _ready;
    await _player.setRate(rate);
  }

  @override
  Future<void> setLoop(bool loop) async {
    await _ready;
    await _player.setPlaylistMode(
      loop ? PlaylistMode.single : PlaylistMode.none,
    );
  }

  @override
  Future<Duration> currentPosition() async {
    await _ready;
    return _player.state.position;
  }

  @override
  Widget buildVideo(BuildContext context) =>
      Video(controller: _videoController);

  @override
  Future<void> dispose() => _player.dispose();
}

class NotesClipPlayer extends StatefulWidget {
  const NotesClipPlayer({
    super.key,
    required this.clip,
    required this.filePath,
    this.playerFactory = createMediaKitClipPlayer,
    this.pauseRequested = false,
    this.onStarted,
    this.playerCardKey,
  });

  final NoteClip clip;
  final String filePath;
  final NotesClipPlayerSessionFactory playerFactory;
  final bool pauseRequested;
  final VoidCallback? onStarted;
  final Key? playerCardKey;

  @override
  State<NotesClipPlayer> createState() => _NotesClipPlayerState();
}

class _NotesClipPlayerState extends State<NotesClipPlayer> {
  NotesClipPlayerSession? _session;
  bool _started = false;
  bool _unavailable = false;
  bool _loop = true;
  double _rate = 1;

  @override
  void didUpdateWidget(covariant NotesClipPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      final session = _session;
      if (session != null) unawaited(_disposeSession(session));
      _session = null;
      _started = false;
      _unavailable = false;
    }
    if (widget.pauseRequested && !oldWidget.pauseRequested) {
      final session = _session;
      if (session != null) unawaited(_pauseSession(session));
      if (mounted) setState(() => _started = false);
    }
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) unawaited(_disposeSession(session));
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final session = await _ensureSession();
      if (session == null) return;
      await session.setRate(_rate);
      await session.setLoop(_loop);
      await session.play();
      if (!mounted) return;
      setState(() => _started = true);
      widget.onStarted?.call();
    } on Object {
      _showUnavailable();
    }
  }

  Future<void> _pause() async {
    try {
      await _session?.pause();
      if (mounted) setState(() => _started = false);
    } on Object {
      _showUnavailable();
    }
  }

  Future<void> _pauseSession(NotesClipPlayerSession session) async {
    try {
      await session.pause();
    } on Object {
      if (mounted && identical(_session, session)) _showUnavailable();
    }
  }

  Future<void> _restart() async {
    try {
      final session = await _ensureSession();
      if (session == null) return;
      await session.seek(Duration.zero);
      await session.play();
      if (mounted) {
        setState(() => _started = true);
        widget.onStarted?.call();
      }
    } on Object {
      _showUnavailable();
    }
  }

  Future<void> _step(int frames) async {
    final session = _session;
    if (session == null || _started) return;
    try {
      final current = await session.currentPosition();
      final next = current + Duration(microseconds: frames * 16667);
      await session.seek(next < Duration.zero ? Duration.zero : next);
    } on Object {
      _showUnavailable();
    }
  }

  Future<void> _setRate(double? rate) async {
    if (rate == null) return;
    _rate = rate;
    try {
      await _session?.setRate(rate);
      if (mounted) setState(() {});
    } on Object {
      _showUnavailable();
    }
  }

  Future<void> _setLoop(bool value) async {
    _loop = value;
    try {
      await _session?.setLoop(value);
      if (mounted) setState(() {});
    } on Object {
      _showUnavailable();
    }
  }

  Future<NotesClipPlayerSession?> _ensureSession() async {
    final current = _session;
    if (current != null) return current;
    if (!await File(widget.filePath).exists()) {
      _showUnavailable();
      return null;
    }
    final session = widget.playerFactory(widget.filePath);
    _session = session;
    return session;
  }

  void _showUnavailable() {
    final session = _session;
    _session = null;
    _started = false;
    if (session != null) unawaited(_disposeSession(session));
    if (mounted) setState(() => _unavailable = true);
  }

  Future<void> _disposeSession(NotesClipPlayerSession session) async {
    try {
      await session.dispose();
    } on Object {
      // A failed player cleanup must not surface as an unhandled UI future.
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _disposeIfOffscreen();
    });
    return false;
  }

  void _disposeIfOffscreen() {
    final child = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (child is! RenderBox || viewport is! RenderBox) return;
    final childRect = child.localToGlobal(Offset.zero) & child.size;
    final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;
    if (childRect.overlaps(viewportRect)) return;
    final session = _session;
    if (session == null) return;
    unawaited(_disposeSession(session));
    _session = null;
    if (mounted) setState(() => _started = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: Card(
        key: widget.playerCardKey ?? const ValueKey('clip-player'),
        margin: const EdgeInsets.only(top: 12),
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: _unavailable
                      ? Center(
                          child: Text(
                            'Clip unavailable',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : _started && session != null
                          ? session.buildVideo(context)
                          : _poster(theme),
                ),
              ),
              const SizedBox(height: 8),
              if (session != null)
                StreamBuilder<Duration>(
                  stream: session.position,
                  initialData: Duration.zero,
                  builder: (context, snapshot) {
                    return StreamBuilder<Duration>(
                      stream: session.duration,
                      initialData: Duration.zero,
                      builder: (context, durationSnapshot) {
                        final duration = durationSnapshot.data ?? Duration.zero;
                        final position = snapshot.data ?? Duration.zero;
                        final max = duration.inMicroseconds.toDouble();
                        final value = max <= 0
                            ? 0.0
                            : position.inMicroseconds.clamp(0, max).toDouble();
                        return LinearProgressIndicator(
                          value: max <= 0 ? null : value / max,
                          minHeight: 3,
                        );
                      },
                    );
                  },
                ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                runSpacing: 3,
                children: [
                  IconButton(
                    key: const ValueKey('clip-play'),
                    tooltip: 'Play clip',
                    onPressed: _start,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('clip-pause'),
                    tooltip: 'Pause clip',
                    onPressed: session == null ? null : _pause,
                    icon: const Icon(Icons.pause_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('clip-restart'),
                    tooltip: 'Restart clip',
                    onPressed: _restart,
                    icon: const Icon(Icons.replay_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('clip-step-back'),
                    tooltip: 'One frame back',
                    onPressed:
                        session == null || _started ? null : () => _step(-1),
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('clip-step-forward'),
                    tooltip: 'One frame forward',
                    onPressed:
                        session == null || _started ? null : () => _step(1),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  DropdownButton<double>(
                    value: _rate,
                    underline: const SizedBox.shrink(),
                    onChanged: _setRate,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1x')),
                      DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                      DropdownMenuItem(value: 0.25, child: Text('0.25x')),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _loop,
                        onChanged: _setLoop,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text(
                        'Loop',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster(ThemeData theme) {
    final poster = widget.clip.poster;
    final path = poster == null || poster.isEmpty
        ? null
        : _joinPath(File(widget.filePath).parent.path, poster);
    return Container(
      color: AfterimageTheme.canvas,
      alignment: Alignment.center,
      child: path == null
          ? Icon(
              Icons.movie_outlined,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.movie_outlined,
                size: 42,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

String _joinPath(String base, String child) {
  if (child.isEmpty) return base;
  if (child.startsWith('/') || child.startsWith('\\')) return child;
  if (base.endsWith('/') || base.endsWith('\\')) return '$base$child';
  return '$base${Platform.pathSeparator}$child';
}
