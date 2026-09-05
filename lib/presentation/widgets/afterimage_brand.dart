import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The application wordmark.
///
/// There is deliberately no image here. The application shipped with a drawn
/// icon that was not good enough to put in front of a user, so it was removed
/// rather than kept out of sentiment. A mark can be added again when there is
/// one worth showing.
class AfterimageBrand extends StatelessWidget {
  const AfterimageBrand({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markSize = compact ? 30.0 : 38.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 9 : 11),
            gradient: const LinearGradient(
              colors: [AfterimageTheme.accent, AfterimageTheme.accentStrong],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(
            Icons.motion_photos_on_outlined,
            color: AfterimageTheme.canvas,
            size: compact ? 19 : 24,
          ),
        ),
        const SizedBox(width: 11),
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
