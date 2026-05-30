import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

/// Number of lines shown in a tool preview before it truncates. Shared by the
/// result-side preview ([ToolResultBubble]) and the call-side card
/// ([ToolUseTile]) so a "preview" means the same thing on both sides.
const int toolPreviewLines = 5;

/// Shared header used by every tool row — the collapsed result row, the
/// expanded result card, and the assistant-side tool-use collapsed row + card —
/// so the "icon + tool name + summary + trailing" recipe stays identical and
/// any future tweak lands once. Behaviour-free: pure layout.
///
/// Parameterised by primitives (icon/accent) rather than a result-only status
/// object so the call side can reuse it with category-derived visuals.
class ToolRowHeader extends StatelessWidget {
  final IconData icon;

  /// Tint for the leading glyph (and the tool name when [isError]).
  final Color accent;
  final String name;
  final String summaryText;
  final double iconSize;

  /// When true, the name + summary read in the error tint.
  final bool isError;

  /// When true, the summary reads as a muted placeholder (e.g. "(no output)").
  final bool muted;
  final Widget? trailing;

  const ToolRowHeader({
    super.key,
    required this.icon,
    required this.accent,
    required this.name,
    required this.summaryText,
    required this.iconSize,
    this.isError = false,
    this.muted = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: iconSize, color: accent),
        const SizedBox(width: AppSpacing.sm),
        Text(
          name,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            // Tint the name on failure so the call reads as failed even when
            // the glyph scrolls past the eye.
            color: isError ? appColors.errorText : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            summaryText,
            style: textTheme.labelSmall?.copyWith(
              color: isError ? appColors.errorText : appColors.subtleText,
              fontStyle: muted ? FontStyle.italic : FontStyle.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// The one "... N more lines" truncation hint, so the four places that
/// truncate long tool bodies (result preview, tool-use card preview, inline
/// edit diff, todo list) all read in the same muted italic voice.
class MoreLinesHint extends StatelessWidget {
  final int remaining;

  const MoreLinesHint({super.key, required this.remaining});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Text(
      '... $remaining more lines',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: appColors.subtleText,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
