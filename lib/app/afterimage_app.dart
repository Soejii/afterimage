import 'package:flutter/material.dart';

import '../domain/recorder_contracts.dart';
import '../presentation/home_shell.dart';
import '../presentation/recorder_controller.dart';
import '../presentation/widgets/recording_window_guard.dart';
import '../services/setup_service.dart';
import 'theme.dart';

class AfterimageApp extends StatelessWidget {
  const AfterimageApp({
    super.key,
    this.setupService = const LocalSetupService(),
    this.recorderBackend,
    this.recorderController,
    this.enableWindowGuard = false,
  });

  final SetupService setupService;
  final NativeRecorderBackend? recorderBackend;
  final RecorderController? recorderController;
  final bool enableWindowGuard;

  @override
  Widget build(BuildContext context) {
    final shell = AfterimageHomeShell(
      setupService: setupService,
      recorderBackend: recorderBackend,
      recorderController: recorderController,
    );
    return MaterialApp(
      title: 'AFTERIMAGE',
      debugShowCheckedModeBanner: false,
      theme: AfterimageTheme.dark(),
      themeMode: ThemeMode.dark,
      home: enableWindowGuard && recorderController != null
          ? RecordingWindowGuard(controller: recorderController!, child: shell)
          : shell,
    );
  }
}
