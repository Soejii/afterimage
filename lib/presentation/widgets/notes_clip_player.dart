import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/theme.dart';
import '../../domain/notes_models.dart';

abstract interface class NotesClipPlayerSession {
  Stream<Duration> get position;

  Stream<Duration> get duration;

  Stream<bool> get playing;

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> setRate(double rate);

  Future<void> setLoop(bool loop);

  Future<Duration> currentPosition();

  /// One decoded frame forward (1) or back (-1). Leaves the player paused.
  Future<void> stepFrame(int direction);

  Widget buildVideo(BuildContext context);

  Future<void> dispose();
}

typedef NotesClipPlayerSessionFactory = NotesClipPlayerSession Function(
  String path,
);

/// Software rendering: the GL texture path drew solid blue on an RX 9060 XT
/// under Wayland. Clips are 1280x720, so the CPU cost is small.
const notesClipVideoConfiguration = VideoControllerConfiguration(
  enableHardwareAcceleration: false,
);

/// The page draws its own play, seek, speed and loop bar.
const notesClipVideoControls = NoVideoControls;

NotesClipPlayerSession createMediaKitClipPlayer(String path) =>
    MediaKitNotesClipPlayerSession(path);

/// A small seam around media_kit. Tests can provide a fake session and never
/// initialize libmpv.
class MediaKitNotesClipPlayerSession implements NotesClipPlayerSession {
  MediaKitNotesClipPlayerSession(String path) : _player = Player() {
    _videoController = VideoController(
      _player,
      configuration: notesClipVideoConfiguration,
    );
    _ready = _open(path);
  }

  final Player _player;
  late final VideoController _videoController;
  late final Future<void> _ready;

  Future<void> _open(String path) async {
    if (!await File(path).exists()) {
      throw StateError('The clip file is no longer available.');
    }
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // Exact seeks, so scrubbing and frame steps land on the frame asked for.
      await platform.setProperty('hr-seek', 'yes');
    }
    await _player.open(Media(path), play: false);
    await _player.setVolume(0);
  }

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<bool> get playing => _player.stream.playing;

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
  Future<void> stepFrame(int direction) async {
    await _ready;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform
          .command([direction < 0 ? 'frame-back-step' : 'frame-step']);
    }
  }

  @override
  Widget buildVideo(BuildContext context) =>
      Video(controller: _videoController, controls: notesClipVideoControls);

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
  static const _seekStep = Duration(seconds: 1);

  final FocusNode _focus = FocusNode(debugLabel: 'clip player');
  NotesClipPlayerSession? _session;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  bool _playing = false;
  bool _unavailable = false;
  bool _loop = true;
  double _rate = 1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragMicros;
  // Bumped whenever the session is closed: an open still in flight is stale.
  int _generation = 0;
  Future<NotesClipPlayerSession?>? _opening;
  // Bumped by every play, pause and outside pause: a pending play is cancelled.
  int _request = 0;

  @override
  void didUpdateWidget(covariant NotesClipPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _closeSession();
      _unavailable = false;
    }
    if (widget.pauseRequested && !oldWidget.pauseRequested) {
      _request++;
      final session = _session;
      // Pause even when not yet playing: a play may be in flight natively.
      if (session != null) unawaited(_pauseSession(session));
      _playing = false;
    }
  }

  @override
  void dispose() {
    _closeSession();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() => _playing ? _pause() : _play();

  Future<void> _play() async {
    final request = ++_request;
    // Claim the page now, so a card clicked later can cancel this start.
    widget.onStarted?.call();
    NotesClipPlayerSession? session;
    bool current() =>
        mounted && request == _request && identical(_session, session);
    try {
      final created = _session == null;
      session = await _ensureSession();
      if (session == null || !current()) return;
      if (created) {
        await session.setRate(_rate);
        await session.setLoop(_loop);
        if (!current()) return;
      }
      if (!_loop &&
          _duration > Duration.zero &&
          _position >= _duration - const Duration(milliseconds: 100)) {
        await session.seek(Duration.zero);
        if (!current()) return;
      }
      await session.play();
      if (!current()) return;
      setState(() => _playing = true);
    } on Object {
      _failed(session);
    }
  }

  Future<void> _pause() async {
    _request++;
    final session = _session;
    try {
      await session?.pause();
      if (mounted) setState(() => _playing = false);
    } on Object {
      _failed(session);
    }
  }

  /// A failing operation only takes down its own session, never a newer one.
  void _failed(NotesClipPlayerSession? session) {
    if (!mounted) return;
    // No session yet: only fail if no newer one has opened since.
    if (session == null ? _session == null : identical(session, _session)) {
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

  Future<void> _step(int direction) async {
    final session = _session;
    if (session == null) return;
    try {
      if (_playing) {
        await session.pause();
        if (mounted) setState(() => _playing = false);
      }
      await session.stepFrame(direction);
    } on Object {
      _failed(session);
    }
  }

  Future<void> _seekTo(Duration target) async {
    final session = _session;
    if (session == null) return;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration
            ? _duration
            : target);
    try {
      await session.seek(clamped);
    } on Object {
      _failed(session);
    }
  }

  Future<void> _setRate(double? rate) async {
    if (rate == null) return;
    _rate = rate;
    final session = _session;
    try {
      await session?.setRate(rate);
      if (mounted) setState(() {});
    } on Object {
      _failed(session);
    }
  }

  Future<void> _setLoop(bool value) async {
    _loop = value;
    final session = _session;
    try {
      await session?.setLoop(value);
      if (mounted) setState(() {});
    } on Object {
      _failed(session);
    }
  }

  Future<NotesClipPlayerSession?> _ensureSession() {
    final current = _session;
    if (current != null) return Future.value(current);
    return _opening ??= _open();
  }

  Future<NotesClipPlayerSession?> _open() async {
    final generation = _generation;
    final path = widget.filePath;
    try {
      final exists = await File(path).exists();
      // Closed, disposed or switched clip while checking: open nothing.
      if (!mounted || generation != _generation) return null;
      if (!exists) {
        _showUnavailable();
        return null;
      }
      final session = widget.playerFactory(path);
      _session = session;
      _positionSubscription = session.position.listen((value) {
        if (mounted) setState(() => _position = value);
      });
      _durationSubscription = session.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
      });
      _playingSubscription = session.playing.listen((value) {
        if (mounted) setState(() => _playing = value);
      });
      return session;
    } finally {
      if (generation == _generation) _opening = null;
    }
  }

  void _closeSession() {
    final session = _session;
    _session = null;
    _generation++;
    _opening = null;
    _request++;
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    _positionSubscription = null;
    _durationSubscription = null;
    _playingSubscription = null;
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _dragMicros = null;
    if (session != null) unawaited(_disposeSession(session));
  }

  void _showUnavailable() {
    _closeSession();
    if (mounted) setState(() => _unavailable = true);
  }

  Future<void> _disposeSession(NotesClipPlayerSession session) async {
    try {
      await session.dispose();
    } on Object {
      // A failed player cleanup must not surface as an unhandled UI future.
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      if (event is KeyDownEvent) unawaited(_togglePlay());
    } else if (key == LogicalKeyboardKey.period) {
      unawaited(_step(1));
    } else if (key == LogicalKeyboardKey.comma) {
      unawaited(_step(-1));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_seekTo(_position + _seekStep));
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekTo(_position - _seekStep));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
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
    if (_session == null) return;
    _closeSession();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    final hasSession = session != null;
    final maxMicros = _duration.inMicroseconds.toDouble();
    final sliderMax = maxMicros > 0 ? maxMicros : 1.0;
    final sliderValue = (_dragMicros ?? _position.inMicroseconds.toDouble())
        .clamp(0.0, sliderMax);
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
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
                        : GestureDetector(
                            key: const ValueKey('clip-surface'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _focus.requestFocus();
                              unawaited(_togglePlay());
                            },
                            child: hasSession
                                ? session.buildVideo(context)
                                : _poster(theme),
                          ),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    key: const ValueKey('clip-seek'),
                    value: sliderValue,
                    max: sliderMax,
                    onChanged: hasSession && maxMicros > 0
                        ? (value) {
                            _focus.requestFocus();
                            setState(() => _dragMicros = value);
                            unawaited(
                              _seekTo(Duration(microseconds: value.round())),
                            );
                          }
                        : null,
                    onChangeEnd: hasSession && maxMicros > 0
                        ? (value) {
                            setState(() => _dragMicros = null);
                            unawaited(
                              _seekTo(Duration(microseconds: value.round())),
                            );
                          }
                        : null,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('clip-play'),
                      tooltip: _playing ? 'Pause (Space)' : 'Play (Space)',
                      onPressed: () {
                        _focus.requestFocus();
                        unawaited(_togglePlay());
                      },
                      icon: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('clip-step-back'),
                      tooltip: 'Previous frame (,)',
                      onPressed: hasSession
                          ? () {
                              _focus.requestFocus();
                              unawaited(_step(-1));
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    IconButton(
                      key: const ValueKey('clip-step-forward'),
                      tooltip: 'Next frame (.)',
                      onPressed: hasSession
                          ? () {
                              _focus.requestFocus();
                              unawaited(_step(1));
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_clock(_dragMicros == null ? _position : Duration(microseconds: _dragMicros!.round()))}'
                      ' / ${_clock(_duration)}',
                      key: const ValueKey('clip-time'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
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
                    IconButton(
                      key: const ValueKey('clip-loop'),
                      tooltip: _loop ? 'Loop on' : 'Loop off',
                      isSelected: _loop,
                      onPressed: () => unawaited(_setLoop(!_loop)),
                      icon: const Icon(Icons.repeat_rounded),
                      selectedIcon: const Icon(Icons.repeat_on_rounded),
                    ),
                  ],
                ),
              ],
            ),
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
    final image = Container(
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
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Center(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0x99000000),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 40,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `0:02.37`: clips are a few seconds long, so hundredths matter.
String _clock(Duration value) {
  final centis = value.inMilliseconds ~/ 10;
  final minutes = centis ~/ 6000;
  final seconds = (centis ~/ 100) % 60;
  final hundredths = centis % 100;
  return '$minutes:${seconds.toString().padLeft(2, '0')}'
      '.${hundredths.toString().padLeft(2, '0')}';
}

String _joinPath(String base, String child) {
  if (child.isEmpty) return base;
  if (child.startsWith('/') || child.startsWith('\\')) return child;
  if (base.endsWith('/') || base.endsWith('\\')) return '$base$child';
  return '$base${Platform.pathSeparator}$child';
}
