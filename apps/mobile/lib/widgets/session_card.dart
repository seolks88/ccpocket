import 'package:expandable_page_view/expandable_page_view.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/messages.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/code_text_style.dart';
import '../theme/provider_style.dart';
import '../utils/command_parser.dart';
import 'adaptive_context_menu.dart';
import 'plan_detail_sheet.dart';
import 'expandable_summary_text.dart';
import 'session_visual_status.dart';

/// Shared layout constant for AskUserArea buttons.
const _buttonHeight = 44.0;
const _sessionCardTextRailIndent = AppIconSize.chip + AppSpacing.sm;

/// Card for a currently running session
class RunningSessionCard extends StatefulWidget {
  final SessionInfo session;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<Offset?>? onShowActions;
  final void Function(String toolUseId, {bool clearContext})? onApprove;
  final ValueChanged<String>? onApproveAlways;
  final void Function(String toolUseId, {String? message})? onReject;
  final void Function(String toolUseId, String result)? onAnswer;
  final VoidCallback? onStop;
  final bool isUnseen;
  final bool isSelected;

  const RunningSessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.onShowActions,
    this.onApprove,
    this.onApproveAlways,
    this.onReject,
    this.onAnswer,
    this.onStop,
    this.isUnseen = false,
    this.isSelected = false,
  });

  @override
  State<RunningSessionCard> createState() => _RunningSessionCardState();
}

class _RunningSessionCardState extends State<RunningSessionCard> {
  late final TextEditingController _planFeedbackController;
  String? _activePlanToolUseId;

  @override
  void initState() {
    super.initState();
    _planFeedbackController = TextEditingController();
  }

  @override
  void dispose() {
    _planFeedbackController.dispose();
    super.dispose();
  }

  void _syncPlanApprovalState(PermissionRequestMessage? permission) {
    final toolUseId = permission?.toolUseId;
    if (_activePlanToolUseId == toolUseId) return;
    _activePlanToolUseId = toolUseId;
    _planFeedbackController.clear();
  }

  String? _extractPlanText(PermissionRequestMessage permission) {
    final raw = permission.input['plan'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw;
    }
    return null;
  }

  Future<void> _openPlanSheet(PermissionRequestMessage permission) async {
    final originalText = _extractPlanText(permission);
    if (originalText == null || !mounted) return;
    await showPlanDetailSheet(context, originalText);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final visualStatus = sessionVisualStatusFor(
      rawStatus: session.status,
      permissionMode: session.effectivePermissionMode,
      planMode: session.resolvedPlanMode,
      pendingPermission: session.pendingPermission,
    );
    final isReadyUnseen =
        visualStatus.primary == SessionPrimaryStatus.ready && widget.isUnseen;
    final isNeedsYou = visualStatus.primary == SessionPrimaryStatus.needsYou;
    // Four glanceable status hues: Working=blue, Needs You=ember (highest
    // urgency), Done (ready & unseen)=green (a positive "go look"), Idle
    // (ready & seen)=muted warm grey. Done now carries a real hue instead of
    // the old near-black onSurface so it never reads as "another grey" beside
    // Idle. Done/Idle have no approval area, so statusColor here only drives
    // the dot/word/rail/tint/selected-border for those two states.
    final statusColor = switch (visualStatus.primary) {
      SessionPrimaryStatus.working => appColors.statusRunning,
      SessionPrimaryStatus.needsYou => appColors.statusApproval,
      SessionPrimaryStatus.ready =>
        isReadyUnseen ? appColors.statusOnline : appColors.statusIdle,
    };
    // Split the today-collapsed grey "Ready" into Done (just-finished, unseen)
    // vs Idle (long-idle) purely from the already-passed isUnseen flag — no
    // change to session_visual_status.dart. Working/Needs You keep the existing
    // hardcoded-English visualStatus.label path; Done/Idle are added the same
    // way (the sibling labels are raw English literals, not AppLocalizations).
    final statusWord = isReadyUnseen
        ? 'Done'
        : switch (visualStatus.primary) {
            SessionPrimaryStatus.working => visualStatus.label,
            SessionPrimaryStatus.needsYou => visualStatus.label,
            SessionPrimaryStatus.ready => 'Idle',
          };

    final permission = session.pendingPermission;
    final hasPermission = permission != null;
    final queuedInput = session.queuedInput;
    final isCodexSession = session.provider == Provider.codex.value;
    final isPlanApproval =
        hasPermission && permission.toolName == 'ExitPlanMode';
    final hasQuestionPrompt = hasPermission && permission.usesAskUserUi;
    if (isPlanApproval) {
      _syncPlanApprovalState(permission);
    } else {
      _syncPlanApprovalState(null);
    }
    final projectName = session.projectPath.split('/').last;
    final provider = providerFromRaw(session.provider);
    final elapsed = _formatElapsed(session.lastActivityAt);
    final agentLabel = _formatAgentLabel(
      session.agentNickname,
      session.agentRole,
    );
    final displayMessage = formatCommandText(
      session.lastMessage.replaceAll(RegExp(r'\s+'), ' ').trim(),
    );
    final colorScheme = Theme.of(context).colorScheme;
    // Flat, uniform surface for every state — status is carried by the dot +
    // word (and the approval area when present), not by a tinted wash. Keeps
    // cards calm and consistent with the surrounding surfaces.
    final cardColor = colorScheme.surfaceContainerHigh;
    final card = Card(
      margin: const EdgeInsets.symmetric(
        vertical: AppSpacing.xs,
        horizontal: 0,
      ),
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: widget.isSelected
              ? statusColor.withValues(alpha: 0.95)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: widget.isSelected ? 2.2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onShowActions == null ? widget.onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line 1 — status eyebrow + time: a slim meta strip so the
              // title on Line 2 below gets the full card width.
              Row(
                children: [
                  _StatusDot(
                    color: statusColor,
                    animate: visualStatus.animate,
                    glow: isReadyUnseen,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    statusWord.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: isReadyUnseen || isNeedsYou
                          ? FontWeight.w800
                          : FontWeight.w700,
                      letterSpacing: 0.5,
                      color: statusColor,
                    ),
                  ),
                  // Plan-mode signal: a calm, static (motion-safe) marker.
                  // Keeps the primary status color on the dot/label; adds a
                  // plan-tinted glyph.
                  if (visualStatus.showPlanBadge) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.assignment_outlined,
                      size: AppIconSize.chip,
                      color: appColors.statusPlan,
                    ),
                  ],
                  const Spacer(),
                  // Meta trailing: queued-input badge + the small elapsed
                  // timestamp, pushed to the right by the Spacer.
                  if (queuedInput != null) ...[
                    _QueuedInputBadge(item: queuedInput),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  // Fixed-width trailing slot keeps timestamps aligned
                  // across cards while still ellipsizing on narrow layouts.
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 64,
                      maxWidth: 88,
                    ),
                    child: Text(
                      elapsed,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: appColors.subtleText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Line 2 — identity: provider glyph + the full-width title.
              // Provider is carried ONCE here as a bare tinted glyph (no
              // word pill), so the title stays neutral text. The inline Stop
              // control stays on the right when shown (shell/desktop only).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _ProviderGlyph(provider: provider),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Hero(
                      tag: 'project_name_${session.id}',
                      child: Material(
                        type: MaterialType.transparency,
                        child: _SessionTitle(
                          title:
                              session.name != null && session.name!.isNotEmpty
                              ? session.name!
                              : projectName,
                          projectSuffix:
                              session.name != null &&
                                  session.name!.isNotEmpty &&
                                  session.name! != projectName
                              ? projectName
                              : null,
                          agentLabel: agentLabel,
                        ),
                      ),
                    ),
                  ),
                  if (widget.onStop != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _RunningSessionStopButton(onPressed: widget.onStop!),
                  ],
                ],
              ),
              // Approval area (shown when waiting for permission). The
              // entire provider x toolName switch below is lifted verbatim;
              // only its position moved to inside this Column.
              if (hasPermission) ...[
                const SizedBox(height: AppSpacing.sm),
                isCodexSession
                    ? (isPlanApproval
                          ? _CodexPlanApprovalArea(
                              statusColor: statusColor,
                              canOpenPlan: _extractPlanText(permission) != null,
                              onOpenPlan: () => _openPlanSheet(permission),
                              onApprove: () => widget.onApprove?.call(
                                permission.toolUseId,
                                clearContext: false,
                              ),
                              onReject: () =>
                                  widget.onReject?.call(permission.toolUseId),
                            )
                          : hasQuestionPrompt
                          ? _AskUserArea(
                              permission: permission,
                              statusColor: statusColor,
                              onAnswer: (result) => widget.onAnswer?.call(
                                permission.toolUseId,
                                result,
                              ),
                              onTap: widget.onTap,
                            )
                          : _ToolApprovalArea(
                              permission: permission,
                              statusColor: statusColor,
                              isCodex: isCodexSession,
                              onApprove: () => widget.onApprove?.call(
                                permission.toolUseId,
                                clearContext: false,
                              ),
                              onApproveAlways: widget.onApproveAlways == null
                                  ? null
                                  : () => widget.onApproveAlways!(
                                      permission.toolUseId,
                                    ),
                              onReject: () =>
                                  widget.onReject?.call(permission.toolUseId),
                            ))
                    : switch (permission.toolName) {
                        'AskUserQuestion' ||
                        'McpElicitation' when hasQuestionPrompt => _AskUserArea(
                          permission: permission,
                          statusColor: statusColor,
                          onAnswer: (result) => widget.onAnswer?.call(
                            permission.toolUseId,
                            result,
                          ),
                          onTap: widget.onTap,
                        ),
                        'ExitPlanMode' => _PlanApprovalArea(
                          statusColor: statusColor,
                          planFeedbackController: _planFeedbackController,
                          canOpenPlan: _extractPlanText(permission) != null,
                          onOpenPlan: () => _openPlanSheet(permission),
                          onApprove: () => widget.onApprove?.call(
                            permission.toolUseId,
                            clearContext: false,
                          ),
                          onApproveClearContext: () => widget.onApprove?.call(
                            permission.toolUseId,
                            clearContext: true,
                          ),
                          onKeepPlanning: () {
                            final feedback = _planFeedbackController.text
                                .trim();
                            widget.onReject?.call(
                              permission.toolUseId,
                              message: feedback.isNotEmpty ? feedback : null,
                            );
                            _planFeedbackController.clear();
                          },
                        ),
                        _ => _ToolApprovalArea(
                          permission: permission,
                          statusColor: statusColor,
                          isCodex: isCodexSession,
                          onApprove: () => widget.onApprove?.call(
                            permission.toolUseId,
                            clearContext: false,
                          ),
                          onApproveAlways: () => widget.onApproveAlways?.call(
                            permission.toolUseId,
                          ),
                          onReject: () =>
                              widget.onReject?.call(permission.toolUseId),
                        ),
                      },
              ],
              // Row 2 — preview (the anchor). Clamps to 1 line only while
              // an approval area is open so an actionable card stays
              // compact; otherwise the medium 2-line preview.
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(
                  left: _sessionCardTextRailIndent,
                ),
                child: _SessionMessage(
                  text: displayMessage,
                  maxLines: hasPermission ? 1 : 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final onShowActions = widget.onShowActions;
    if (onShowActions == null) return card;
    return AdaptiveContextMenuRegion(onOpen: onShowActions, child: card);
  }

  String _formatElapsed(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}

class _QueuedInputBadge extends StatelessWidget {
  final QueuedInputItem item;

  const _QueuedInputBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final imageLabel = item.imageCount > 0
        ? ' · ${l.queuedInputImageCount(item.imageCount)}'
        : '';
    final semanticsLabel = '${l.queuedInputForNextTurn}$imageLabel';

    return Semantics(
      label: semanticsLabel,
      child: Tooltip(
        message: semanticsLabel,
        child: Container(
          key: const ValueKey('session_card_queue_badge'),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.32),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: AppIconSize.chip - 2,
                color: colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l.sessionCardQueuedInput,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimaryContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunningSessionStopButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RunningSessionStopButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    // Destructive control: keep the painted icon compact (~20) but guarantee
    // a full 44x44 hit area per AppSizes.minTouchTarget.
    return IconButton(
      key: const ValueKey('running_session_stop_button'),
      onPressed: onPressed,
      tooltip: l.stopSession,
      icon: const Icon(Icons.stop_circle_outlined),
      iconSize: AppIconSize.action,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: AppSizes.minTouchTarget,
        height: AppSizes.minTouchTarget,
      ),
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.error,
        backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.26),
      ),
    );
  }
}

/// Approval area for normal tool execution (Bash, Edit, etc.)
class _ToolApprovalArea extends StatelessWidget {
  final PermissionRequestMessage permission;
  final Color statusColor;
  final VoidCallback onApprove;
  final VoidCallback? onApproveAlways;
  final VoidCallback onReject;
  final bool isCodex;

  const _ToolApprovalArea({
    required this.permission,
    required this.statusColor,
    required this.onApprove,
    this.onApproveAlways,
    required this.onReject,
    this.isCodex = false,
  });

  @override
  Widget build(BuildContext context) {
    final presentation = permission.presentation;
    final detailLines = presentation.secondaryDetails;
    final canReject = permission.canDecline;
    final canApproveAlways =
        permission.canApproveForSession && onApproveAlways != null;
    final canApprove = permission.canApprove;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: statusColor.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            presentation.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          ExpandableSummaryText(
            text: presentation.summary,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.8),
            ),
            maxLines: 2,
          ),
          if (presentation.primaryTarget != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                presentation.primaryTarget!,
                style: codeTextSettingsOf(context).style(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (detailLines.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...detailLines
                .take(5)
                .map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 400;
              final l = AppLocalizations.of(context);
              final cs = Theme.of(context).colorScheme;
              final rejectLabel = permission.showsCancelAction
                  ? l.cancel
                  : l.reject;
              final alwaysMain = isCodex
                  ? l.approveSessionMain
                  : l.approveAlways;
              final alwaysSub = isCodex
                  ? l.approveSessionSub
                  : l.approveAlwaysSub;
              Widget buildApproveLabel() {
                final approveLabel = isCodex ? l.approve : l.approveOnce;
                if (isWide || !approveLabel.contains(' ')) {
                  return Text(
                    approveLabel,
                    style: const TextStyle(fontSize: 12),
                  );
                }
                final splitIndex = approveLabel.lastIndexOf(' ');
                final sub = approveLabel.substring(0, splitIndex);
                final main = approveLabel.substring(splitIndex + 1);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w400,
                        color: statusColor.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(main, style: const TextStyle(fontSize: 11)),
                  ],
                );
              }

              final buttons = <Widget>[
                if (canReject)
                  SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      key: const ValueKey('reject_button'),
                      onPressed: onReject,
                      icon: const Icon(Icons.close, size: 14),
                      label: Text(rejectLabel),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                if (canApproveAlways) ...[
                  if (canReject) const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      key: const ValueKey('approve_always_button'),
                      onPressed: onApproveAlways,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: cs.error,
                        side: BorderSide(
                          color: cs.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: isWide || alwaysSub.isEmpty
                          ? Text(
                              alwaysSub.isEmpty
                                  ? alwaysMain
                                  : '$alwaysMain $alwaysSub',
                              style: const TextStyle(fontSize: 12),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  alwaysSub,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w400,
                                    color: cs.error.withValues(alpha: 0.7),
                                  ),
                                ),
                                Text(
                                  alwaysMain,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
                if (canApprove) ...[
                  if (canReject || canApproveAlways) const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('approve_button'),
                      onPressed: onApprove,
                      icon: const Icon(Icons.check, size: 14),
                      label: buildApproveLabel(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 11),
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        foregroundColor: statusColor,
                      ),
                    ),
                  ),
                ],
              ];
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: buttons,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Approval area for ExitPlanMode (plan review).
class _PlanApprovalArea extends StatelessWidget {
  final Color statusColor;
  final TextEditingController planFeedbackController;
  final bool canOpenPlan;
  final VoidCallback onOpenPlan;
  final VoidCallback onApprove;
  final VoidCallback onApproveClearContext;
  final VoidCallback onKeepPlanning;

  const _PlanApprovalArea({
    required this.statusColor,
    required this.planFeedbackController,
    required this.canOpenPlan,
    required this.onOpenPlan,
    required this.onApprove,
    required this.onApproveClearContext,
    required this.onKeepPlanning,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: statusColor.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    l.planApprovalSummaryCard,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.8),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (canOpenPlan)
                IconButton(
                  onPressed: onOpenPlan,
                  icon: const Icon(Icons.open_in_full, size: 22),
                  color: cs.primary,
                  tooltip: l.viewEditPlan,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.keepPlanning,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('plan_feedback_input'),
                  controller: planFeedbackController,
                  style: const TextStyle(fontSize: 13),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    hintText: l.keepPlanningHint,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('reject_button'),
                onPressed: onKeepPlanning,
                icon: Icon(Icons.send, size: 18, color: cs.primary),
                tooltip: l.sendFeedbackKeepPlanning,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    key: const ValueKey('approve_clear_context_button'),
                    onPressed: onApproveClearContext,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      foregroundColor: statusColor,
                      side: BorderSide(
                        color: statusColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        l.acceptAndClear,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: FilledButton(
                    key: const ValueKey('approve_button'),
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      backgroundColor: statusColor.withValues(alpha: 0.15),
                      foregroundColor: statusColor,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        l.acceptPlan,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Plan approval area for Codex sessions in session list.
class _CodexPlanApprovalArea extends StatelessWidget {
  final Color statusColor;
  final bool canOpenPlan;
  final VoidCallback onOpenPlan;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _CodexPlanApprovalArea({
    required this.statusColor,
    required this.canOpenPlan,
    required this.onOpenPlan,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('codex_plan_approval_area'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: statusColor.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    l.planApprovalSummaryCard,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.8),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (canOpenPlan)
                IconButton(
                  onPressed: onOpenPlan,
                  icon: const Icon(Icons.open_in_full, size: 22),
                  color: cs.primary,
                  tooltip: l.viewEditPlan,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    key: const ValueKey('reject_button'),
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        l.continuePlanning,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: FilledButton(
                    key: const ValueKey('approve_button'),
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      backgroundColor: statusColor.withValues(alpha: 0.15),
                      foregroundColor: statusColor,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        l.acceptPlan,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Approval area for AskUserQuestion.
/// Supports three modes:
/// - Single question, single select → full-width buttons + Other
/// - Single question, multi select → toggle buttons + Confirm + Other
/// - Multiple questions → PageView with one question per page + Other
class _AskUserArea extends StatefulWidget {
  final PermissionRequestMessage permission;
  final Color statusColor;
  final ValueChanged<String> onAnswer;
  final VoidCallback onTap;

  const _AskUserArea({
    required this.permission,
    required this.statusColor,
    required this.onAnswer,
    required this.onTap,
  });

  @override
  State<_AskUserArea> createState() => _AskUserAreaState();
}

class _AskUserAreaState extends State<_AskUserArea> {
  late final PageController _pageController;

  /// 0 to questions.length (where questions.length == summary page).
  int _currentPage = 0;

  /// questionIndex -> chosen label
  final Map<int, String> _singleAnswers = {};

  /// questionIndex -> set of chosen labels
  final Map<int, Set<String>> _multiAnswers = {};

  final Map<int, TextEditingController> _customControllers = {};

  /// Keep track of which questions have their "Other" input shown
  final Set<int> _customInputs = {};

  List<dynamic> get _questions =>
      widget.permission.input['questions'] as List<dynamic>? ?? [];

  bool get _isMultiQuestion => _questions.length > 1;

  bool get _allowsCustomInput => !widget.permission.isQuestionApproval;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    for (var c in _customControllers.values) {
      c.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _answerSingle(int questionIndex, String label) {
    setState(() {
      _singleAnswers[questionIndex] = label;

      // Only clear custom input for single-select questions
      final q = _questions[questionIndex] as Map<String, dynamic>;
      final isMulti = q['multiSelect'] as bool? ?? false;
      if (!isMulti) {
        _customControllers[questionIndex]?.clear();
      }
    });
    if (!_isMultiQuestion) {
      // Single question → send immediately
      widget.onAnswer(label);
    }
  }

  void _confirmMultiSelect(int questionIndex) {
    final selected = _multiAnswers[questionIndex];
    if (selected == null || selected.isEmpty) return;
    final answer = selected.join(', ');
    if (!_isMultiQuestion) {
      widget.onAnswer(answer);
    } else {
      setState(() {
        _singleAnswers[questionIndex] = answer;
      });
      _goToPage(_currentPage + 1);
    }
  }

  void _submitCustomText(int questionIndex) {
    // Determine the combined text for submission
    String finalAnswer = '';

    final q = _questions[questionIndex] as Map<String, dynamic>;
    final isMulti = q['multiSelect'] as bool? ?? false;

    final customText = _customControllers[questionIndex]?.text.trim() ?? '';

    if (isMulti) {
      final selected = _multiAnswers[questionIndex] ?? {};
      final parts = [...selected];
      if (customText.isNotEmpty) parts.add(customText);
      finalAnswer = parts.join(', ');
    } else {
      finalAnswer = _singleAnswers[questionIndex]?.trim() ?? '';
    }

    if (finalAnswer.isEmpty) return;

    if (!_isMultiQuestion) {
      widget.onAnswer(finalAnswer);
      return;
    }

    final next = questionIndex + 1;
    if (next <= _questions.length) {
      _goToPage(next);
    }
  }

  void _submitAll() {
    final parts = <String>[];
    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i] as Map<String, dynamic>;
      final isMulti = q['multiSelect'] as bool? ?? false;
      final header = q['header'] as String? ?? 'Q${i + 1}';

      String answer = '';
      if (isMulti) {
        final selected = _multiAnswers[i] ?? {};
        final subParts = [...selected];
        final customText = _customControllers[i]?.text.trim() ?? '';
        if (customText.isNotEmpty) subParts.add(customText);
        answer = subParts.isNotEmpty ? subParts.join(', ') : '(skipped)';
      } else {
        answer = _singleAnswers[i] ?? '(skipped)';
      }

      parts.add('$header: $answer');
    }
    widget.onAnswer(parts.join('\n'));
  }

  void _resetAll() {
    setState(() {
      _singleAnswers.clear();
      for (var s in _multiAnswers.values) {
        s.clear();
      }
      _multiAnswers.clear();
      _customInputs.clear();
      for (var c in _customControllers.values) {
        c.clear();
      }
      _currentPage = 0;
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _toggleMultiSelectLabel(int questionIndex, String label) {
    setState(() {
      final selected = _multiAnswers.putIfAbsent(questionIndex, () => {});
      if (selected.contains(label)) {
        selected.remove(label);
      } else {
        selected.add(label);
      }

      final parts = [...selected];
      final customText = _customControllers[questionIndex]?.text.trim() ?? '';
      if (customText.isNotEmpty) parts.add(customText);

      _singleAnswers[questionIndex] = parts.join(', ');
    });
  }

  void _onCustomTextChanged(int questionIndex, String text) {
    setState(() {
      final q = _questions[questionIndex] as Map<String, dynamic>;
      final isMulti = q['multiSelect'] as bool? ?? false;

      if (isMulti) {
        final selected = _multiAnswers[questionIndex] ?? {};
        final parts = [...selected];
        if (text.trim().isNotEmpty) parts.add(text.trim());
        _singleAnswers[questionIndex] = parts.join(', ');
      } else {
        _singleAnswers[questionIndex] = text.trim();
        // Clear single-select chips when typing
        if (text.trim().isNotEmpty) {
          _multiAnswers[questionIndex]?.clear();
        }
      }
    });
  }

  void _showCustomInput(int questionIndex) {
    if (!_allowsCustomInput) return;
    setState(() {
      _customInputs.add(questionIndex);
    });
  }

  TextEditingController _getOrCreateController(int questionIndex) {
    return _customControllers.putIfAbsent(
      questionIndex,
      () => TextEditingController(),
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final questions = _questions;
    if (questions.isEmpty) return const SizedBox.shrink();

    final firstQ = questions[0] as Map<String, dynamic>;
    final options = firstQ['options'] as List<dynamic>? ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: widget.statusColor.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isMultiQuestion) ...[
            _QuestionPageView(
              questions: questions,
              currentPage: _currentPage,
              pageController: _pageController,
              statusColor: widget.statusColor,
              isMultiQuestion: _isMultiQuestion,
              allowsCustomInput: _allowsCustomInput,
              singleAnswers: _singleAnswers,
              multiAnswers: _multiAnswers,
              customInputs: _customInputs,
              getOrCreateController: _getOrCreateController,
              onAnswerSingle: _answerSingle,
              onToggleMultiSelectLabel: _toggleMultiSelectLabel,
              onConfirmMultiSelect: _confirmMultiSelect,
              onSubmitCustomText: _submitCustomText,
              onCustomTextChanged: _onCustomTextChanged,
              onShowCustomInput: _showCustomInput,
              onPageChanged: _onPageChanged,
              onGoToPage: _goToPage,
              onResetAll: _resetAll,
              onSubmitAll: _submitAll,
            ),
          ] else if (options.isNotEmpty) ...[
            _QuestionLayout(
              question: firstQ,
              questionIndex: 0,
              statusColor: widget.statusColor,
              isMultiQuestion: _isMultiQuestion,
              allowsCustomInput: _allowsCustomInput,
              singleAnswers: _singleAnswers,
              multiAnswers: _multiAnswers,
              customInputs: _customInputs,
              getOrCreateController: _getOrCreateController,
              onAnswerSingle: _answerSingle,
              onToggleMultiSelectLabel: _toggleMultiSelectLabel,
              onConfirmMultiSelect: _confirmMultiSelect,
              onSubmitCustomText: _submitCustomText,
              onCustomTextChanged: _onCustomTextChanged,
              onShowCustomInput: _showCustomInput,
            ),
          ] else ...[
            _QuestionText(question: firstQ),
            const SizedBox(height: 6),
            _OpenButton(onTap: widget.onTap),
          ],
        ],
      ),
    );
  }
}

/// Displays the question text from a question map.
class _QuestionText extends StatelessWidget {
  final Map<String, dynamic> question;

  const _QuestionText({required this.question});

  @override
  Widget build(BuildContext context) {
    final text = question['question'] as String? ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// "Open" button for questions without options.
class _OpenButton extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        height: _buttonHeight,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.open_in_new, size: 14),
          label: const Text('Open'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// Single-select option chips for a question.
class _SingleSelectChips extends StatelessWidget {
  final int questionIndex;
  final List<dynamic> options;
  final String? selectedLabel;
  final Color statusColor;
  final void Function(int questionIndex, String label) onAnswerSingle;

  const _SingleSelectChips({
    required this.questionIndex,
    required this.options,
    required this.selectedLabel,
    required this.statusColor,
    required this.onAnswerSingle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final opt in options)
          if (opt is Map<String, dynamic>)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Builder(
                builder: (context) {
                  final label = opt['label'] as String? ?? '';
                  final isChosen = selectedLabel == label;
                  return OutlinedButton.icon(
                    onPressed: () => onAnswerSingle(questionIndex, label),
                    icon: isChosen
                        ? Icon(Icons.check_circle, size: 16, color: statusColor)
                        : const SizedBox.shrink(),
                    label: Text(label, style: const TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      minimumSize: const Size(0, _buttonHeight),
                      foregroundColor: statusColor,
                      backgroundColor: isChosen
                          ? statusColor.withValues(alpha: 0.15)
                          : Colors.transparent,
                      side: BorderSide(
                        color: statusColor.withValues(
                          alpha: isChosen ? 0.6 : 0.3,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }
}

/// Multi-select option chips for a question.
class _MultiSelectChips extends StatelessWidget {
  final int questionIndex;
  final List<dynamic> options;
  final Set<String> selected;
  final Color statusColor;
  final void Function(int questionIndex, String label) onToggleLabel;

  const _MultiSelectChips({
    required this.questionIndex,
    required this.options,
    required this.selected,
    required this.statusColor,
    required this.onToggleLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final opt in options)
          if (opt is Map<String, dynamic>)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Builder(
                builder: (context) {
                  final label = opt['label'] as String? ?? '';
                  final isSelected = selected.contains(label);
                  return OutlinedButton.icon(
                    onPressed: () => onToggleLabel(questionIndex, label),
                    icon: Icon(
                      isSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: isSelected
                          ? statusColor
                          : statusColor.withValues(alpha: 0.5),
                    ),
                    label: Text(label, style: const TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      minimumSize: const Size(0, _buttonHeight),
                      alignment: Alignment.centerLeft,
                      foregroundColor: statusColor,
                      backgroundColor: isSelected
                          ? statusColor.withValues(alpha: 0.15)
                          : Colors.transparent,
                      side: BorderSide(
                        color: statusColor.withValues(
                          alpha: isSelected ? 0.6 : 0.3,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }
}

/// Confirm button for multi-select (used in single-question mode).
class _ConfirmButton extends StatelessWidget {
  final int questionIndex;
  final Set<String> selected;
  final Color statusColor;
  final void Function(int questionIndex) onConfirmMultiSelect;

  const _ConfirmButton({
    required this.questionIndex,
    required this.selected,
    required this.statusColor,
    required this.onConfirmMultiSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SizedBox(
        width: double.infinity,
        height: _buttonHeight,
        child: FilledButton.icon(
          onPressed: selected.isNotEmpty
              ? () => onConfirmMultiSelect(questionIndex)
              : null,
          icon: const Icon(Icons.check, size: 16),
          label: Text('Confirm (${selected.length})'),
          style: FilledButton.styleFrom(
            textStyle: const TextStyle(fontSize: 13),
            backgroundColor: statusColor.withValues(alpha: 0.15),
            foregroundColor: statusColor,
            disabledBackgroundColor: statusColor.withValues(alpha: 0.05),
            disabledForegroundColor: statusColor.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Other answer..." toggle button + inline text field.
class _OtherAnswerSection extends StatelessWidget {
  final int questionIndex;
  final bool isCustomInputShown;
  final bool isMultiQuestion;
  final Color statusColor;
  final TextEditingController controller;
  final void Function(int questionIndex, String text) onCustomTextChanged;
  final void Function(int questionIndex) onSubmitCustomText;
  final void Function(int questionIndex) onShowCustomInput;

  const _OtherAnswerSection({
    required this.questionIndex,
    required this.isCustomInputShown,
    required this.isMultiQuestion,
    required this.statusColor,
    required this.controller,
    required this.onCustomTextChanged,
    required this.onSubmitCustomText,
    required this.onShowCustomInput,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final canSubmit = controller.text.trim().isNotEmpty;

    if (isCustomInputShown) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Type your answer...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: statusColor.withValues(alpha: 0.4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: statusColor),
                  ),
                  isDense: true,
                ),
                onChanged: (text) => onCustomTextChanged(questionIndex, text),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: _buttonHeight,
              child: FilledButton(
                onPressed: canSubmit
                    ? () {
                        FocusScope.of(context).unfocus();
                        onSubmitCustomText(questionIndex);
                      }
                    : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  foregroundColor: statusColor,
                  disabledBackgroundColor: statusColor.withValues(alpha: 0.08),
                  disabledForegroundColor: statusColor.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  isMultiQuestion ? l.next : l.send,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: TextButton(
          onPressed: () => onShowCustomInput(questionIndex),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 36),
            textStyle: const TextStyle(fontSize: 12),
            foregroundColor: statusColor.withValues(alpha: 0.7),
          ),
          child: const Text('Other answer...'),
        ),
      ),
    );
  }
}

/// Common layout for a single question page.
/// Used by both inline (single-question) and PageView (multi-question) modes
/// to ensure consistent ordering: question -> options -> other answer -> confirm.
class _QuestionLayout extends StatelessWidget {
  final Map<String, dynamic> question;
  final int questionIndex;
  final Color statusColor;
  final bool isMultiQuestion;
  final bool allowsCustomInput;
  final Map<int, String> singleAnswers;
  final Map<int, Set<String>> multiAnswers;
  final Set<int> customInputs;
  final TextEditingController Function(int) getOrCreateController;
  final void Function(int questionIndex, String label) onAnswerSingle;
  final void Function(int questionIndex, String label) onToggleMultiSelectLabel;
  final void Function(int questionIndex) onConfirmMultiSelect;
  final void Function(int questionIndex) onSubmitCustomText;
  final void Function(int questionIndex, String text) onCustomTextChanged;
  final void Function(int questionIndex) onShowCustomInput;

  const _QuestionLayout({
    required this.question,
    required this.questionIndex,
    required this.statusColor,
    required this.isMultiQuestion,
    required this.allowsCustomInput,
    required this.singleAnswers,
    required this.multiAnswers,
    required this.customInputs,
    required this.getOrCreateController,
    required this.onAnswerSingle,
    required this.onToggleMultiSelectLabel,
    required this.onConfirmMultiSelect,
    required this.onSubmitCustomText,
    required this.onCustomTextChanged,
    required this.onShowCustomInput,
  });

  @override
  Widget build(BuildContext context) {
    final opts = question['options'] as List<dynamic>? ?? [];
    final isMulti = question['multiSelect'] as bool? ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _QuestionText(question: question),
        const SizedBox(height: 6),
        if (isMulti && opts.isNotEmpty)
          _MultiSelectChips(
            questionIndex: questionIndex,
            options: opts,
            selected: multiAnswers.putIfAbsent(questionIndex, () => {}),
            statusColor: statusColor,
            onToggleLabel: onToggleMultiSelectLabel,
          )
        else if (opts.isNotEmpty)
          _SingleSelectChips(
            questionIndex: questionIndex,
            options: opts,
            selectedLabel: singleAnswers[questionIndex],
            statusColor: statusColor,
            onAnswerSingle: onAnswerSingle,
          ),
        if (allowsCustomInput)
          _OtherAnswerSection(
            questionIndex: questionIndex,
            isCustomInputShown: customInputs.contains(questionIndex),
            isMultiQuestion: isMultiQuestion,
            statusColor: statusColor,
            controller: getOrCreateController(questionIndex),
            onCustomTextChanged: onCustomTextChanged,
            onSubmitCustomText: onSubmitCustomText,
            onShowCustomInput: onShowCustomInput,
          ),
        if (isMulti && !isMultiQuestion)
          _ConfirmButton(
            questionIndex: questionIndex,
            selected: multiAnswers[questionIndex] ?? {},
            statusColor: statusColor,
            onConfirmMultiSelect: onConfirmMultiSelect,
          ),
      ],
    );
  }
}

/// PageView for multi-question flows with step indicators and summary page.
class _QuestionPageView extends StatelessWidget {
  final List<dynamic> questions;
  final int currentPage;
  final PageController pageController;
  final Color statusColor;
  final bool isMultiQuestion;
  final bool allowsCustomInput;
  final Map<int, String> singleAnswers;
  final Map<int, Set<String>> multiAnswers;
  final Set<int> customInputs;
  final TextEditingController Function(int) getOrCreateController;
  final void Function(int questionIndex, String label) onAnswerSingle;
  final void Function(int questionIndex, String label) onToggleMultiSelectLabel;
  final void Function(int questionIndex) onConfirmMultiSelect;
  final void Function(int questionIndex) onSubmitCustomText;
  final void Function(int questionIndex, String text) onCustomTextChanged;
  final void Function(int questionIndex) onShowCustomInput;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onGoToPage;
  final VoidCallback onResetAll;
  final VoidCallback onSubmitAll;

  const _QuestionPageView({
    required this.questions,
    required this.currentPage,
    required this.pageController,
    required this.statusColor,
    required this.isMultiQuestion,
    required this.allowsCustomInput,
    required this.singleAnswers,
    required this.multiAnswers,
    required this.customInputs,
    required this.getOrCreateController,
    required this.onAnswerSingle,
    required this.onToggleMultiSelectLabel,
    required this.onConfirmMultiSelect,
    required this.onSubmitCustomText,
    required this.onCustomTextChanged,
    required this.onShowCustomInput,
    required this.onPageChanged,
    required this.onGoToPage,
    required this.onResetAll,
    required this.onSubmitAll,
  });

  @override
  Widget build(BuildContext context) {
    final totalPages = isMultiQuestion
        ? questions.length + 1
        : questions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minimal step indicators: 1 of 3
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                currentPage < questions.length
                    ? ((questions[currentPage]
                                  as Map<String, dynamic>)['header']
                              as String? ??
                          'Q${currentPage + 1}')
                    : 'Review Summary',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor.withValues(alpha: 0.8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${currentPage + 1} of $totalPages',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Progress bar instead of bulky chips
        LinearProgressIndicator(
          value: (currentPage + 1) / totalPages,
          backgroundColor: statusColor.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          minHeight: 2,
        ),
        const SizedBox(height: 10),
        // Dynamic height container based on content, avoiding rigid PageView size
        ExpandablePageView.builder(
          controller: pageController,
          itemCount: totalPages,
          onPageChanged: onPageChanged,
          itemBuilder: (context, index) {
            if (index == questions.length) {
              return _SummaryPage(
                questions: questions,
                statusColor: statusColor,
                singleAnswers: singleAnswers,
                multiAnswers: multiAnswers,
                customControllers: getOrCreateController,
                onGoToPage: onGoToPage,
                onResetAll: onResetAll,
                onSubmitAll: onSubmitAll,
              );
            }
            return _QuestionLayout(
              question: questions[index] as Map<String, dynamic>,
              questionIndex: index,
              statusColor: statusColor,
              isMultiQuestion: isMultiQuestion,
              allowsCustomInput: allowsCustomInput,
              singleAnswers: singleAnswers,
              multiAnswers: multiAnswers,
              customInputs: customInputs,
              getOrCreateController: getOrCreateController,
              onAnswerSingle: onAnswerSingle,
              onToggleMultiSelectLabel: onToggleMultiSelectLabel,
              onConfirmMultiSelect: onConfirmMultiSelect,
              onSubmitCustomText: onSubmitCustomText,
              onCustomTextChanged: onCustomTextChanged,
              onShowCustomInput: onShowCustomInput,
            );
          },
        ),
      ],
    );
  }
}

/// Summary page showing all answers with Submit/Cancel buttons.
class _SummaryPage extends StatelessWidget {
  final List<dynamic> questions;
  final Color statusColor;
  final Map<int, String> singleAnswers;
  final Map<int, Set<String>> multiAnswers;
  final TextEditingController Function(int) customControllers;
  final ValueChanged<int> onGoToPage;
  final VoidCallback onResetAll;
  final VoidCallback onSubmitAll;

  const _SummaryPage({
    required this.questions,
    required this.statusColor,
    required this.singleAnswers,
    required this.multiAnswers,
    required this.customControllers,
    required this.onGoToPage,
    required this.onResetAll,
    required this.onSubmitAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Review your answers',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < questions.length; i++) ...[
            _SummaryRow(
              index: i,
              question: questions[i] as Map<String, dynamic>,
              statusColor: statusColor,
              singleAnswers: singleAnswers,
              multiAnswers: multiAnswers,
              customControllers: customControllers,
              onGoToPage: onGoToPage,
            ),
            if (i < questions.length - 1) const SizedBox(height: 6),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: onResetAll,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      side: BorderSide(color: cs.outlineVariant),
                      foregroundColor: cs.onSurfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: FilledButton(
                    onPressed: onSubmitAll,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      backgroundColor: statusColor,
                      foregroundColor: statusColor.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Submit',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.send, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single row in the summary page showing the answer for one question.
class _SummaryRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> question;
  final Color statusColor;
  final Map<int, String> singleAnswers;
  final Map<int, Set<String>> multiAnswers;
  final TextEditingController Function(int) customControllers;
  final ValueChanged<int> onGoToPage;

  const _SummaryRow({
    required this.index,
    required this.question,
    required this.statusColor,
    required this.singleAnswers,
    required this.multiAnswers,
    required this.customControllers,
    required this.onGoToPage,
  });

  @override
  Widget build(BuildContext context) {
    final header = question['header'] as String? ?? 'Q${index + 1}';
    final isMulti = question['multiSelect'] as bool? ?? false;

    // Compute combined answer for summary
    String? answer;
    if (isMulti) {
      final selected = multiAnswers[index] ?? {};
      final parts = [...selected];
      final customText = customControllers(index).text.trim();
      if (customText.isNotEmpty) parts.add(customText);
      answer = parts.isNotEmpty ? parts.join(', ') : null;
    } else {
      answer = singleAnswers[index];
    }

    final hasAnswer = answer != null && answer.isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onGoToPage(index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: cs.surfaceContainerLowest,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasAnswer ? Icons.check_circle : Icons.error_outline,
              size: 14,
              color: hasAnswer ? statusColor : cs.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    header,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasAnswer ? answer : '(No answer selected)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: hasAnswer ? cs.onSurface : cs.error,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.edit,
              size: 14,
              color: statusColor.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool animate;
  final bool glow;
  const _StatusDot({
    required this.color,
    required this.animate,
    this.glow = false,
  });

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // reducedMotion needs a BuildContext, so the repeat() decision lives here
    // (and didUpdateWidget) rather than initState.
    _syncPulse();
  }

  @override
  void didUpdateWidget(_StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  /// Runs the pulse only when animation is requested and the user has not
  /// asked for reduced motion; otherwise settles on the static, full-opacity
  /// end-state of the pulse.
  void _syncPulse() {
    final shouldPulse = widget.animate && !reducedMotion(context);
    if (shouldPulse) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      if (_pulseController.isAnimating) _pulseController.stop();
      // An animating dot under reduced motion settles "on" (1.0) so it stays
      // visible; a static idle/ready dot keeps its original muted look
      // (value 0.0 -> pulseAnimation 0.4 alpha). Do NOT force idle dots to 1.0.
      _pulseController.value = widget.animate ? 1.0 : 0.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(14, 14),
          painter: _StatusDotPainter(
            color: widget.color,
            pulseValue: _pulseAnimation.value,
            animate: widget.animate,
            glow: widget.glow,
          ),
        );
      },
    );
  }
}

class _StatusDotPainter extends CustomPainter {
  final Color color;
  final double pulseValue;
  final bool animate;
  final bool glow;

  _StatusDotPainter({
    required this.color,
    required this.pulseValue,
    required this.animate,
    this.glow = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const dotRadius = 5.0;

    // Glow behind the dot (animated pulse or static unseen glow)
    if (animate) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: pulseValue * 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(center, dotRadius + 1.5, glowPaint);
    } else if (glow) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(center, dotRadius + 1.5, glowPaint);
    }

    // Main dot
    final dotPaint = Paint()..color = color.withValues(alpha: pulseValue);
    canvas.drawCircle(center, dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(_StatusDotPainter oldDelegate) =>
      oldDelegate.pulseValue != pulseValue ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow ||
      oldDelegate.animate != animate;
}

/// Provider identity as a single bare tinted icon glyph (no word pill),
/// exposing the provider's full label via Semantics/Tooltip.
class _ProviderGlyph extends StatelessWidget {
  final Provider provider;

  const _ProviderGlyph({required this.provider});

  @override
  Widget build(BuildContext context) {
    final style = providerStyleFor(context, provider);
    final label = provider.label;
    return Semantics(
      label: '$label session',
      child: Tooltip(
        message: label,
        child: Icon(
          style.icon,
          size: AppIconSize.chip,
          color: style.foreground,
        ),
      ),
    );
  }
}

/// The session identity block: the bold session [title] (name when present,
/// else project name) on top, allowed two lines so a long name wraps instead
/// of being amputated. The project ([projectSuffix]) rides its own dedicated
/// line below, with an independent ellipsis budget, so a long name can never
/// squeeze the project out of view and the two never compete on one row. The
/// optional [agentLabel] sits on its own muted micro-line so it can never
/// starve the project. Flat text only — no nested glyph, chip fill, or wash;
/// hierarchy is carried by weight and color.
class _SessionTitle extends StatelessWidget {
  final String title;
  final String? projectSuffix;
  final String? agentLabel;

  const _SessionTitle({
    required this.title,
    this.projectSuffix,
    this.agentLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.extension<AppColors>()!;
    final colorScheme = theme.colorScheme;
    final hasProject = projectSuffix != null;
    // Hero line. Slightly under titleMedium(16) so the name leads on weight,
    // not raw size. Allowed TWO lines whether or not a project follows — a long
    // name degrades to a wrap, never a hard 1-line ellipsis. The project below
    // is on its own row, so it is never the thing dropped to fit the name.
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: colorScheme.onSurface,
    );
    // Project line: onSurfaceVariant + medium weight so it reads as real,
    // second-tier identity, fully legible — not a throwaway suffix.
    final projectStyle = theme.textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );
    // Agent label: lowest-priority tertiary token, on its own muted micro-line
    // so it can never starve the project text for width.
    final agentStyle = theme.textTheme.labelSmall?.copyWith(
      color: appColors.subtleText,
      fontWeight: FontWeight.w500,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: titleStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasProject) ...[
          const SizedBox(height: 3),
          Text(
            projectSuffix!,
            style: projectStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (agentLabel != null) ...[
          const SizedBox(height: 2),
          Text(
            agentLabel!,
            style: agentStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

String? _formatAgentLabel(String? nickname, String? role) {
  final trimmedNickname = nickname?.trim();
  final trimmedRole = role?.trim();
  final hasNickname = trimmedNickname != null && trimmedNickname.isNotEmpty;
  final hasRole = trimmedRole != null && trimmedRole.isNotEmpty;
  if (!hasNickname && !hasRole) return null;
  if (hasNickname && hasRole) return '$trimmedNickname [$trimmedRole]';
  return hasNickname ? trimmedNickname : '[$trimmedRole]';
}

/// The message preview — the visual anchor of a session card. Shared by both
/// card types so the most-read line is styled identically. When [text] is
/// empty, renders a designed muted-italic placeholder instead of a literal
/// "(no description)" string styled like real content.
class _SessionMessage extends StatelessWidget {
  final String text;

  /// Preview line cap. Defaults to 2 (the "medium" anchor) so existing call
  /// sites are unaffected; the session list passes 1 only while an approval
  /// area is open so an actionable card stays compact.
  final int maxLines;

  const _SessionMessage({required this.text, this.maxLines = 2});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.extension<AppColors>()!;
    final hasText = text.isNotEmpty;
    return Text(
      hasText ? text : AppLocalizations.of(context).noPromptHistoryYet,
      // Secondary to the title: 13px and slightly dimmed so it supports rather
      // than competes (a full-strength 14px 2-line block read as heavy).
      style: hasText
          ? theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              height: 1.35,
            )
          : theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: appColors.subtleText,
              fontStyle: FontStyle.italic,
              height: 1.35,
            ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class RecentSessionCard extends StatelessWidget {
  final RecentSession session;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<Offset?>? onShowActions;
  final bool hideProjectBadge;
  final SessionDisplayMode displayMode;
  final String? draftText;
  final bool isProcessing;
  final bool isSelected;

  const RecentSessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.onShowActions,
    this.hideProjectBadge = false,
    this.displayMode = SessionDisplayMode.first,
    this.draftText,
    this.isProcessing = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.extension<AppColors>()!;
    final provider = providerFromRaw(session.provider);
    final agentLabel = _formatAgentLabel(
      session.agentNickname,
      session.agentRole,
    );
    final dateStr = _formatDateRange(session.created, session.modified);

    final card = Card(
      margin: const EdgeInsets.symmetric(
        vertical: AppSpacing.xs,
        horizontal: 0,
      ),
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.9)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 2.2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isProcessing ? null : onTap,
        onLongPress: isProcessing || onShowActions != null ? null : onLongPress,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1 — identity: provider glyph + the title block, then
                  // time. No live status dot/word (history, not live).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _ProviderGlyph(provider: provider),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _SessionTitle(
                          title:
                              session.name != null && session.name!.isNotEmpty
                              ? session.name!
                              : session.projectName,
                          projectSuffix:
                              !hideProjectBadge &&
                                  session.name != null &&
                                  session.name!.isNotEmpty &&
                                  session.name! != session.projectName
                              ? session.projectName
                              : null,
                          agentLabel: agentLabel,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // Cap the timestamp width so the title (Expanded) always
                      // wins the leftover space — a long "M/D HH:MM–M/D HH:MM"
                      // range ellipsizes inside its 132px box instead of
                      // squeezing the title.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 132),
                        child: Text(
                          dateStr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: appColors.subtleText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  // Row 2 — preview (the anchor). Keep the draftText italic
                  // override branch; both obey the medium 2-line cap.
                  const SizedBox(height: 6),
                  if (draftText != null && draftText!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: _sessionCardTextRailIndent,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 2,
                              right: AppSpacing.xs + 2,
                            ),
                            child: Icon(
                              Icons.edit_note,
                              size: AppIconSize.inline,
                              color: appColors.subtleText,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              draftText!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: appColors.subtleText,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(
                        left: _sessionCardTextRailIndent,
                      ),
                      child: _SessionMessage(
                        text: _displayTextForMode(session, displayMode),
                        maxLines: 2,
                      ),
                    ),
                ],
              ),
            ),
            if (isProcessing)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.55),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (isProcessing || onShowActions == null) return card;
    return AdaptiveContextMenuRegion(onOpen: onShowActions!, child: card);
  }

  /// Returns the message text for the active display mode, or an empty string
  /// when there is genuinely no content. The empty case is rendered by
  /// [_SessionMessage] as a designed, muted placeholder rather than a literal
  /// "(no description)" string styled like a real message.
  static String _displayTextForMode(
    RecentSession session,
    SessionDisplayMode mode,
  ) {
    final String raw;
    switch (mode) {
      case SessionDisplayMode.first:
        raw = session.firstPrompt.isNotEmpty
            ? session.firstPrompt
            : session.displayText;
      case SessionDisplayMode.last:
        raw = session.lastPrompt ?? session.firstPrompt;
      case SessionDisplayMode.summary:
        raw = session.summary ?? session.firstPrompt;
    }
    return formatCommandText(raw);
  }

  String _formatDateRange(String createdIso, String modifiedIso) {
    if (modifiedIso.isEmpty) return _formatDate(createdIso);
    final modified = _formatDate(modifiedIso);
    if (createdIso.isEmpty || createdIso == modifiedIso) return modified;
    try {
      final first = DateTime.parse(createdIso).toLocal();
      final last = DateTime.parse(modifiedIso).toLocal();
      // Same minute → single timestamp
      if (first.year == last.year &&
          first.month == last.month &&
          first.day == last.day &&
          first.hour == last.hour &&
          first.minute == last.minute) {
        return modified;
      }
      final firstTime =
          '${first.hour.toString().padLeft(2, '0')}:${first.minute.toString().padLeft(2, '0')}';
      final lastTime =
          '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}';
      // Same day → "Today 10:00–12:30"
      if (first.year == last.year &&
          first.month == last.month &&
          first.day == last.day) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final dtDate = DateTime(first.year, first.month, first.day);
        if (dtDate == today) return 'Today $firstTime–$lastTime';
        if (dtDate == yesterday) return 'Yesterday $firstTime–$lastTime';
        return '${first.month}/${first.day} $firstTime–$lastTime';
      }
      // Different days → "1/10 10:00–1/11 12:30"
      return '${first.month}/${first.day} $firstTime–${last.month}/${last.day} $lastTime';
    } catch (_) {
      return modified;
    }
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final dtDate = DateTime(dt.year, dt.month, dt.day);

      final time =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

      if (dtDate == today) return 'Today $time';
      if (dtDate == yesterday) return 'Yesterday $time';
      return '${dt.month}/${dt.day} $time';
    } catch (_) {
      return '';
    }
  }
}
