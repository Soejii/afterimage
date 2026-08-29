import 'package:flutter/material.dart';

import '../domain/recorder_contracts.dart';
import '../presentation/home_shell.dart';
import '../presentation/recorder_controller.dart';
import '../services/setup_service.dart';
import 'theme.dart';

class AfterimageApp extends StatelessWidget {
  const AfterimageApp({
    super.key,
    this.setupService = const LocalSetupService(),
    this.recorderBackend,
    this.recorderController,
  });

  final SetupService setupService;
  final NativeRecorderBackend? recorderBackend;
  final RecorderController? recorderController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AFTERIMAGE',
      debugShowCheckedModeBanner: false,
      theme: AfterimageTheme.dark(),
      themeMode: ThemeMode.dark,
      home: AfterimageHomeShell(
        setupService: setupService,
        recorderBackend: recorderBackend,
        recorderController: recorderController,
      ),
    );
  }
}
