import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Design tokens and the small building blocks every screen shares.
///
/// Text wears one of three inks and never a data colour; identity comes from the
/// coloured mark beside it. The two series colours were checked on the panel
/// surface for colour-blind separation, and always ship with a label.
abstract final class Ui {
  // Ink.
  static const ink = Color(0xFFE9EFED);
  static const inkMid = Color(0xFFAEBBB8);
  static const inkLow = Color(0xFF84928F);

  // Series: the user's own games, and the high-level reference.
  static const you = Color(0xFF27AE7D);
  static const reference = Color(0xFF4A8DE8);

  // Outcomes.
  static const bad = Color(0xFFE5645F);
  static const warn = Color(0xFFE0A14A);
  static const good = Color(0xFF27AE7D);
  static const idle = Color(0xFF5B6866);

  /// The unfilled part of a bar.
  static const track = Color(0xFF242D2C);

  static const radius = 14.0;

  static const display = TextStyle(
      fontSize: 30, fontWeight: FontWeight.w700, height: 1.1, color: ink);
  static const h1 = TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: -0.2,
      color: ink);
  static const h2 = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w700, height: 1.25, color: ink);
  static const body = TextStyle(fontSize: 14.5, height: 1.45, color: ink);
  static const bodyMid = TextStyle(fontSize: 14.5, height: 1.45, color: inkMid);
  static const small = TextStyle(fontSize: 12.5, height: 1.35, color: inkMid);
  static const caps = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      height: 1.2,
      color: inkLow);

  /// Numbers that line up in a column.
  static const figure = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: ink,
      fontFeatures: [FontFeature.tabularFigures()]);

  static String percent(num part, num whole) =>
      whole <= 0 ? 'n/a' : '${(100 * part / whole).round()}%';

  static String times(int count) => count == 1 ? '1 time' : '$count times';

  static String thousands(num value) {
    final digits = value.round().abs().toString();
    final out = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

/// A section label in small capitals.
class UiCaps extends StatelessWidget {
  const UiCaps(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: color == null ? Ui.caps : Ui.caps.copyWith(color: color));
}

/// A surface that groups related content. Tappable when [onTap] is set.
class UiPanel extends StatelessWidget {
  const UiPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color = AfterimageTheme.panel,
    this.border = AfterimageTheme.hairline,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ui.radius),
        side: BorderSide(color: border));
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              hoverColor: Colors.white.withValues(alpha: 0.035),
              child: Padding(padding: padding, child: child)),
    );
  }
}

/// A row that highlights under the pointer and can be clicked.
class UiHoverRow extends StatelessWidget {
  const UiHoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.04),
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// A thin bar showing one share of a whole.
class UiMeter extends StatelessWidget {
  const UiMeter({
    super.key,
    required this.fraction,
    required this.color,
    this.width = 96,
    this.height = 8,
  });
  final double fraction;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final value = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: Ui.track, borderRadius: BorderRadius.circular(height)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value == 0 ? null : value.clamp(0.04, 1.0),
            child: value == 0
                ? const SizedBox.shrink()
                : DecoratedBox(
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(height)),
                    child: const SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

/// One whole split into parts, for example what happened after an answer.
class UiSplitBar extends StatelessWidget {
  const UiSplitBar({
    super.key,
    required this.parts,
    this.width = 96,
    this.height = 8,
  });

  /// Counts with their colours, in display order. Parts at zero draw nothing.
  final List<(int, Color)> parts;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final part in parts)
        if (part.$1 > 0) part
    ];
    final total = shown.fold<int>(0, (sum, part) => sum + part.$1);
    if (total == 0) {
      return UiMeter(fraction: 0, color: Ui.idle, width: width, height: height);
    }
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Row(children: [
          for (var index = 0; index < shown.length; index++) ...[
            if (index > 0) const SizedBox(width: 2),
            Expanded(
                flex: shown[index].$1,
                child: ColoredBox(
                    color: shown[index].$2, child: const SizedBox.expand())),
          ],
        ]),
      ),
    );
  }
}

/// A colour key with its label, for legends.
class UiKey extends StatelessWidget {
  const UiKey({super.key, required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Ui.small),
      ]);
}

/// A small label with an optional icon, tinted by [color].
class UiPill extends StatelessWidget {
  const UiPill({super.key, required this.label, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Ui.inkMid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 5),
        ],
        Text(label,
            style: Ui.small.copyWith(
                color: color == null ? Ui.inkMid : Ui.ink,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// A number with its label, and an optional line under it.
class UiStat extends StatelessWidget {
  const UiStat({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.detail,
    this.marker,
  });
  final String label;
  final String value;
  final String? unit;

  /// A line under the value, for example the comparison.
  final Widget? detail;

  /// The colour key of the series this number belongs to.
  final Color? marker;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (marker != null) ...[
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: marker, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
            ],
            Flexible(child: UiCaps(label)),
          ]),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: Ui.display),
              if (unit != null) ...[
                const SizedBox(width: 6),
                Flexible(child: Text(unit!, style: Ui.small)),
              ],
            ],
          ),
          if (detail != null) ...[const SizedBox(height: 6), detail!],
        ],
      );
}

/// Underlined tabs: the sections of one page.
class UiTabs<T> extends StatelessWidget {
  const UiTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  /// Value, label, and the key the label text carries.
  final List<(T, String, Key?)> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: AfterimageTheme.hairline))),
        // Scrolls sideways rather than overflowing in a narrow window.
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final tab in tabs)
                InkWell(
                  onTap: () => onChanged(tab.$1),
                  hoverColor: Colors.white.withValues(alpha: 0.04),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
                    margin: const EdgeInsets.only(right: 26),
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                width: 2,
                                color: tab.$1 == selected
                                    ? AfterimageTheme.accent
                                    : Colors.transparent))),
                    child: Text(tab.$2,
                        key: tab.$3,
                        style: Ui.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: tab.$1 == selected ? Ui.ink : Ui.inkMid)),
                  ),
                ),
            ])),
      );
}

/// A chevron for rows that open something.
class UiChevron extends StatelessWidget {
  const UiChevron({super.key});
  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.chevron_right_rounded, size: 22, color: Ui.inkLow);
}
