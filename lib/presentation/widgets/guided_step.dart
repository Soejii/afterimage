import 'package:flutter/material.dart';

import '../../app/theme.dart';

enum GuidedStepStatus {
  current,
  ready,
  pending,
}

class GuidedStep extends StatelessWidget {
  const GuidedStep({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.child,
    this.action,
  });

  final int number;
  final String title;
  final String subtitle;
  final GuidedStepStatus status;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      GuidedStepStatus.ready => AfterimageTheme.accent,
      GuidedStepStatus.current => const Color(0xFFFFC67A),
      GuidedStepStatus.pending => Theme.of(context).colorScheme.outline,
    };
    final icon = switch (status) {
      GuidedStepStatus.ready => Icons.check_rounded,
      GuidedStepStatus.current => Icons.arrow_forward_rounded,
      GuidedStepStatus.pending => Icons.more_horiz_rounded,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: status == GuidedStepStatus.pending
                      ? Text(
                          '$number',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w800,
                                  ),
                        )
                      : Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 12),
                  action!,
                ],
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}
