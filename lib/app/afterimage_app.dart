import 'package:flutter/material.dart';

import '../domain/recorder_contracts.dart';
import '../domain/finder_contracts.dart';
import '../presentation/home_shell.dart';
import '../presentation/recorder_controller.dart';
import '../services/setup_service.dart';
import '../services/notes_repository.dart';
import 'theme.dart';

class AfterimageApp extends StatelessWidget {
  const AfterimageApp({
    super.key,
    this.setupService = const LocalSetupService(),
    this.recorderBackend,
    this.recorderController,
    this.finder,
    this.notesRepository,
    this.enableWindowGuard = false,
  });

  final SetupService setupService;
  final NativeRecorderBackend? recorderBackend;
  final RecorderController? recorderController;
  final FinderPort? finder;
  final NotesRepository? notesRepository;
  final bool enableWindowGuard;

  @override
  Widget build(BuildContext context) {
    final shell = AfterimageHomeShell(
      setupService: setupService,
      recorderBackend: recorderBackend,
      recorderController: recorderController,
      finder: finder,
      notesRepository: notesRepository,
      enableWindowGuard: enableWindowGuard,
    );
    return MaterialApp(
      title: 'AFTERIMAGE',
      debugShowCheckedModeBanner: false,
      theme: AfterimageTheme.dark(),
      themeMode: ThemeMode.dark,
      home: shell,
    );
  }
}
