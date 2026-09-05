import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The tone a status surface carries.
enum StatusTone { ready, blocked, failed, recording }

extension StatusToneColors on StatusTone {
  Color get color {
    switch (this) {
      case StatusTone.ready:
        return AfterimageTheme.ready;
      case StatusTone.blocked:
        return AfterimageTheme.blocked;
      case StatusTone.failed:
        return AfterimageTheme.failed;
      case StatusTone.recording:
        return AfterimageTheme.recording;
    }
  }

  Color get textColor {
    switch (this) {
      case StatusTone.ready:
        return AfterimageTheme.readyText;
      case StatusTone.blocked:
        return AfterimageTheme.blockedText;
      case StatusTone.failed:
        return AfterimageTheme.failedText;
      case StatusTone.recording:
        return AfterimageTheme.blockedText;
    }
  }
}

/// A tinted panel carrying one status message.
///
/// Six near-identical versions of this used to be written by hand across the
/// setup and recorder screens, each with slightly different padding, radius and
/// alpha. Every tinted status panel in Afterimage now comes from here so they
/// agree with one another.
class StatusSurface extends StatelessWidget {
  const StatusSurface({
    super.key,
    required this.tone,
    required this.child,
    this.icon,
    this.padding = const EdgeInsets.all(15),
  });

  final StatusTone tone;
  final Widget child;
  final IconData? icon;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: AfterimageTheme.statusFillAlpha),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: color.withValues(alpha: AfterimageTheme.statusBorderAlpha),
        ),
      ),
      child: icon == null
          ? child
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 11),
                Expanded(child: child),
              ],
            ),
    );
  }
}
