import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// The single container-pill recipe shared by the small inline status chips
/// (result / system / tip).
///
/// One geometry, distinct meaning: every consumer gets identical corner radius
/// ([AppRadius.sm]), padding rhythm and label style ([TextTheme.labelMedium]),
/// and supplies only its own semantic [backgroundColor] / [foregroundColor].
///
/// Pass [label] for a plain-text pill, or [child] when the content is a richer
/// widget (e.g. an environment summary). The optional [icon] sits inline before
/// the label and stays compact — only the pill geometry is shared, glyphs keep
/// their own size.
class ChipPill extends StatelessWidget {
  /// Semantic fill for the pill.
  final Color backgroundColor;

  /// Semantic foreground applied to the label text (and [icon] when present).
  /// When null, the inherited [TextTheme.labelSmall] color is used.
  final Color? foregroundColor;

  /// Plain-text label. Mutually exclusive with [child].
  final String? label;

  /// Custom content. Mutually exclusive with [label].
  final Widget? child;

  /// Optional leading glyph, rendered at [AppIconSize.chip] to stay compact.
  final IconData? icon;

  const ChipPill({
    super.key,
    required this.backgroundColor,
    this.foregroundColor,
    this.label,
    this.child,
    this.icon,
  }) : assert(
         (label == null) != (child == null),
         'Provide exactly one of label or child.',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget content;
    if (child != null) {
      content = child!;
    } else {
      final text = Text(
        label!,
        style: theme.textTheme.labelMedium?.copyWith(color: foregroundColor),
      );
      content = icon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: AppIconSize.chip,
                  color: foregroundColor,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(child: text),
              ],
            );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: content,
    );
  }
}
