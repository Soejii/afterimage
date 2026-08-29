import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/setup_models.dart';

class SetupCheckTile extends StatelessWidget {
  const SetupCheckTile({
    super.key,
    required this.check,
  });

  final SetupCheck check;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AfterimageTheme.panelRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_checkIcon, color: statusColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        check.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (check.required)
                      Text(
                        'REQUIRED',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  check.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color get _statusColor {
    switch (check.status) {
      case SetupCheckStatus.ready:
        return AfterimageTheme.accent;
      case SetupCheckStatus.blocked:
        return const Color(0xFFFFC67A);
      case SetupCheckStatus.notice:
        return const Color(0xFF91B8FF);
    }
  }

  IconData get _checkIcon {
    switch (check.status) {
      case SetupCheckStatus.ready:
        return Icons.check_rounded;
      case SetupCheckStatus.blocked:
        return Icons.lock_outline_rounded;
      case SetupCheckStatus.notice:
        return Icons.info_outline_rounded;
    }
  }
}
