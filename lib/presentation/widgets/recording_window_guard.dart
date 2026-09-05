import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../recorder_controller.dart';

/// Keeps a normal window close within the recorder's safe stop lifecycle.
class RecordingWindowGuard extends StatefulWidget {
  const RecordingWindowGuard(
      {super.key, required this.controller, required this.child});
  final RecorderController controller;
  final Widget child;

  @override
  State<RecordingWindowGuard> createState() => _RecordingWindowGuardState();
}

class _RecordingWindowGuardState extends State<RecordingWindowGuard>
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
      if (controller.isBusy) {
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
