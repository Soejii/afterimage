import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/recorder_contracts.dart';
import '../domain/setup_models.dart';
import '../presentation/recorder_controller.dart';
import '../services/setup_service.dart';
import 'screens/recorder_screen.dart';
import 'screens/setup_screen.dart';
import 'widgets/afterimage_brand.dart';

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

class _AfterimageHomeShellState extends State<AfterimageHomeShell> {
  late final RecorderController _recorderController;
  late final bool _ownsRecorderController;
  int _selectedIndex = 0;
  bool _isChecking = false;
  SetupReport? _report;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final suppliedController = widget.recorderController;
    _ownsRecorderController = suppliedController == null;
    _recorderController = suppliedController ??
        RecorderController(
          backend: widget.recorderBackend ??
              const UnavailableNativeRecorderBackend(),
        );
    _refreshChecks();
    _recorderController.refreshReadiness();
  }

  @override
  void dispose() {
    if (_ownsRecorderController) {
      _recorderController.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshChecks() async {
    if (_isChecking) {
      return;
    }
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });
    try {
      final report = await widget.setupService.inspect();
      if (!mounted) {
        return;
      }
      setState(() {
        _report = report;
        _isChecking = false;
      });
      _recorderController.setSetupReport(report);
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
                    report: _report,
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
    final page = _selectedIndex == 0
        ? SetupScreen(
            key: const ValueKey('setup-screen'),
            report: _report,
            isRefreshing: _isChecking,
            errorMessage: _errorMessage,
            recorderController: _recorderController,
            onRefresh: _refreshChecks,
            onOpenRecorder: () => _selectPage(1),
          )
        : RecorderScreen(
            key: const ValueKey('recorder-screen'),
            controller: _recorderController,
            report: _report,
            options: _recorderController.options,
            onOptionsChanged: _recorderController.updateOptions,
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: page,
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
            'WORKSPACE',
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
          Text(
            'v0.1.0  ·  alpha',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
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
