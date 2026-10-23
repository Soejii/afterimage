import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../recorder_controller.dart';

/// Keeps a normal window close within the recorder's safe stop lifecycle.
class RecordingWindowGuard extends StatefulWidget {
  const RecordingWindowGuard({
    super.key,
    required this.controller,
    required this.child,
    this.notesEditing = false,
    this.notesSaving = false,
  });
  final RecorderController controller;
  final Widget child;
  final bool notesEditing;
  final bool notesSaving;

  @override
  State<RecordingWindowGuard> createState() => RecordingWindowGuardState();
}

class RecordingWindowGuardState extends State<RecordingWindowGuard>
    with WindowListener {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    if (!widget.controller.isBusy && !_closing) {
      unawaited(
          widget.controller.refreshAllReadiness().catchError((Object _) {}));
    }
  }

  @override
  void onWindowClose() {
    unawaited(_close());
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final controller = widget.controller;
      if (widget.notesEditing || widget.notesSaving) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard your unsaved edit?'),
            content: const Text(
                'Afterimage will close without keeping the current notes edit.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard edit and close'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      } else if (controller.isBusy) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Stop recording and quit?'),
            content: const Text(
                'Afterimage will finish saving the current recording before closing.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep recording')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Stop and quit')),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        await controller.stopAndWait();
        if (controller.error != null && mounted) {
          await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                    title: const Text('Check your recording before closing'),
                    content: Text(
                        '${controller.error}\n\nAfterimage is staying open so you can check OBS and your output folder.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Keep app open'))
                    ],
                  ));
          return;
        }
      }
      await controller.preferences?.flush();
      await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
