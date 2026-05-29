import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/code_text_style.dart';

/// Shared presentation of a permission / approval request.
///
/// Renders one consistent idiom for the same high-consequence decision
/// regardless of where it appears (inline [PermissionRequestBubble] or the
/// bottom [ApprovalBar]): a single leading icon, a title, a summary, an
/// optional monospace "primary target" card, and a single bullet-list idiom
/// for secondary detail lines.
///
/// Pure presentation — no state, no callbacks. Hosts supply their own
/// surrounding chrome (containers, expanders, action buttons) and pass the
/// `header`/`summary` slots they want so each host keeps its existing
/// behavior while sharing the visual language.
class PermissionPresentationView extends StatelessWidget {
  /// The leading icon glyph. Both surfaces use the same default so the
  /// concept reads identically; the plan-approval variant may tint it.
  final IconData icon;

  /// Icon (and tint) color. Defaults to [AppColors.permissionIcon].
  final Color? iconColor;

  /// The title text (tool / request name).
  final String title;

  /// Optional summary slot. Callers can pass plain [Text] or an
  /// expandable summary widget; when null, no summary row is shown.
  final Widget? summary;

  /// Optional monospace command / path / target shown in a code-style card.
  final String? primaryTarget;

  /// Secondary detail lines, rendered as a single bullet-list idiom.
  final List<String> detailLines;

  /// Optional trailing widget in the header row (e.g. an expand chevron or a
  /// "view plan" action). Sits to the right of the title.
  final Widget? trailing;

  /// Optional tap handler for the whole header row (title + icon + trailing).
  final VoidCallback? onHeaderTap;

  /// Max lines per secondary detail line. Null = unbounded (inline bubble can
  /// grow freely). The bottom [ApprovalBar] passes a small value (2) so a long
  /// agent-supplied reason cannot push the action buttons off-reach.
  final int? detailMaxLines;

  const PermissionPresentationView({
    super.key,
    this.icon = Icons.shield_outlined,
    this.iconColor,
    required this.title,
    this.summary,
    this.primaryTarget,
    this.detailLines = const [],
    this.trailing,
    this.onHeaderTap,
    this.detailMaxLines,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final theme = Theme.of(context);
    final resolvedIconColor = iconColor ?? appColors.permissionIcon;
    final target = primaryTarget;

    final header = Row(
      children: [
        Icon(icon, size: AppIconSize.inline, color: resolvedIconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onHeaderTap != null)
          InkWell(onTap: onHeaderTap, child: header)
        else
          header,
        if (summary != null) ...[
          const SizedBox(height: AppSpacing.xs),
          DefaultTextStyle.merge(
            style:
                theme.textTheme.bodySmall?.copyWith(
                  color: appColors.subtleText,
                ) ??
                TextStyle(color: appColors.subtleText),
            child: summary!,
          ),
        ],
        if (target != null) ...[
          const SizedBox(height: AppSpacing.sm),
          PermissionTargetCard(text: target),
        ],
        if (detailLines.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final line in detailLines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: AppSpacing.sm),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: appColors.subtleText,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      maxLines: detailMaxLines,
                      overflow: detailMaxLines != null
                          ? TextOverflow.ellipsis
                          : null,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appColors.subtleText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Monospace command / path / target card used by both permission surfaces.
///
/// Backed by the warm code surface tokens so a copyable command in an
/// approval bar looks identical to one in an inline permission bubble (and to
/// real code blocks elsewhere). Uses the user-configurable code font via
/// [codeTextSettingsOf] — never a bare `fontFamily: 'monospace'`.
class PermissionTargetCard extends StatelessWidget {
  final String text;

  const PermissionTargetCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: appColors.codeBackground,
        borderRadius: BorderRadius.circular(AppSpacing.codeRadius),
        border: Border.all(color: appColors.codeBorder),
      ),
      child: Text(
        text,
        style: codeTextSettingsOf(context).style(color: cs.onSurface),
      ),
    );
  }
}
