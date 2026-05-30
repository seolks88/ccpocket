import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/messages.dart';
import '../../../services/bridge_service.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../state/chat_session_state.dart';
import '../state/chat_session_cubit.dart';

/// Total rendered height of the floating [SessionModeBar], derived from its
/// fixed geometry so a scroll view behind it can reserve a matching top inset
/// (the bar is positioned over the chat list, so without this the first
/// conversation lines scroll underneath it and get clipped).
///
/// Breakdown: chip hit area ([AppSizes.minTouchTarget]) + inner container
/// vertical padding ([_kBarContainerPaddingV] * 2) + outer vertical padding
/// ([_kBarOuterPaddingV] * 2).
const double kSessionModeBarHeight =
    AppSizes.minTouchTarget +
    (_kBarContainerPaddingV * 2) +
    (_kBarOuterPaddingV * 2);

const double _kBarContainerPaddingV = 2;
const double _kBarOuterPaddingV = 6;

class SessionModeBar extends StatelessWidget {
  final Future<void> Function()? onBeforeRestart;

  const SessionModeBar({super.key, this.onBeforeRestart});

  @override
  Widget build(BuildContext context) {
    final chatCubit = context.watch<ChatSessionCubit>();
    final executionMode = chatCubit.state.executionMode;
    final planMode = chatCubit.state.planMode;
    final inPlanMode = chatCubit.state.inPlanMode;
    final status = chatCubit.state.status;
    final isActive =
        status == ProcessStatus.running ||
        status == ProcessStatus.waitingApproval ||
        status == ProcessStatus.compacting;
    final sandboxMode = chatCubit.state.sandboxMode;
    final permissionMode = chatCubit.state.permissionMode;
    final isCodex = chatCubit.provider == Provider.codex;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: _kBarContainerPaddingV,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? cs.surface.withValues(alpha: 0.6)
                : cs.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCodex) ...[
                  PlanModeChip(
                    enabled: planMode,
                    activeGlow: false,
                    onTap: () => togglePlanMode(
                      context,
                      chatCubit,
                      onBeforeRestart: onBeforeRestart,
                    ),
                  ),
                  ValueListenableBuilder<ReasoningEffort>(
                    valueListenable: chatCubit.modelReasoningEffortListenable,
                    builder: (context, effort, _) => ThinkingEffortChip(
                      currentEffort: effort,
                      onTap: () =>
                          showCodexReasoningEffortMenu(context, chatCubit),
                    ),
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: chatCubit.serviceTierListenable,
                    builder: (context, serviceTier, _) => ServiceTierChip(
                      serviceTier: serviceTier,
                      onTap: () => showCodexServiceTierMenu(context, chatCubit),
                    ),
                  ),
                  ExecutionModeChip(
                    currentMode: executionMode,
                    codexApprovalPolicy: chatCubit.state.codexApprovalPolicy,
                    codexApprovalsReviewer:
                        chatCubit.state.codexApprovalsReviewer,
                    codexPermissionsMode: chatCubit.state.codexPermissionsMode,
                    provider: chatCubit.provider,
                    onTap: () => showCodexPermissionsMenu(
                      context,
                      chatCubit,
                      onBeforeRestart: onBeforeRestart,
                    ),
                  ),
                ] else ...[
                  PermissionModeChip(
                    currentMode: permissionMode,
                    onTap: () => showPermissionModeMenu(
                      context,
                      chatCubit,
                      onBeforeRestart: onBeforeRestart,
                    ),
                  ),
                  ValueListenableBuilder<ClaudeSessionRuntimeSettings>(
                    valueListenable: chatCubit.claudeSettingsListenable,
                    builder: (context, settings, _) => ClaudeModelChip(
                      model: settings.model,
                      onTap: () => showClaudeModelMenu(
                        context,
                        chatCubit,
                        onBeforeRestart: onBeforeRestart,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<ClaudeSessionRuntimeSettings>(
                    valueListenable: chatCubit.claudeSettingsListenable,
                    builder: (context, settings, _) => ClaudeThinkingChip(
                      effort: settings.effort,
                      onTap: () => showClaudeEffortMenu(
                        context,
                        chatCubit,
                        onBeforeRestart: onBeforeRestart,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<ClaudeSessionRuntimeSettings>(
                    valueListenable: chatCubit.claudeSettingsListenable,
                    builder: (context, settings, _) => ClaudeFastModeChip(
                      enabled: settings.fastMode,
                      actualState: settings.fastModeState,
                      onTap: () async {
                        final nextFastMode = !settings.fastMode;
                        final nextModel =
                            nextFastMode &&
                                !_isClaudeFastModeCapableModel(
                                  _effectiveClaudeModel(settings),
                                )
                            ? _preferredClaudeFastModeModel(context)
                            : null;
                        await onBeforeRestart?.call();
                        HapticFeedback.lightImpact();
                        chatCubit.setClaudeSessionOptions(
                          model: nextModel,
                          fastMode: nextFastMode,
                        );
                      },
                    ),
                  ),
                  ValueListenableBuilder<ClaudeSessionRuntimeSettings>(
                    valueListenable: chatCubit.claudeSettingsListenable,
                    builder: (context, settings, _) => ClaudeBillingChip(
                      settings: settings,
                      onTap: () => showClaudeBillingSheet(context, settings),
                    ),
                  ),
                ],
                if (!isCodex) ...[
                  SandboxModeChip(
                    currentMode: sandboxMode,
                    provider: chatCubit.provider,
                    onTap: () => showSandboxModeMenu(
                      context,
                      chatCubit,
                      onBeforeRestart: onBeforeRestart,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: _kBarOuterPaddingV,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _PulsingModeBarSurface(
          inPlanMode: inPlanMode && isActive,
          child: bar,
        ),
      ),
    );
  }
}

class _PulsingModeBarSurface extends StatefulWidget {
  final bool inPlanMode;
  final Widget child;

  const _PulsingModeBarSurface({
    super.key,
    required this.inPlanMode,
    required this.child,
  });

  @override
  State<_PulsingModeBarSurface> createState() => _PulsingModeBarSurfaceState();
}

class _PulsingModeBarSurfaceState extends State<_PulsingModeBarSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // reducedMotion() needs a BuildContext (unavailable in initState), so the
    // repeat() decision lives here (also re-runs on reduced-motion changes).
    _syncGlow();
  }

  @override
  void didUpdateWidget(_PulsingModeBarSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncGlow();
  }

  /// Rotates the plan-mode border glow only while in plan mode and motion is
  /// allowed; otherwise the border is painted as a calm static tint.
  void _syncGlow() {
    final shouldAnimate = widget.inPlanMode && !reducedMotion(context);
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!widget.inPlanMode) {
      return widget.child;
    }

    // Under reduced motion the controller is parked; paint a calm static tinted
    // border (no rotating glow dot) instead of the moving sweep.
    if (reducedMotion(context)) {
      return CustomPaint(
        painter: _RotatingBorderPainter(
          progress: 0,
          animate: false,
          color: appColors.statusPlan,
          glowColor: appColors.statusPlanGlow,
          borderRadius: 12,
          strokeWidth: 1.5,
          isDark: isDark,
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return CustomPaint(
          painter: _RotatingBorderPainter(
            progress: _controller.value,
            color: appColors.statusPlan,
            glowColor: appColors.statusPlanGlow,
            borderRadius: 12,
            strokeWidth: 1.5,
            isDark: isDark,
          ),
          child: child,
        );
      },
    );
  }
}

class _RotatingBorderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color glowColor;
  final double borderRadius;
  final double strokeWidth;
  final bool isDark;

  /// When false (reduced motion), only the static base border is painted and
  /// the rotating glow dot is skipped entirely.
  final bool animate;

  _RotatingBorderPainter({
    required this.progress,
    required this.color,
    required this.glowColor,
    required this.borderRadius,
    required this.strokeWidth,
    required this.isDark,
    this.animate = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Subtle base border
    final basePaint = Paint()
      ..color = color.withValues(alpha: isDark ? 0.12 : 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRRect(rrect, basePaint);

    // Reduced motion: stop at the calm static tinted border.
    if (!animate) return;

    // Build path from the rounded rect and find the dot position
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final totalLen = metric.length;
    final dotOffset = metric.getTangentForOffset(totalLen * progress)!.position;

    // Radial gradient centered on the dot for a clean glow
    final glowRadius = 18.0;
    final dotRect = Rect.fromCircle(center: dotOffset, radius: glowRadius);
    final radial = RadialGradient(
      colors: [
        glowColor.withValues(alpha: isDark ? 0.85 : 0.7),
        color.withValues(alpha: isDark ? 0.4 : 0.25),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 1.0],
    );

    // Clip to border stroke region (outer rrect minus inner rrect)
    final halfW = (strokeWidth + 4) / 2;
    final outerRRect = RRect.fromRectAndRadius(
      rect.inflate(halfW),
      Radius.circular(borderRadius + halfW),
    );
    final innerRRect = RRect.fromRectAndRadius(
      rect.deflate(halfW),
      Radius.circular((borderRadius - halfW).clamp(0, double.infinity)),
    );
    final clipPath = Path()
      ..addRRect(outerRRect)
      ..addRRect(innerRRect)
      ..fillType = PathFillType.evenOdd;

    canvas.save();
    canvas.clipPath(clipPath);

    // Outer glow
    final glowPaint = Paint()
      ..shader = radial.createShader(dotRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRect(dotRect, glowPaint);

    // Bright core
    final coreRect = Rect.fromCircle(center: dotOffset, radius: 8);
    final coreGradient = RadialGradient(
      colors: [
        glowColor.withValues(alpha: isDark ? 1.0 : 0.9),
        color.withValues(alpha: isDark ? 0.5 : 0.35),
        Colors.transparent,
      ],
      stops: const [0.0, 0.4, 1.0],
    );
    final corePaint = Paint()..shader = coreGradient.createShader(coreRect);
    canvas.drawRect(coreRect, corePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_RotatingBorderPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.animate != animate;
}

void showCodexPermissionsMenu(
  BuildContext context,
  ChatSessionCubit chatCubit, {
  Future<void> Function()? onBeforeRestart,
}) {
  if (chatCubit.provider != Provider.codex) {
    showPermissionModeMenu(
      context,
      chatCubit,
      onBeforeRestart: onBeforeRestart,
    );
    return;
  }
  final currentMode = chatCubit.state.codexPermissionsMode;

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final sheetCs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Permissions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: sheetCs.onSurface,
                    ),
                  ),
                ),
              ),
              for (final mode in CodexPermissionsMode.values)
                ListTile(
                  leading: Icon(
                    _codexPermissionsIcon(mode),
                    color: mode == currentMode
                        ? (mode == CodexPermissionsMode.fullAccess
                              ? sheetCs.error
                              : sheetCs.primary)
                        : sheetCs.onSurfaceVariant,
                  ),
                  title: Text(mode.label),
                  subtitle: Text(
                    _codexPermissionsSubtitle(
                      mode,
                      AppLocalizations.of(context),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: mode == currentMode
                      ? Icon(
                          Icons.check,
                          color: mode == CodexPermissionsMode.fullAccess
                              ? sheetCs.error
                              : sheetCs.primary,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (mode == currentMode) return;
                    HapticFeedback.lightImpact();
                    _confirmCodexPermissionsModeChange(
                      context,
                      chatCubit,
                      mode,
                      onBeforeRestart: onBeforeRestart,
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

void showCodexReasoningEffortMenu(
  BuildContext context,
  ChatSessionCubit chatCubit,
) {
  if (!chatCubit.isCodex) return;
  final currentEffort = chatCubit.modelReasoningEffort;
  final efforts = _codexReasoningEffortsForSession(context, chatCubit);
  final l = AppLocalizations.of(context);

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final sheetCs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reasoning',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: sheetCs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Current: ${_reasoningEffortDisplayLabel(currentEffort)} - applies from the next message.',
                        style: TextStyle(
                          fontSize: 12,
                          color: sheetCs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final effort in efforts)
                ListTile(
                  leading: Icon(
                    _reasoningEffortIcon(effort),
                    color: effort == currentEffort
                        ? sheetCs.primary
                        : sheetCs.onSurfaceVariant,
                  ),
                  title: Text(_reasoningEffortDisplayLabel(effort)),
                  subtitle: Text(
                    _reasoningEffortDescription(effort, l),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: effort == currentEffort
                      ? Icon(Icons.check, color: sheetCs.primary, size: 20)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (effort == currentEffort) return;
                    HapticFeedback.lightImpact();
                    chatCubit.setModelReasoningEffort(effort);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

void showCodexServiceTierMenu(
  BuildContext context,
  ChatSessionCubit chatCubit,
) {
  if (!chatCubit.isCodex) return;
  final currentTier = chatCubit.serviceTier;
  final tiers = _codexServiceTiersForSession(context, chatCubit, currentTier);

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final sheetCs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Service tier',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: sheetCs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Current: ${_serviceTierLabel(currentTier, tiers)} - applies from the next message.',
                        style: TextStyle(
                          fontSize: 12,
                          color: sheetCs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.tune,
                  color: currentTier == null
                      ? sheetCs.primary
                      : sheetCs.onSurfaceVariant,
                ),
                title: const Text('Default'),
                subtitle: const Text(
                  'Use Codex config default',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: currentTier == null
                    ? Icon(Icons.check, color: sheetCs.primary, size: 20)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (currentTier == null) return;
                  HapticFeedback.lightImpact();
                  chatCubit.setServiceTier(null);
                },
              ),
              for (final tier in tiers)
                ListTile(
                  leading: Icon(
                    Icons.flash_on_outlined,
                    color: tier.id == currentTier
                        ? sheetCs.primary
                        : sheetCs.onSurfaceVariant,
                  ),
                  title: Text(_serviceTierLabel(tier.id, tiers)),
                  subtitle: Text(
                    tier.description?.isNotEmpty == true
                        ? tier.description!
                        : 'Service tier: ${tier.id}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: tier.id == currentTier
                      ? Icon(Icons.check, color: sheetCs.primary, size: 20)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (tier.id == currentTier) return;
                    HapticFeedback.lightImpact();
                    chatCubit.setServiceTier(tier.id);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

List<ReasoningEffort> _codexReasoningEffortsForSession(
  BuildContext context,
  ChatSessionCubit chatCubit,
) {
  final fallback = ReasoningEffort.values.toList(growable: false);
  final bridge = context.read<BridgeService>();
  SessionInfo? session;
  for (final candidate in bridge.sessions) {
    if (candidate.id == chatCubit.sessionId) {
      session = candidate;
      break;
    }
  }
  final model = sanitizeCodexModelName(session?.codexModel);
  final raw = model == null
      ? const <String>[]
      : bridge.codexModelReasoningEfforts[model] ?? const <String>[];
  if (raw.isEmpty) return fallback;

  final efforts = <ReasoningEffort>[ReasoningEffort.none];
  for (final value in raw) {
    final effort = _reasoningEffortFromRaw(value);
    if (effort != null && !efforts.contains(effort)) {
      efforts.add(effort);
    }
  }
  return efforts.length > 1 ? efforts : fallback;
}

List<CodexServiceTier> _codexServiceTiersForSession(
  BuildContext context,
  ChatSessionCubit chatCubit,
  String? currentTier,
) {
  final bridge = context.read<BridgeService>();
  SessionInfo? session;
  for (final candidate in bridge.sessions) {
    if (candidate.id == chatCubit.sessionId) {
      session = candidate;
      break;
    }
  }
  final model = sanitizeCodexModelName(session?.codexModel);
  final tiers = model == null
      ? const <CodexServiceTier>[]
      : bridge.codexModelServiceTiers[model] ?? const <CodexServiceTier>[];
  final byId = <String, CodexServiceTier>{
    for (final tier in tiers)
      if (tier.id.isNotEmpty) tier.id: tier,
  };
  if (currentTier != null &&
      currentTier.isNotEmpty &&
      !byId.containsKey(currentTier)) {
    byId[currentTier] = CodexServiceTier(
      id: currentTier,
      name: _serviceTierFallbackName(currentTier),
    );
  }
  return byId.values.toList(growable: false);
}

ReasoningEffort? _reasoningEffortFromRaw(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final effort in ReasoningEffort.values) {
    if (effort.value == raw) return effort;
  }
  return null;
}

IconData _reasoningEffortIcon(ReasoningEffort effort) => switch (effort) {
  ReasoningEffort.none => Icons.block,
  ReasoningEffort.minimal => Icons.bolt_outlined,
  ReasoningEffort.low => Icons.speed,
  ReasoningEffort.medium => Icons.lightbulb_outline,
  ReasoningEffort.high => Icons.psychology,
  ReasoningEffort.xhigh => Icons.auto_awesome,
};

String _reasoningEffortDisplayLabel(ReasoningEffort effort) => switch (effort) {
  ReasoningEffort.none => 'None',
  ReasoningEffort.minimal => 'Minimal',
  ReasoningEffort.low => 'Low',
  ReasoningEffort.medium => 'Medium',
  ReasoningEffort.high => 'High',
  ReasoningEffort.xhigh => 'X High',
};

String _serviceTierFallbackName(String serviceTier) {
  final normalized = serviceTier.trim().toLowerCase();
  if (normalized == 'priority' || normalized == 'fast') return 'Fast';
  return serviceTier;
}

String _serviceTierLabel(String? serviceTier, List<CodexServiceTier> tiers) {
  if (serviceTier == null || serviceTier.isEmpty) return 'Default';
  for (final tier in tiers) {
    if (tier.id == serviceTier) {
      final label = tier.label;
      return label == tier.id ? _serviceTierFallbackName(serviceTier) : label;
    }
  }
  return _serviceTierFallbackName(serviceTier);
}

String _reasoningEffortDescription(
  ReasoningEffort effort,
  AppLocalizations l,
) => switch (effort) {
  ReasoningEffort.none => l.reasoningEffortNoneDesc,
  ReasoningEffort.minimal => l.reasoningEffortMinimalDesc,
  ReasoningEffort.low => l.reasoningEffortLowDesc,
  ReasoningEffort.medium => l.reasoningEffortMediumDesc,
  ReasoningEffort.high => l.reasoningEffortHighDesc,
  ReasoningEffort.xhigh => l.reasoningEffortXhighDesc,
};

/// Show confirmation dialog before changing permission mode for Codex sessions,
/// because the change requires a session restart (like sandbox mode).
Future<void> _confirmCodexPermissionsModeChange(
  BuildContext context,
  ChatSessionCubit chatCubit,
  CodexPermissionsMode mode, {
  Future<void> Function()? onBeforeRestart,
}) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final cs = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(l.changeApprovalPolicyTitle),
        content: Text(l.changeApprovalPolicyBody(mode.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: mode == CodexPermissionsMode.fullAccess
                ? FilledButton.styleFrom(backgroundColor: cs.error)
                : null,
            child: Text(l.restart),
          ),
        ],
      );
    },
  );
  if (confirmed == true) {
    await onBeforeRestart?.call();
    chatCubit.setCodexPermissionsMode(mode);
  }
}

Future<void> togglePlanMode(
  BuildContext context,
  ChatSessionCubit chatCubit, {
  Future<void> Function()? onBeforeRestart,
}) async {
  final nextPlanMode = !chatCubit.state.planMode;
  final hasPendingApproval = chatCubit.state.approval is! ApprovalNone;
  final l = AppLocalizations.of(context);
  final canToggleInPlace =
      chatCubit.isCodex &&
      chatCubit.state.status == ProcessStatus.idle &&
      !hasPendingApproval;

  if (canToggleInPlace) {
    HapticFeedback.lightImpact();
    chatCubit.setSessionModes(planMode: nextPlanMode);
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          nextPlanMode ? l.enablePlanModeTitle : l.disablePlanModeTitle,
        ),
        content: Text(
          nextPlanMode ? l.enablePlanModeBody : l.disablePlanModeBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.restart),
          ),
        ],
      );
    },
  );
  if (confirmed == true) {
    await onBeforeRestart?.call();
    chatCubit.setSessionModes(planMode: nextPlanMode);
  }
}

void showSandboxModeMenu(
  BuildContext context,
  ChatSessionCubit chatCubit, {
  Future<void> Function()? onBeforeRestart,
}) {
  final currentMode = chatCubit.state.sandboxMode;
  final isClaude = chatCubit.provider != Provider.codex;
  final l = AppLocalizations.of(context);

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final sheetCs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sandbox',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: sheetCs.onSurface,
                  ),
                ),
              ),
            ),
            for (final mode
                in isClaude ? SandboxMode.values.reversed : SandboxMode.values)
              ListTile(
                leading: Icon(
                  _sandboxMenuIcon(mode, isClaude),
                  color: mode == currentMode
                      ? sheetCs.primary
                      : _sandboxMenuIconColor(mode, isClaude, sheetCs),
                ),
                title: Text(
                  _sandboxMenuTitle(mode, isClaude),
                  style: TextStyle(
                    color:
                        !isClaude &&
                            mode == SandboxMode.off &&
                            currentMode != mode
                        ? sheetCs.error
                        : null,
                  ),
                ),
                subtitle: Text(
                  _sandboxMenuSubtitle(mode, isClaude, l),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: mode == currentMode
                    ? Icon(Icons.check, color: sheetCs.primary, size: 20)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (mode == currentMode) return;
                  HapticFeedback.lightImpact();
                  _confirmSandboxModeChange(
                    context,
                    chatCubit,
                    mode,
                    isClaude: isClaude,
                    onBeforeRestart: onBeforeRestart,
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

IconData _sandboxMenuIcon(SandboxMode mode, bool isClaude) {
  if (mode == SandboxMode.on) return Icons.shield_outlined;
  return isClaude ? Icons.code : Icons.warning_amber;
}

Color _sandboxMenuIconColor(SandboxMode mode, bool isClaude, ColorScheme cs) {
  if (mode == SandboxMode.off && !isClaude) return cs.error;
  return cs.onSurfaceVariant;
}

String _sandboxMenuTitle(SandboxMode mode, bool isClaude) {
  if (isClaude) {
    return mode == SandboxMode.on ? 'Sandbox (Safe Mode)' : 'Standard';
  }
  return mode == SandboxMode.on ? 'Sandbox On' : 'Sandbox Off';
}

String _sandboxMenuSubtitle(
  SandboxMode mode,
  bool isClaude,
  AppLocalizations l,
) {
  if (isClaude) {
    return mode == SandboxMode.on
        ? l.sandboxRestrictedDescription
        : l.sandboxNativeDescription;
  }
  return mode == SandboxMode.on
      ? l.sandboxRestrictedDescription
      : l.sandboxNativeCautionDescription;
}

/// Show confirmation dialog before changing sandbox mode, because
/// the change requires a session restart (thread/resume with new sandbox).
Future<void> _confirmSandboxModeChange(
  BuildContext context,
  ChatSessionCubit chatCubit,
  SandboxMode mode, {
  bool isClaude = false,
  Future<void> Function()? onBeforeRestart,
}) async {
  final l = AppLocalizations.of(context);
  final modeLabel = isClaude
      ? (mode == SandboxMode.on ? 'Sandbox (Safe Mode)' : 'Standard')
      : mode.label;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final cs = Theme.of(dialogContext).colorScheme;
      // For Codex, turning off sandbox is dangerous (red button).
      // For Claude, turning off is standard — no red.
      final useErrorStyle = mode == SandboxMode.off && !isClaude;
      return AlertDialog(
        title: Text(l.changeSandboxModeTitle),
        content: Text(l.changeSandboxModeBody(modeLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: useErrorStyle
                ? FilledButton.styleFrom(backgroundColor: cs.error)
                : null,
            child: Text(l.restart),
          ),
        ],
      );
    },
  );
  if (confirmed == true) {
    await onBeforeRestart?.call();
    chatCubit.setSandboxMode(mode);
  }
}

void showPermissionModeMenu(
  BuildContext context,
  ChatSessionCubit chatCubit, {
  Future<void> Function()? onBeforeRestart,
}) {
  final currentMode = chatCubit.state.permissionMode;
  final l = AppLocalizations.of(context);
  final appColors = Theme.of(context).extension<AppColors>()!;
  final autoModeColor = Theme.of(context).brightness == Brightness.dark
      ? appColors.warningText
      : appColors.warningBubbleBorder;

  final modeDetails =
      <PermissionMode, ({IconData icon, String description, Color color})>{
        PermissionMode.defaultMode: (
          icon: Icons.tune,
          description: l.permissionDefaultDescription,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        PermissionMode.auto: (
          icon: Icons.auto_mode_outlined,
          description: l.permissionAutoDescription,
          color: autoModeColor,
        ),
        PermissionMode.acceptEdits: (
          icon: Icons.edit_note,
          description: l.permissionAcceptEditsDescription,
          color: appColors.modeAcceptEdits,
        ),
        PermissionMode.plan: (
          icon: Icons.assignment_outlined,
          description: l.permissionPlanDescription,
          color: Theme.of(context).extension<AppColors>()!.statusPlan,
        ),
        PermissionMode.bypassPermissions: (
          icon: Icons.flash_on,
          description: l.permissionBypassDescription,
          color: Theme.of(context).colorScheme.error,
        ),
      };

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final sheetCs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Permission',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: sheetCs.onSurface,
                  ),
                ),
              ),
            ),
            for (final mode in PermissionMode.values)
              ListTile(
                leading: Icon(
                  modeDetails[mode]!.icon,
                  color: mode == currentMode
                      ? modeDetails[mode]!.color
                      : sheetCs.onSurfaceVariant,
                ),
                title: Text(mode.label),
                subtitle: Text(
                  modeDetails[mode]!.description,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: mode == currentMode
                    ? Icon(
                        Icons.check,
                        color: modeDetails[mode]!.color,
                        size: 20,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (mode == currentMode) return;
                  HapticFeedback.lightImpact();
                  _confirmPermissionModeChange(
                    context,
                    chatCubit,
                    mode,
                    onBeforeRestart: onBeforeRestart,
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _confirmPermissionModeChange(
  BuildContext context,
  ChatSessionCubit chatCubit,
  PermissionMode mode, {
  Future<void> Function()? onBeforeRestart,
}) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final cs = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(l.changePermissionModeTitle),
        content: Text(l.changePermissionModeBody(mode.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: mode == PermissionMode.bypassPermissions
                ? FilledButton.styleFrom(backgroundColor: cs.error)
                : null,
            child: Text(l.restart),
          ),
        ],
      );
    },
  );
  if (confirmed == true) {
    await onBeforeRestart?.call();
    chatCubit.setPermissionMode(mode);
  }
}

class PermissionModeChip extends StatelessWidget {
  final PermissionMode currentMode;
  final VoidCallback onTap;

  const PermissionModeChip({
    super.key,
    required this.currentMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plan = Theme.of(context).extension<AppColors>()!.statusPlan;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final autoModeColor = Theme.of(context).brightness == Brightness.dark
        ? appColors.warningText
        : appColors.warningBubbleBorder;

    final (IconData icon, String label, Color fg) = switch (currentMode) {
      PermissionMode.defaultMode => (
        Icons.tune,
        'Default',
        cs.onSurfaceVariant,
      ),
      PermissionMode.auto => (Icons.auto_mode_outlined, 'Auto', autoModeColor),
      PermissionMode.acceptEdits => (
        Icons.edit_note,
        'Edits',
        appColors.modeAcceptEdits,
      ),
      PermissionMode.plan => (Icons.assignment_outlined, 'Plan', plan),
      PermissionMode.bypassPermissions => (Icons.flash_on, 'Bypass', cs.error),
    };

    return _SessionChip(
      icon: icon,
      label: label,
      color: fg,
      tooltip: 'Permission mode: $label',
      onTap: onTap,
    );
  }
}

class ThinkingEffortChip extends StatelessWidget {
  final ReasoningEffort currentEffort;
  final VoidCallback onTap;

  const ThinkingEffortChip({
    super.key,
    required this.currentEffort,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = currentEffort == ReasoningEffort.none
        ? cs.onSurfaceVariant
        : cs.primary;
    final label = _reasoningEffortDisplayLabel(currentEffort);

    return _SessionChip(
      icon: _reasoningEffortIcon(currentEffort),
      label: label,
      color: fg,
      tooltip:
          'Codex mode: $label (${currentEffort.label}). Applies from the next message.',
      onTap: onTap,
    );
  }
}

class ServiceTierChip extends StatelessWidget {
  final String? serviceTier;
  final VoidCallback onTap;

  const ServiceTierChip({
    super.key,
    required this.serviceTier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDefault = serviceTier == null || serviceTier!.isEmpty;
    final fg = isDefault ? cs.onSurfaceVariant : cs.primary;
    final label = isDefault ? 'Tier' : _serviceTierFallbackName(serviceTier!);

    return _SessionChip(
      icon: isDefault ? Icons.tune : Icons.flash_on_outlined,
      label: label,
      color: fg,
      tooltip:
          'Service tier: ${isDefault ? 'Default' : '$label ($serviceTier)'}. Applies from the next message.',
      onTap: onTap,
    );
  }
}

void showClaudeModelMenu(
  BuildContext context,
  ChatSessionCubit chatCubit, {
  Future<void> Function()? onBeforeRestart,
}) {
  if (chatCubit.isCodex) return;
  final settings = chatCubit.claudeSettings;
  final currentModel = _effectiveClaudeModel(settings);
  final models = _claudeModelsForSession(context, currentModel);
  final currentEffort = settings.effort;

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final sheetCs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Claude model',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: sheetCs.onSurface,
                    ),
                  ),
                ),
              ),
              for (final model in models)
                ListTile(
                  leading: Icon(
                    _claudeModelIcon(model),
                    color: model == currentModel
                        ? sheetCs.primary
                        : sheetCs.onSurfaceVariant,
                  ),
                  title: Text(displayLabelForClaudeModel(model)),
                  subtitle: Text(
                    descriptionForClaudeModel(model),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: model == currentModel
                      ? Icon(Icons.check, color: sheetCs.primary, size: 20)
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (model == currentModel) return;
                    final allowedEfforts = _claudeEffortsForModel(
                      context,
                      model,
                      currentEffort,
                    );
                    final nextEffort = allowedEfforts.contains(currentEffort)
                        ? currentEffort
                        : allowedEfforts.contains(ClaudeEffort.high)
                        ? ClaudeEffort.high
                        : allowedEfforts.first;
                    await onBeforeRestart?.call();
                    HapticFeedback.lightImpact();
                    chatCubit.setClaudeSessionOptions(
                      model: model,
                      effort: nextEffort,
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

void showClaudeEffortMenu(
  BuildContext context,
  ChatSessionCubit chatCubit, {
  Future<void> Function()? onBeforeRestart,
}) {
  if (chatCubit.isCodex) return;
  final settings = chatCubit.claudeSettings;
  final model = _effectiveClaudeModel(settings);
  final currentEffort = settings.effort;
  final efforts = _claudeEffortsForModel(context, model, currentEffort);

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final sheetCs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Claude thinking',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: sheetCs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Current: ${currentEffort.label}. Applies from the next message.',
                        style: TextStyle(
                          fontSize: 12,
                          color: sheetCs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final effort in efforts)
                ListTile(
                  leading: Icon(
                    _claudeEffortIcon(effort),
                    color: effort == currentEffort
                        ? sheetCs.primary
                        : sheetCs.onSurfaceVariant,
                  ),
                  title: Text(effort.label),
                  subtitle: Text(
                    _claudeEffortDescription(effort),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: effort == currentEffort
                      ? Icon(Icons.check, color: sheetCs.primary, size: 20)
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (effort == currentEffort) return;
                    await onBeforeRestart?.call();
                    HapticFeedback.lightImpact();
                    chatCubit.setClaudeSessionOptions(effort: effort);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

void showClaudeBillingSheet(
  BuildContext context,
  ClaudeSessionRuntimeSettings settings,
) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final sheetCs = Theme.of(sheetContext).colorScheme;
      final source = _claudeBillingFullLabel(settings);
      final fastState = settings.fastModeState?.isNotEmpty == true
          ? settings.fastModeState!
          : (settings.fastMode ? 'requested' : 'off');
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Claude usage',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: sheetCs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _ClaudeUsageRow(
                icon: Icons.account_circle_outlined,
                label: 'Source',
                value: source,
              ),
              _ClaudeUsageRow(
                icon: Icons.bolt_outlined,
                label: 'Fast mode',
                value: fastState,
              ),
              _ClaudeUsageRow(
                icon: Icons.smart_toy_outlined,
                label: 'Model',
                value: displayLabelForClaudeModel(
                  _effectiveClaudeModel(settings),
                ),
              ),
              if (settings.claudeCodeVersion?.isNotEmpty == true)
                _ClaudeUsageRow(
                  icon: Icons.terminal,
                  label: 'Claude Code',
                  value: settings.claudeCodeVersion!,
                ),
            ],
          ),
        ),
      );
    },
  );
}

List<String> _claudeModelsForSession(BuildContext context, String current) {
  const fallback = <String>[
    'default',
    'opus',
    'opus[1m]',
    'sonnet',
    'haiku',
    'claude-opus-4-8',
    'claude-opus-4-8[1m]',
  ];
  final bridgeModels = context.read<BridgeService>().claudeModels;
  final seen = <String>{};
  final out = <String>[];
  for (final model in [current, ...bridgeModels, ...fallback]) {
    final trimmed = model.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) continue;
    out.add(trimmed);
  }
  return out;
}

List<ClaudeEffort> _claudeEffortsForModel(
  BuildContext context,
  String model,
  ClaudeEffort current,
) {
  final raw =
      context.read<BridgeService>().claudeModelEfforts[model] ??
      context.read<BridgeService>().claudeModelEfforts['default'] ??
      const <String>[];
  final seen = <ClaudeEffort>{};
  final out = <ClaudeEffort>[];
  for (final effort in [
    current,
    ...raw.map(parseClaudeEffortFromRaw).whereType<ClaudeEffort>(),
    ClaudeEffort.low,
    ClaudeEffort.medium,
    ClaudeEffort.high,
    ClaudeEffort.xhigh,
    ClaudeEffort.max,
  ]) {
    if (seen.add(effort)) out.add(effort);
  }
  return out;
}

String _effectiveClaudeModel(ClaudeSessionRuntimeSettings settings) {
  final model = settings.model?.trim();
  return model == null || model.isEmpty ? 'default' : model;
}

bool _isClaudeFastModeCapableModel(String model) {
  final value = model.trim().toLowerCase();
  return value.contains('opus') && value != 'opusplan';
}

String _preferredClaudeFastModeModel(BuildContext context) {
  final models = context.read<BridgeService>().claudeModels;
  const candidates = [
    'claude-opus-4-8[1m]',
    'opus[1m]',
    'claude-opus-4-8',
    'opus',
    'claude-opus-4-7[1m]',
    'claude-opus-4-7',
    'claude-opus-4-6[1m]',
    'claude-opus-4-6',
  ];
  for (final candidate in candidates) {
    if (models.contains(candidate)) return candidate;
  }
  return models.firstWhere(
    _isClaudeFastModeCapableModel,
    orElse: () => 'opus[1m]',
  );
}

IconData _claudeModelIcon(String model) {
  final value = model.toLowerCase();
  if (value.contains('opus')) return Icons.auto_awesome;
  if (value.contains('haiku')) return Icons.bolt_outlined;
  if (value.contains('sonnet')) return Icons.balance_outlined;
  return Icons.smart_toy_outlined;
}

IconData _claudeEffortIcon(ClaudeEffort effort) => switch (effort) {
  ClaudeEffort.low => Icons.speed,
  ClaudeEffort.medium => Icons.lightbulb_outline,
  ClaudeEffort.high => Icons.psychology,
  ClaudeEffort.xhigh => Icons.auto_awesome,
  ClaudeEffort.max => Icons.all_inclusive,
};

String _claudeEffortDescription(ClaudeEffort effort) => switch (effort) {
  ClaudeEffort.low => 'Faster responses with lighter reasoning',
  ClaudeEffort.medium => 'Balanced speed and reasoning',
  ClaudeEffort.high => 'More careful analysis',
  ClaudeEffort.xhigh => 'Extended reasoning for harder work',
  ClaudeEffort.max => 'Most thorough, slowest option',
};

String _claudeBillingShortLabel(ClaudeSessionRuntimeSettings settings) {
  final source = settings.billingSource?.trim().toLowerCase();
  final apiKeySource = settings.apiKeySource?.trim().toLowerCase();
  if (source == 'subscription' || apiKeySource == 'none') return 'Sub';
  if (source == 'api' || (apiKeySource != null && apiKeySource.isNotEmpty)) {
    return 'API';
  }
  return 'Usage';
}

String _claudeBillingFullLabel(ClaudeSessionRuntimeSettings settings) {
  final source = settings.billingSource?.trim().toLowerCase();
  final apiKeySource = settings.apiKeySource?.trim();
  if (source == 'subscription' || apiKeySource == 'none') {
    return 'Claude subscription';
  }
  if (source == 'api') {
    return apiKeySource?.isNotEmpty == true
        ? 'API key ($apiKeySource)'
        : 'API key';
  }
  if (apiKeySource?.isNotEmpty == true) {
    return 'Credential source: $apiKeySource';
  }
  return 'Waiting for Claude Code init';
}

class ClaudeModelChip extends StatelessWidget {
  final String? model;
  final VoidCallback onTap;

  const ClaudeModelChip({super.key, required this.model, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effective = model?.trim().isNotEmpty == true
        ? model!.trim()
        : 'default';
    final label = displayLabelForClaudeModel(effective);
    final compactLabel = label
        .replaceAll('Claude ', '')
        .replaceAll(' available', '')
        .replaceAll(' context', '');

    return _SessionChip(
      icon: _claudeModelIcon(effective),
      label: compactLabel,
      color: cs.primary,
      tooltip: 'Claude model: $label',
      onTap: onTap,
    );
  }
}

class ClaudeThinkingChip extends StatelessWidget {
  final ClaudeEffort effort;
  final VoidCallback onTap;

  const ClaudeThinkingChip({
    super.key,
    required this.effort,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SessionChip(
      icon: _claudeEffortIcon(effort),
      label: effort == ClaudeEffort.xhigh ? 'X High' : effort.label,
      color: cs.primary,
      tooltip: 'Claude thinking: ${effort.label}',
      onTap: onTap,
    );
  }
}

class ClaudeFastModeChip extends StatelessWidget {
  final bool enabled;
  final String? actualState;
  final VoidCallback onTap;

  const ClaudeFastModeChip({
    super.key,
    required this.enabled,
    this.actualState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final normalizedActual = actualState?.trim().toLowerCase();
    final requestedButOff =
        enabled && normalizedActual != null && normalizedActual != 'on';
    final color = requestedButOff
        ? appColors.warningText
        : enabled
        ? cs.primary
        : cs.onSurfaceVariant;
    final label = enabled
        ? switch (normalizedActual) {
            'cooldown' => 'Fast Cooldown',
            'off' => 'Fast Blocked',
            _ => 'Fast',
          }
        : 'Fast Off';

    return _SessionChip(
      icon: enabled ? Icons.bolt : Icons.bolt_outlined,
      label: label,
      color: color,
      tooltip:
          'Claude Opus fast mode: ${enabled ? 'requested' : 'off'}${actualState == null ? '' : ', Claude reports $actualState'}${enabled && normalizedActual == 'off' ? '. Extra usage or usage credits are disabled.' : ''}',
      showChevron: false,
      tinted: enabled,
      onTap: onTap,
    );
  }
}

class ClaudeBillingChip extends StatelessWidget {
  final ClaudeSessionRuntimeSettings settings;
  final VoidCallback onTap;

  const ClaudeBillingChip({
    super.key,
    required this.settings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = _claudeBillingShortLabel(settings);
    final color = label == 'API' ? cs.error : cs.onSurfaceVariant;

    return _SessionChip(
      icon: label == 'API' ? Icons.key : Icons.account_circle_outlined,
      label: label,
      color: color,
      tooltip: _claudeBillingFullLabel(settings),
      onTap: onTap,
    );
  }
}

class _ClaudeUsageRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ClaudeUsageRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Canonical mode-bar chip primitive.
///
/// The painted pill stays visually compact, but the InkWell hit area is forced
/// to at least [AppSizes.minTouchTarget] tall so every chip is comfortably
/// tappable one-handed. Toggle-style chips (no chevron) pass [tinted] so an
/// active state reads as a filled background rather than relying on the
/// presence/absence of a chevron alone.
class _SessionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  final bool showChevron;

  /// When true, the compact pill gets a tinted [color] background so the chip
  /// reads as an active toggle (used for chevron-less toggles like Fast/Plan).
  final bool tinted;

  const _SessionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.showChevron = true,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      // Visually compact: padding stays small so the painted pill does not
      // grow even though the hit area below is 44px tall.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: tinted
          ? BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.32)),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppIconSize.chip, color: color),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (showChevron)
            Icon(
              Icons.arrow_drop_down,
              size: AppIconSize.chip,
              color: color.withValues(alpha: 0.5),
            ),
        ],
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Force a >=44px tap/ripple area without enlarging the pill.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Center(widthFactor: 1, child: pill),
            ),
          ),
        ),
      ),
    );
  }
}

class ExecutionModeChip extends StatelessWidget {
  final ExecutionMode currentMode;
  final CodexApprovalPolicy? codexApprovalPolicy;
  final String? codexApprovalsReviewer;
  final CodexPermissionsMode? codexPermissionsMode;
  final Provider? provider;
  final VoidCallback onTap;

  const ExecutionModeChip({
    super.key,
    required this.currentMode,
    this.codexApprovalPolicy,
    this.codexApprovalsReviewer,
    this.codexPermissionsMode,
    this.provider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Colors aligned with Claude Code CLI
    final appColors = Theme.of(context).extension<AppColors>()!;

    final (IconData icon, String label, Color fg) = provider == Provider.codex
        ? _codexPermissionsChipStyle(
            codexPermissionsMode ??
                codexPermissionsModeFromSettings(
                  approvalPolicy: codexApprovalPolicy?.value,
                  approvalsReviewer: codexApprovalsReviewer,
                  sandboxMode: null,
                ),
            cs,
          )
        : switch (currentMode) {
            ExecutionMode.defaultMode => (
              Icons.tune,
              'Default',
              cs.onSurfaceVariant,
            ),
            ExecutionMode.acceptEdits => (
              Icons.edit_note,
              'Edits',
              appColors.modeAcceptEdits,
            ),
            ExecutionMode.fullAccess => (Icons.flash_on, 'Full', cs.error),
          };

    return _SessionChip(
      icon: icon,
      label: label,
      color: fg,
      tooltip: provider == Provider.codex
          ? 'Codex permissions: $label'
          : 'Execution mode: $label',
      onTap: onTap,
    );
  }
}

IconData _codexPermissionsIcon(CodexPermissionsMode mode) => switch (mode) {
  CodexPermissionsMode.defaultPermissions => Icons.back_hand_outlined,
  CodexPermissionsMode.autoReview => Icons.shield_outlined,
  CodexPermissionsMode.fullAccess => Icons.warning_amber_outlined,
  CodexPermissionsMode.custom => Icons.settings_outlined,
};

String _codexPermissionsSubtitle(
  CodexPermissionsMode mode,
  AppLocalizations l,
) => switch (mode) {
  CodexPermissionsMode.defaultPermissions => l.sandboxRestrictedDescription,
  CodexPermissionsMode.autoReview => l.codexAutoReviewDescription,
  CodexPermissionsMode.fullAccess => l.sandboxNativeCautionDescription,
  CodexPermissionsMode.custom => 'Codex uses permissions from config.toml',
};

(IconData, String, Color) _codexPermissionsChipStyle(
  CodexPermissionsMode mode,
  ColorScheme cs,
) => switch (mode) {
  CodexPermissionsMode.defaultPermissions => (
    _codexPermissionsIcon(mode),
    'Default',
    cs.onSurfaceVariant,
  ),
  CodexPermissionsMode.autoReview => (
    _codexPermissionsIcon(mode),
    'Auto Review',
    cs.primary,
  ),
  CodexPermissionsMode.fullAccess => (
    _codexPermissionsIcon(mode),
    'Full',
    cs.error,
  ),
  CodexPermissionsMode.custom => (
    _codexPermissionsIcon(mode),
    'Custom',
    cs.primary,
  ),
};

class PlanModeChip extends StatelessWidget {
  final bool enabled;
  final bool activeGlow;
  final VoidCallback onTap;

  const PlanModeChip({
    super.key,
    required this.enabled,
    this.activeGlow = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final cs = Theme.of(context).colorScheme;
    final fg = enabled ? appColors.statusPlan : cs.onSurfaceVariant;

    final chip = _SessionChip(
      icon: Icons.assignment_outlined,
      label: enabled ? 'Plan On' : 'Plan Off',
      color: fg,
      tooltip: 'Plan mode: ${enabled ? 'on' : 'off'}',
      showChevron: false,
      tinted: enabled,
      onTap: onTap,
    );

    if (!activeGlow) return chip;

    return _PulsingModeBarSurface(
      key: const ValueKey('plan_mode_chip_glow'),
      inPlanMode: true,
      child: chip,
    );
  }
}

class SandboxModeChip extends StatelessWidget {
  final SandboxMode currentMode;
  final Provider? provider;
  final VoidCallback onTap;

  const SandboxModeChip({
    super.key,
    required this.currentMode,
    this.provider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isClaude = provider != Provider.codex;

    final (IconData icon, String label, Color fg) = switch (currentMode) {
      SandboxMode.on => (Icons.shield_outlined, 'Sandbox', cs.tertiary),
      SandboxMode.off =>
        isClaude
            ? (Icons.code, 'Standard', cs.onSurfaceVariant)
            : (Icons.warning_amber, 'No SB', cs.error),
    };

    // Pair the risky "sandbox off" state with a tinted background so the
    // warning is not signalled by colour alone (the warning glyph + red text
    // are reinforced by a filled chip).
    final isRisky = currentMode == SandboxMode.off && !isClaude;

    return _SessionChip(
      icon: icon,
      label: label,
      color: fg,
      tooltip: 'Sandbox: $label',
      tinted: isRisky,
      onTap: onTap,
    );
  }
}
