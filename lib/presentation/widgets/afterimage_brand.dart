import 'package:flutter/material.dart';

import '../../app/theme.dart';

class AfterimageBrand extends StatelessWidget {
  const AfterimageBrand({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markSize = compact ? 32.0 : 40.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 9 : 12),
            gradient: const LinearGradient(
              colors: [AfterimageTheme.accent, AfterimageTheme.accentStrong],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(
            Icons.blur_on_rounded,
            color: const Color(0xFF0B1A13),
            size: compact ? 21 : 26,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'AFTERIMAGE',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: compact ? 2.2 : 1.8,
                color: Colors.white,
              ),
        ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.ready,
    this.checking = false,
  });

  final bool ready;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final color = ready ? AfterimageTheme.accent : const Color(0xFFFFC67A);
    final label = checking
        ? 'CHECKING'
        : ready
            ? 'READY TO RECORD'
            : 'SETUP REQUIRED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (checking)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: color,
              ),
            )
          else
            Icon(
              ready ? Icons.check_circle_outline : Icons.lock_outline,
              size: 14,
              color: color,
            ),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
          ),
        ],
      ),
    );
  }
}
