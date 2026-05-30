import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/markdown_style.dart';

/// A visually distinct card for rendering implementation plans inline in chat.
///
/// Shows a preview of the plan text with a header and optional "View Full Plan"
/// button when the content exceeds [_maxPreviewHeight].
class PlanCard extends StatelessWidget {
  final String planText;
  final VoidCallback onViewFullPlan;

  /// Lines threshold below which the full plan is shown without a button.
  static const int _shortPlanLineThreshold = 10;

  /// Max height for the preview area before fade-out is applied.
  static const double _maxPreviewHeight = 200;

  const PlanCard({
    super.key,
    required this.planText,
    required this.onViewFullPlan,
  });

  bool get _isLongPlan => planText.split('\n').length > _shortPlanLineThreshold;

  int get _sectionCount {
    return RegExp(r'^#{1,3}\s', multiLine: true).allMatches(planText).length;
  }

  @override
  Widget build(BuildContext context) {
    // The plan artifact uses the dedicated plan-mode semantic color so it
    // matches the plan-mode chip and the plan-approval header (one concept,
    // one token) instead of the generic primary ember.
    final planColor = Theme.of(context).extension<AppColors>()!.statusPlan;

    return GestureDetector(
      onTap: _isLongPlan ? onViewFullPlan : null,
      child: Container(
        margin: const EdgeInsets.symmetric(
          vertical: AppSpacing.bubbleMarginV,
          horizontal: AppSpacing.bubbleMarginH,
        ),
        decoration: BoxDecoration(
          color: planColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: planColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PlanHeader(sectionCount: _sectionCount),
            Divider(height: 1, color: planColor.withValues(alpha: 0.15)),
            _PlanBody(planText: planText, isLongPlan: _isLongPlan),
            if (_isLongPlan) _PlanFooter(onViewFullPlan: onViewFullPlan),
          ],
        ),
      ),
    );
  }
}

class _PlanHeader extends StatelessWidget {
  final int sectionCount;

  const _PlanHeader({required this.sectionCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planColor = theme.extension<AppColors>()!.statusPlan;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.assignment_outlined,
            size: AppIconSize.inline,
            color: planColor,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            AppLocalizations.of(context).implementationPlan,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: planColor,
            ),
          ),
          const Spacer(),
          if (sectionCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: planColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.codeRadius),
              ),
              child: Text(
                '$sectionCount sections',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: planColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  final String planText;
  final bool isLongPlan;

  const _PlanBody({required this.planText, required this.isLongPlan});

  @override
  Widget build(BuildContext context) {
    final markdownWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: suppressMarkdownScrollbarIndicators(
        context,
        child: MarkdownBody(
          data: planText,
          selectable: true,
          styleSheet: buildMarkdownStyle(context),
          onTapLink: handleMarkdownLink,
          inlineSyntaxes: colorCodeInlineSyntaxes,
          builders: markdownBuilders,
        ),
      ),
    );

    if (!isLongPlan) return markdownWidget;

    return ClipRect(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: PlanCard._maxPreviewHeight,
        ),
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.7, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: markdownWidget,
          ),
        ),
      ),
    );
  }
}

class _PlanFooter extends StatelessWidget {
  final VoidCallback onViewFullPlan;

  const _PlanFooter({required this.onViewFullPlan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planColor = theme.extension<AppColors>()!.statusPlan;

    return InkWell(
      key: const ValueKey('view_full_plan_button'),
      onTap: onViewFullPlan,
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppSpacing.cardRadius),
      ),
      child: Container(
        width: double.infinity,
        // Min touch target so the footer action clears 44px even though the
        // painted strip looks compact.
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: planColor.withValues(alpha: 0.15)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.unfold_more, size: AppIconSize.inline, color: planColor),
            const SizedBox(width: AppSpacing.xs),
            Text(
              AppLocalizations.of(context).viewFullPlan,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: planColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
