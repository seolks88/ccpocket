import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/messages.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'expandable_summary_text.dart';
import 'permission_presentation_view.dart';

enum PlanApprovalUiMode { claude, codex }

/// Bottom bar that presents tool-use / plan approval controls.
///
/// Pure presentation — all actions are dispatched via callbacks.
class ApprovalBar extends StatelessWidget {
  final AppColors appColors;
  final PermissionRequestMessage? pendingPermission;
  final bool isPlanApproval;
  final TextEditingController planFeedbackController;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onApproveAlways;
  final VoidCallback? onViewPlan;

  /// Callback for "Accept & Clear Context" button (plan approval only).
  final VoidCallback? onApproveClearContext;
  final PlanApprovalUiMode planApprovalUiMode;

  const ApprovalBar({
    super.key,
    required this.appColors,
    required this.pendingPermission,
    required this.isPlanApproval,
    required this.planFeedbackController,
    required this.onApprove,
    required this.onReject,
    required this.onApproveAlways,
    this.onViewPlan,
    this.onApproveClearContext,
    this.planApprovalUiMode = PlanApprovalUiMode.claude,
  });

  @override
  Widget build(BuildContext context) {
    final presentation = pendingPermission?.presentation;
    final l = AppLocalizations.of(context);
    final summary = pendingPermission != null
        ? (isPlanApproval ? l.planApprovalSummary : pendingPermission!.summary)
        : l.toolApprovalSummary;
    final toolName = isPlanApproval
        ? l.planApproval
        : presentation?.title ?? pendingPermission?.displayToolName;
    final detailLines = isPlanApproval
        ? const <String>[]
        : (presentation?.secondaryDetails ?? const <String>[]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: appColors.approvalBar,
        border: Border(
          top: BorderSide(color: appColors.approvalBarBorder, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ApprovalHeader(
              appColors: appColors,
              isPlanApproval: isPlanApproval,
              toolName: toolName,
              summary: summary,
              primaryTarget: presentation?.primaryTarget,
              detailLines: detailLines,
              onViewPlan: onViewPlan,
            ),
            const SizedBox(height: 6),
            if (isPlanApproval &&
                planApprovalUiMode == PlanApprovalUiMode.claude) ...[
              const SizedBox(height: 6),
              _KeepPlanningCard(
                appColors: appColors,
                planFeedbackController: planFeedbackController,
                onReject: onReject,
              ),
              const SizedBox(height: 10),
            ] else
              const SizedBox(height: 6),
            _ApprovalButtons(
              pendingPermission: pendingPermission,
              isPlanApproval: isPlanApproval,
              planApprovalUiMode: planApprovalUiMode,
              onApprove: onApprove,
              onReject: onReject,
              onApproveAlways: onApproveAlways,
              onApproveClearContext: onApproveClearContext,
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalHeader extends StatelessWidget {
  final AppColors appColors;
  final bool isPlanApproval;
  final String? toolName;
  final String summary;
  final String? primaryTarget;
  final List<String> detailLines;
  final VoidCallback? onViewPlan;

  const _ApprovalHeader({
    required this.appColors,
    required this.isPlanApproval,
    required this.toolName,
    required this.summary,
    required this.primaryTarget,
    required this.detailLines,
    this.onViewPlan,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // The plan ARTIFACT shares the plan-mode semantic color (statusPlan),
    // matching the inline PlanCard and the plan-mode chip. Tool permissions
    // keep the dedicated permission accent.
    final accent = isPlanApproval
        ? appColors.statusPlan
        : appColors.permissionIcon;
    return PermissionPresentationView(
      icon: isPlanApproval ? Icons.assignment : Icons.shield_outlined,
      iconColor: accent,
      title: toolName ?? l.approvalRequired,
      summary: ExpandableSummaryText(
        text: summary,
        // style inherited from PermissionPresentationView's summary slot
        // (bodySmall + subtleText) so the bubble and bar read identically.
        maxLines: 2,
        backgroundColor: appColors.approvalBar,
      ),
      primaryTarget: isPlanApproval ? null : primaryTarget,
      detailLines: detailLines,
      // Clamp detail lines in the bottom bar so a long agent-supplied reason
      // can't grow the bar upward and push the action buttons off-reach.
      detailMaxLines: 2,
      trailing: (isPlanApproval && onViewPlan != null)
          ? IconButton(
              key: const ValueKey('view_plan_header_button'),
              icon: Icon(
                Icons.open_in_full,
                size: AppIconSize.inline,
                color: accent,
              ),
              tooltip: l.viewEditPlan,
              onPressed: onViewPlan,
              constraints: const BoxConstraints(
                minWidth: AppSizes.minTouchTarget,
                minHeight: AppSizes.minTouchTarget,
              ),
              padding: EdgeInsets.zero,
            )
          : null,
    );
  }
}

/// "Keep Planning" card with feedback input + send button.
class _KeepPlanningCard extends StatelessWidget {
  final AppColors appColors;
  final TextEditingController planFeedbackController;
  final VoidCallback onReject;

  const _KeepPlanningCard({
    required this.appColors,
    required this.planFeedbackController,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('keep_planning_card'),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.keepPlanning,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: appColors.subtleText,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('plan_feedback_input'),
                  controller: planFeedbackController,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    hintText: l.keepPlanningHint,
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: appColors.subtleText,
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  maxLines: 3,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('reject_button'),
                icon: Icon(Icons.send, size: 20, color: cs.primary),
                tooltip: l.sendFeedbackKeepPlanning,
                onPressed: onReject,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovalButtons extends StatelessWidget {
  final PermissionRequestMessage? pendingPermission;
  final bool isPlanApproval;
  final PlanApprovalUiMode planApprovalUiMode;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onApproveAlways;
  final VoidCallback? onApproveClearContext;

  const _ApprovalButtons({
    this.pendingPermission,
    required this.isPlanApproval,
    required this.planApprovalUiMode,
    required this.onApprove,
    required this.onReject,
    required this.onApproveAlways,
    this.onApproveClearContext,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (isPlanApproval) {
      if (planApprovalUiMode == PlanApprovalUiMode.codex) {
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('reject_button'),
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.minTouchTarget),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(
                  l.continuePlanning,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const ValueKey('approve_button'),
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.minTouchTarget),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(l.acceptPlan, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
        );
      }

      return Row(
        children: [
          if (onApproveClearContext != null) ...[
            Expanded(
              child: FilledButton.tonal(
                key: const ValueKey('approve_clear_context_button'),
                onPressed: onApproveClearContext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.minTouchTarget),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(
                  l.acceptAndClear,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton(
              key: const ValueKey('approve_button'),
              onPressed: onApprove,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSizes.minTouchTarget),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text(l.acceptPlan, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      );
    }

    final cs = Theme.of(context).colorScheme;
    final isCodex = planApprovalUiMode == PlanApprovalUiMode.codex;
    final canReject = pendingPermission?.canDecline ?? true;
    final canApproveAlways = pendingPermission?.canApproveForSession ?? true;
    final canApprove = pendingPermission?.canApprove ?? true;
    final rejectLabel = pendingPermission?.showsCancelAction ?? false
        ? l.cancel
        : l.reject;
    final alwaysMain = isCodex ? l.approveSessionMain : l.approveAlways;
    final alwaysSub = isCodex ? l.approveSessionSub : l.approveAlwaysSub;
    final buttons = <Widget>[
      // Reject / Cancel is the only destructive action here; it alone carries
      // the error color. Affirmative actions stay neutral/dominant so red is
      // never paired with "approve".
      if (canReject)
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('reject_button'),
            onPressed: onReject,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSizes.minTouchTarget),
              padding: const EdgeInsets.symmetric(vertical: 8),
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
            ),
            child: Text(rejectLabel, style: const TextStyle(fontSize: 13)),
          ),
        ),
      if (canApproveAlways) ...[
        if (canReject) const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('approve_always_button'),
            onPressed: onApproveAlways,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSizes.minTouchTarget),
              padding: const EdgeInsets.symmetric(vertical: 8),
              foregroundColor: cs.onSurfaceVariant,
              side: BorderSide(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
            child: Text(
              isCodex || alwaysSub.isEmpty
                  ? alwaysMain
                  : '$alwaysMain $alwaysSub',
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
      if (canApprove) ...[
        if (canReject || canApproveAlways) const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            key: const ValueKey('approve_button'),
            onPressed: onApprove,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSizes.minTouchTarget),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: Text(
              isCodex ? l.approve : l.approveOnce,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    ];
    return Row(children: buttons);
  }
}
