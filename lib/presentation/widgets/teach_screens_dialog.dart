import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/recorder_contracts.dart';
import '../../services/bmp_image.dart';
import '../recorder_controller.dart';

Future<void> showTeachScreensDialog(
  BuildContext context,
  RecorderController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TeachScreensDialog(controller: controller),
  );
}

class _TeachScreensDialog extends StatefulWidget {
  const _TeachScreensDialog({required this.controller});

  final RecorderController controller;

  @override
  State<_TeachScreensDialog> createState() => _TeachScreensDialogState();
}

class _TeachScreensDialogState extends State<_TeachScreensDialog> {
  final Map<ScreenCheck, RgbImage?> _images = {};
  final Set<ScreenCheck> _taught = {};
  final Set<ScreenCheck> _capturing = {};
  final Set<ScreenCheck> _capturedSinceOpen = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadReferences());
  }

  Future<void> _loadReferences() async {
    for (final check in ScreenCheck.values) {
      final image = await widget.controller.readScreenReference(check);
      if (!mounted) return;
      if (_capturing.contains(check) || _capturedSinceOpen.contains(check)) {
        continue;
      }
      setState(() {
        _images[check] = image;
        if (image == null) {
          _taught.remove(check);
        } else {
          _taught.add(check);
        }
      });
    }
  }

  Future<void> _capture(ScreenCheck check) async {
    if (_capturing.contains(check)) return;
    setState(() {
      _capturing.add(check);
      _error = null;
    });
    try {
      final image = await widget.controller.teachScreen(check);
      if (!mounted) return;
      setState(() {
        _images[check] = image;
        _taught.add(check);
        _capturedSinceOpen.add(check);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _capturing.remove(check));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('teach-screens-dialog'),
      title: const Text('Teach screens'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScreenTeachingStep(
                check: ScreenCheck.replayList,
                number: '1',
                instruction:
                    'In GGST, open Saved Replays so the replay list shows, then select Capture.',
                image: _images[ScreenCheck.replayList],
                taught: _taught.contains(ScreenCheck.replayList),
                capturing: _capturing.contains(ScreenCheck.replayList),
                onCapture: () => unawaited(_capture(ScreenCheck.replayList)),
              ),
              const SizedBox(height: 12),
              _ScreenTeachingStep(
                check: ScreenCheck.replayMenuViewHighlighted,
                number: '2',
                instruction: 'In GGST, press confirm once so the replay MENU '
                    'opens with View Replay highlighted, then select Capture. '
                    'Close that menu in GGST before starting.',
                image: _images[ScreenCheck.replayMenuViewHighlighted],
                taught: _taught.contains(
                  ScreenCheck.replayMenuViewHighlighted,
                ),
                capturing: _capturing.contains(
                  ScreenCheck.replayMenuViewHighlighted,
                ),
                onCapture: () => unawaited(
                  _capture(ScreenCheck.replayMenuViewHighlighted),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _ScreenTeachingStep extends StatelessWidget {
  const _ScreenTeachingStep({
    required this.check,
    required this.number,
    required this.instruction,
    required this.image,
    required this.taught,
    required this.capturing,
    required this.onCapture,
  });

  final ScreenCheck check;
  final String number;
  final String instruction;
  final RgbImage? image;
  final bool taught;
  final bool capturing;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Step $number',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(instruction),
            const SizedBox(height: 10),
            if (image == null)
              Container(
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('No screen captured'),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 96,
                  child: CustomPaint(
                    painter: _RgbImagePainter(image!),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    key: ValueKey('teach-state-${check.name}'),
                    taught ? 'Taught' : 'Not taught',
                  ),
                ),
                OutlinedButton.icon(
                  key: ValueKey(switch (check) {
                    ScreenCheck.replayList => 'teach-replay-list',
                    ScreenCheck.replayMenuViewHighlighted =>
                      'teach-replay-menu',
                  }),
                  onPressed: capturing ? null : onCapture,
                  icon: capturing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: Text(capturing ? 'Capturing…' : 'Capture'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RgbImagePainter extends CustomPainter {
  const _RgbImagePainter(this.image);

  final RgbImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final pixelWidth = size.width / image.width;
    final pixelHeight = size.height / image.height;
    final paint = Paint();
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 3;
        paint.color = Color.fromARGB(
          255,
          image.rgb[offset],
          image.rgb[offset + 1],
          image.rgb[offset + 2],
        );
        canvas.drawRect(
          Rect.fromLTWH(
            x * pixelWidth,
            y * pixelHeight,
            pixelWidth + 0.1,
            pixelHeight + 0.1,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RgbImagePainter oldDelegate) =>
      !identical(image, oldDelegate.image);
}
