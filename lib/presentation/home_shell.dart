import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/recorder_contracts.dart';
import '../services/obs_connection_service.dart';
import '../services/setup_service.dart';
import 'recorder_blocker.dart';
import 'recorder_controller.dart';
import 'screens/workspace_screen.dart';
import 'widgets/obs_connection_card.dart';

class AfterimageHomeShell extends StatefulWidget {
  const AfterimageHomeShell({
    super.key,
    required this.setupService,
    this.recorderBackend,
    this.recorderController,
  });

  final SetupService setupService;
  final NativeRecorderBackend? recorderBackend;
  final RecorderController? recorderController;

  @override
  State<AfterimageHomeShell> createState() => _AfterimageHomeShellState();
}

class _AfterimageHomeShellState extends State<AfterimageHomeShell>
    with WidgetsBindingObserver {
  /// How often to re-check while the user is being asked to change something
  /// in OBS.
  ///
  /// Afterimage reads OBS's configuration file rather than being told about it,
  /// so nothing informs the application when the user switches the WebSocket
  /// server on. Without this poll they would have to find a "check again"
  /// button after doing exactly what they were asked, which is the moment
  /// people decide an application is broken.
  static const _obsPollInterval = Duration(seconds: 3);

  late final RecorderController _recorderController;
  late final bool _ownsRecorderController;
  Timer? _obsPoll;
  bool _isChecking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final suppliedController = widget.recorderController;
    _ownsRecorderController = suppliedController == null;
    _recorderController = suppliedController ??
        RecorderController(
          backend: widget.recorderBackend ??
              const UnavailableNativeRecorderBackend(),
          setupInspector: widget.setupService.inspect,
        );
    _recorderController.setupInspector ??= widget.setupService.inspect;
    _recorderController.addListener(_onControllerChanged);
    unawaited(_recorderController.initialize());
    unawaited(_refreshChecks());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _obsPoll?.cancel();
    _recorderController.removeListener(_onControllerChanged);
    if (_ownsRecorderController) {
      _recorderController.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_recorderController.isBusy) {
      unawaited(_refreshChecks());
    }
  }

  void _onControllerChanged() => _syncObsPoll();

  /// Runs the poll only while the user is actually waiting on OBS.
  void _syncObsPoll() {
    final waitingOnObs = !_recorderController.isBusy &&
        _recorderController.leadBlocker?.id == RecorderBlockerId.obsConnection;
    if (waitingOnObs && _obsPoll == null) {
      _obsPoll = Timer.periodic(_obsPollInterval, (_) {
        if (!_isChecking && !_recorderController.isBusy) {
          unawaited(_refreshChecks());
        }
      });
    } else if (!waitingOnObs && _obsPoll != null) {
      _obsPoll?.cancel();
      _obsPoll = null;
    }
  }

  Future<void> _refreshChecks() async {
    if (_isChecking || _recorderController.isBusy) {
      return;
    }
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });
    try {
      _recorderController.setupInspector ??= widget.setupService.inspect;
      await _recorderController.refreshAllReadiness();
      if (!mounted) {
        return;
      }
      setState(() => _isChecking = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isChecking = false;
        _errorMessage = 'The local checks could not be completed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = _recorderController.obsConnection;
    return Scaffold(
      body: SafeArea(
        child: connection == null
            ? _workspace(null)
            : AnimatedBuilder(
                animation: connection,
                builder: (context, _) => _workspace(connection),
              ),
      ),
    );
  }

  Widget _workspace(ObsConnectionService? connection) {
    return WorkspaceScreen(
      controller: _recorderController,
      isRefreshing: _isChecking || _recorderController.isBusy,
      onRefresh: _refreshChecks,
      // `controller.error` covers failures raised before the engine starts,
      // such as an output folder that fails preflight. Dropping it here left
      // the user on a green READY screen with a Start button that silently
      // did nothing.
      // Only the shell's own check failure is passed down. Anything derived
      // from the controller has to be read inside WorkspaceScreen's listener,
      // because this method runs in the shell's build and does not rebuild
      // when the controller notifies.
      errorMessage: _errorMessage,
      obsConnectionCard:
          connection == null ? null : _obsConnectionCard(connection),
    );
  }

  Widget _obsConnectionCard(ObsConnectionService connection) {
    final result = connection.result;
    final busy = _recorderController.isBusy;
    return ObsConnectionCard(
      isChecking: connection.isChecking || busy,
      connected: result?.ready ?? false,
      detail: result?.detail,
      host: result?.config?.host,
      port: result?.config?.port,
      stage: connection.stage,
      onConnect: busy
          ? null
          : ({password, port}) async {
              await connection.connect(password: password, port: port);
              if (connection.result?.ready == true &&
                  !_recorderController.isBusy) {
                await _refreshChecks();
              }
            },
      onUseAutomatic: busy
          ? null
          : () async {
              await connection.useAutomaticConnection();
              if (connection.result?.ready == true &&
                  !_recorderController.isBusy) {
                await _refreshChecks();
              }
            },
      previewBytes: connection.previewBytes,
      previewSceneName: connection.previewSceneName,
      previewError: connection.previewError,
      isRefreshingPreview: connection.isChecking || busy,
      onRefreshPreview: busy ? null : connection.refreshPreview,
    );
  }
}
