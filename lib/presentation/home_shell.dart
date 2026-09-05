import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/recorder_contracts.dart';
import '../domain/setup_models.dart';
import '../presentation/recorder_controller.dart';
import '../services/obs_connection_service.dart';
import '../services/setup_service.dart';
import 'screens/recorder_screen.dart';
import 'screens/setup_screen.dart';
import 'widgets/afterimage_brand.dart';
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
  late final RecorderController _recorderController;
  late final bool _ownsRecorderController;
  int _selectedIndex = 0;
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
          enforceGuidedChecks: true,
          setupInspector: widget.setupService.inspect,
        );
    _recorderController.setupInspector ??= widget.setupService.inspect;
    _selectedIndex = _recorderController.recentOutputPaths.isNotEmpty ? 1 : 0;
    unawaited(_recorderController.initialize());
    unawaited(_refreshChecks());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      setState(() {
        _isChecking = false;
      });
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

  void _selectPage(int index) {
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 800;
            if (desktop) {
              return Row(
                children: [
                  _DesktopSidebar(
                    selectedIndex: _selectedIndex,
                    report: _recorderController.setupReport,
                    recorderController: _recorderController,
                    onSelected: _selectPage,
                  ),
                  Expanded(child: _content()),
                ],
              );
            }
            return Column(
              children: [
                const _CompactTopBar(),
                Expanded(child: _content()),
                _CompactNavigation(
                  selectedIndex: _selectedIndex,
                  onSelected: _selectPage,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _content() {
    final page = _selectedIndex == 0 ? _setupPage() : _recorderPage();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: page,
    );
  }

  Widget _setupPage() {
    final connection = _recorderController.obsConnection;
    return AnimatedBuilder(
      animation: _recorderController,
      builder: (context, _) {
        final page = _buildSetupPage(connection);
        if (connection == null) {
          return page;
        }
        return AnimatedBuilder(
          animation: connection,
          builder: (context, _) => _buildSetupPage(connection),
        );
      },
    );
  }

  Widget _buildSetupPage(ObsConnectionService? connection) {
    final currentReport = _recorderController.setupReport;
    final page = SetupScreen(
      key: const ValueKey('setup-screen'),
      report: currentReport,
      isRefreshing: _isChecking || _recorderController.isBusy,
      errorMessage: _errorMessage ??
          _recorderController.preferenceNotice ??
          _recorderController.error?.toString(),
      recorderController: _recorderController,
      isBusy: _recorderController.isBusy,
      obsConnectionCard:
          connection == null ? null : _obsConnectionCard(connection),
      obsConnected: connection?.result?.ready ??
          (currentReport?.checkFor(SetupCheckId.obsWebSocket)?.isReady ??
              false),
      pictureAndSoundConfirmed: _recorderController.pictureAndSoundConfirmed,
      onPictureAndSoundChanged: _recorderController.confirmPictureAndSound,
      replayListPrepared: _recorderController.replayListPrepared,
      onReplayListPreparedChanged: _recorderController.setReplayListPrepared,
      onBrowseGameDirectory: _recorderController.browseGameDirectory,
      onBrowseReplayDirectory: _recorderController.browseReplayDirectory,
      onUseAutomaticLocations: _recorderController.useAutomaticLocations,
      onOpenTestRecorder: _openTestRecorder,
      onOpenObsDownload: _recorderController.openObsDownload,
      onRefresh: _refreshChecks,
      onOpenRecorder: () => _selectPage(1),
    );
    return page;
  }

  Widget _recorderPage() {
    return RecorderScreen(
      key: const ValueKey('recorder-screen'),
      controller: _recorderController,
      report: _recorderController.setupReport,
      options: _recorderController.options,
      onOptionsChanged: _recorderController.updateOptions,
    );
  }

  void _openTestRecorder() {
    if (!_recorderController.isBusy) {
      _recorderController.updateOptions(
        _recorderController.options.copyWith(
          replayCount: ReplayCountOption.one,
        ),
      );
    }
    _selectPage(1);
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
      onConnect: busy
          ? null
          : ({password, port}) async {
              if (password != null || port != null) {
                _recorderController.confirmPictureAndSound(false);
              }
              await connection.connect(password: password, port: port);
              if (connection.result?.ready == true &&
                  !_recorderController.isBusy) {
                await _refreshChecks();
              }
            },
      onUseAutomatic: busy
          ? null
          : () async {
              _recorderController.confirmPictureAndSound(false);
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

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.report,
    required this.recorderController,
    required this.onSelected,
  });

  final int selectedIndex;
  final SetupReport? report;
  final RecorderController recorderController;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF111718),
        border: Border(
          right: BorderSide(color: Color(0xFF26302F)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AfterimageBrand(),
          const SizedBox(height: 46),
          Text(
            'YOUR WORKSPACE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
          ),
          const SizedBox(height: 10),
          _NavItem(
            key: const ValueKey('nav-setup'),
            icon: Icons.tune_rounded,
            label: 'Setup',
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          _NavItem(
            key: const ValueKey('nav-recorder'),
            icon: Icons.fiber_manual_record_outlined,
            label: 'Recorder',
            selected: selectedIndex == 1,
            onTap: () => onSelected(1),
          ),
          const Spacer(),
          _SidebarStatus(
            report: report,
            recorderController: recorderController,
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AfterimageTheme.accent
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? const Color(0xFF20372E) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 13),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarStatus extends StatelessWidget {
  const _SidebarStatus({
    required this.report,
    required this.recorderController,
  });

  final SetupReport? report;
  final RecorderController recorderController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: recorderController,
      builder: (context, _) => _buildStatus(context),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final ready = recorderController.canStart;
    final color = ready ? AfterimageTheme.accent : const Color(0xFFFFC67A);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.lock_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              ready ? 'Ready to record' : 'Recording locked',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactTopBar extends StatelessWidget {
  const _CompactTopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF26302F))),
      ),
      child: const AfterimageBrand(compact: true),
    );
  }
}

class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: const [
        NavigationDestination(
          key: ValueKey('compact-nav-setup'),
          icon: Icon(Icons.tune_rounded),
          label: 'Setup',
        ),
        NavigationDestination(
          key: ValueKey('compact-nav-recorder'),
          icon: Icon(Icons.fiber_manual_record_outlined),
          label: 'Recorder',
        ),
      ],
    );
  }
}
