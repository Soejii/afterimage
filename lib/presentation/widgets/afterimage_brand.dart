import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The application wordmark, using the real icon.
///
/// This used to draw `Icons.blur_on_rounded` inside a gradient square while the
/// actual icon sat unreferenced in `assets/branding/`, so the application never
/// showed its own logo. The asset is now bundled and used, with the old drawn
/// mark kept only as a fallback if the image cannot load.
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
        SizedBox(
          width: markSize,
          height: markSize,
          child: Image.asset(
            'assets/branding/afterimage-icon.png',
            width: markSize,
            height: markSize,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => _FallbackMark(
              size: markSize,
              compact: compact,
            ),
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

class _FallbackMark extends StatelessWidget {
  const _FallbackMark({required this.size, required this.compact});

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
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
        size: compact ? 20 : 25,
      ),
    );
  }
}
