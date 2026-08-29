import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/setup_models.dart';
import '../recorder_controller.dart';
import '../widgets/afterimage_brand.dart';
import '../widgets/section_card.dart';
import '../widgets/setup_check_tile.dart';

class SetupScreen extends StatelessWidget {
  const SetupScreen({
    super.key,
    required this.report,
    required this.isRefreshing,
    required this.errorMessage,
    this.recorderController,
    required this.onRefresh,
    required this.onOpenRecorder,
  });

  final SetupReport? report;
  final bool isRefreshing;
  final String? errorMessage;
  final RecorderController? recorderController;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenRecorder;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SetupHeading(
                report: report,
                recorderController: recorderController,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh,
                onOpenRecorder: onOpenRecorder,
              ),
              const SizedBox(height: 26),
              if (errorMessage != null) ...[
                _ErrorNotice(message: errorMessage!),
                const SizedBox(height: 16),
              ],
              if (report == null)
                const _LoadingChecks()
              else ...[
                _CheckSummary(report: report!),
                const SizedBox(height: 16),
                _ChecksGrid(report: report!),
                const SizedBox(height: 16),
                const _SelfContainedNotice(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupHeading extends StatelessWidget {
  const _SetupHeading({
    required this.report,
    required this.recorderController,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onOpenRecorder,
  });

  final SetupReport? report;
  final RecorderController? recorderController;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenRecorder;

  @override
  Widget build(BuildContext context) {
    final controller = recorderController;
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _buildHeading(context),
      );
    }
    return _buildHeading(context);
  }

  Widget _buildHeading(BuildContext context) {
    final canRecord =
        recorderController?.canStart ?? report?.canRecord ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 620;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Workspace setup',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'A quick local check before Afterimage touches a game or recording.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('refresh-checks'),
              onPressed: isRefreshing ? null : onRefresh,
              icon: isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(isRefreshing ? 'Checking…' : 'Refresh checks'),
            ),
            FilledButton.icon(
              key: const ValueKey('open-recorder'),
              onPressed: onOpenRecorder,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Open recorder'),
            ),
          ],
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: 18),
              actions,
              const SizedBox(height: 14),
              StatusPill(ready: canRecord, checking: isRefreshing),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                actions,
                const SizedBox(height: 12),
                StatusPill(ready: canRecord, checking: isRefreshing),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CheckSummary extends StatelessWidget {
  const _CheckSummary({required this.report});

  final SetupReport report;

  @override
  Widget build(BuildContext context) {
    final blockers = report.blockingChecks.length;
    final message = blockers == 0
        ? 'All required local checks are ready.'
        : '$blockers required ${blockers == 1 ? 'check is' : 'checks are'} blocking recording.';
    final color =
        blockers == 0 ? AfterimageTheme.accent : const Color(0xFFFFC67A);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            blockers == 0 ? Icons.check_circle_outline : Icons.lock_outline,
            color: color,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Text(
            '${report.checks.length} checks',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color.withValues(alpha: 0.85),
                ),
          ),
        ],
      ),
    );
  }
}

class _ChecksGrid extends StatelessWidget {
  const _ChecksGrid({required this.report});

  final SetupReport report;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: report.checks.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 132,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => SetupCheckTile(
            check: report.checks[index],
          ),
        );
      },
    );
  }
}

class _SelfContainedNotice extends StatelessWidget {
  const _SelfContainedNotice();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Designed for a simple install',
      subtitle:
          'The eventual release should feel like a desktop utility, not a developer setup.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AfterimageTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: AfterimageTheme.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              'No Python install is needed. Afterimage releases will be self-contained and will check their own native dependencies before recording.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingChecks extends StatelessWidget {
  const _LoadingChecks();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Checking this computer',
      subtitle:
          'Afterimage is reading local status only. Nothing is installed or changed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 15),
          Text(
            'Looking for GGST, OBS, and replay files…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC67A).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFC67A).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC67A)),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
