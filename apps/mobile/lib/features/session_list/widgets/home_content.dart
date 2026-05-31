import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';
import '../../../services/app_update_service.dart';
import '../../../services/bridge_service.dart';
import '../../../services/draft_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/revenuecat_service.dart';
import '../../../services/support_banner_service.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/provider_style.dart';
import '../../../router/app_router.dart';
import '../../../widgets/session_card.dart';
import '../../../widgets/session_visual_status.dart';
import '../../../widgets/workspace_pane_chrome.dart';
import '../state/session_list_cubit.dart';
import '../state/session_list_state.dart';
import '../workspace_shell_screen.dart';
import 'section_header.dart';
import 'session_filter_bar.dart';
import 'session_list_empty_state.dart';
import 'app_update_banner.dart';
import 'bridge_update_banner.dart';
import 'macos_native_app_banner.dart';
import 'session_reconnect_banner.dart';
import 'support_banner.dart';

/// Presentational status-sort rank for the Running section. Lower floats to
/// the top: Needs You (0) -> Working (1) -> Done (ready & unseen, 2) -> Idle
/// (ready & seen, 3). Derived from the SAME [sessionVisualStatusFor] state
/// machine the card uses; NO change to the cubit/state. The Done/Idle split
/// reads the already-known unseen flag, mirroring the card.
int _statusSortRank(SessionInfo session, {required bool isUnseen}) {
  final visualStatus = sessionVisualStatusFor(
    rawStatus: session.status,
    permissionMode: session.effectivePermissionMode,
    planMode: session.resolvedPlanMode,
    pendingPermission: session.pendingPermission,
  );
  return switch (visualStatus.primary) {
    SessionPrimaryStatus.needsYou => 0,
    SessionPrimaryStatus.working => 1,
    SessionPrimaryStatus.ready => isUnseen ? 2 : 3,
  };
}

class HomeContent extends StatefulWidget {
  final BridgeConnectionState connectionState;
  final String? bridgeVersion;
  final String? latestBridgeVersion;
  final List<SessionInfo> sessions;
  final List<OfflinePendingAction> offlinePendingActions;
  final List<RecentSession> recentSessions;
  final Set<String> accumulatedProjectPaths;
  final String searchQuery;
  final bool isLoadingMore;
  final bool isInitialLoading;
  final bool hasMoreSessions;
  final Set<String> archivingSessionIds;
  final Set<String> unseenSessionIds;
  final String? currentProjectFilter;
  final VoidCallback onNewSession;
  final void Function(
    String sessionId, {
    String? projectPath,
    String? gitBranch,
    String? worktreePath,
    String? provider,
    String? permissionMode,
    String? sandboxMode,
    String? approvalPolicy,
    String? approvalsReviewer,
  })
  onTapRunning;
  final ValueChanged<String> onStopSession;
  final ValueChanged<String>? onCancelOfflinePendingAction;
  final void Function(String sessionId, String toolUseId, {bool clearContext})?
  onApprovePermission;
  final void Function(String sessionId, String toolUseId)? onApproveAlways;
  final void Function(String sessionId, String toolUseId, {String? message})?
  onRejectPermission;
  final void Function(String sessionId, String toolUseId, String result)?
  onAnswerQuestion;
  final ValueChanged<RecentSession> onResumeSession;
  final void Function(RecentSession session, Offset? position)
  onLongPressRecentSession;
  final ValueChanged<RecentSession> onArchiveSession;
  final void Function(SessionInfo session, Offset? position)
  onLongPressRunningSession;
  final ValueChanged<String?> onSelectProject;
  final VoidCallback onLoadMore;
  final ProviderFilter providerFilter;
  final bool namedOnly;
  final VoidCallback onToggleProvider;
  final VoidCallback onToggleNamed;
  final AppUpdateInfo? appUpdateInfo;
  final VoidCallback? onDismissAppUpdate;
  final bool showMacOSNativeAppBanner;
  final VoidCallback? onDismissMacOSNativeAppBanner;
  final VoidCallback? onOpenMacOSNativeAppReleases;
  final VoidCallback? onOpenBridgeSettings;
  final VoidCallback? onOpenSupportSettings;
  final bool? showInlineStopButtonOverride;
  final String? connectedBridgeLabel;

  const HomeContent({
    super.key,
    required this.connectionState,
    this.bridgeVersion,
    this.latestBridgeVersion,
    required this.sessions,
    this.offlinePendingActions = const [],
    required this.recentSessions,
    required this.accumulatedProjectPaths,
    required this.searchQuery,
    required this.isLoadingMore,
    required this.isInitialLoading,
    required this.hasMoreSessions,
    this.archivingSessionIds = const {},
    this.unseenSessionIds = const {},
    required this.currentProjectFilter,
    required this.onNewSession,
    required this.onTapRunning,
    required this.onStopSession,
    this.onCancelOfflinePendingAction,
    this.onApprovePermission,
    this.onApproveAlways,
    this.onRejectPermission,
    this.onAnswerQuestion,
    required this.onResumeSession,
    required this.onLongPressRecentSession,
    required this.onArchiveSession,
    required this.onLongPressRunningSession,
    required this.onSelectProject,
    required this.onLoadMore,
    required this.providerFilter,
    required this.namedOnly,
    required this.onToggleProvider,
    required this.onToggleNamed,
    this.appUpdateInfo,
    this.onDismissAppUpdate,
    this.showMacOSNativeAppBanner = false,
    this.onDismissMacOSNativeAppBanner,
    this.onOpenMacOSNativeAppReleases,
    this.onOpenBridgeSettings,
    this.onOpenSupportSettings,
    this.showInlineStopButtonOverride,
    this.connectedBridgeLabel,
  });

  @override
  State<HomeContent> createState() => HomeContentState();
}

class HomeContentState extends State<HomeContent> {
  bool _isSearching = false;
  bool _updateBannerDismissed = false;
  bool _showSupportBanner = false;
  final _searchController = TextEditingController();
  SessionDisplayMode _displayMode = SessionDisplayMode.first;
  RevenueCatService? _revenueCatService;
  VoidCallback? _catalogStateListener;
  SupportBannerService? _supportBannerService;
  VoidCallback? _supportBannerListener;
  String? _providerAuthBaseUrl;
  List<ProviderAuthStatusInfo> _providerAuthStatuses = const [];
  bool _providerAuthLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDisplayMode();
  }

  Future<void> _loadDisplayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString('session_list_display_mode');
    if (modeStr != null && mounted) {
      setState(() {
        _displayMode = SessionDisplayMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => SessionDisplayMode.first,
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revenueCatService = context.read<RevenueCatService>();
    if (!identical(_revenueCatService, revenueCatService)) {
      if (_revenueCatService != null && _catalogStateListener != null) {
        _revenueCatService!.catalogState.removeListener(_catalogStateListener!);
      }
      _revenueCatService = revenueCatService;
      _catalogStateListener = () => _refreshSupportBannerVisibility();
      revenueCatService.catalogState.addListener(_catalogStateListener!);
      _refreshSupportBannerVisibility();
    }

    final supportBannerService = context.read<SupportBannerService>();
    if (!identical(_supportBannerService, supportBannerService)) {
      if (_supportBannerService != null && _supportBannerListener != null) {
        _supportBannerService!.removeListener(_supportBannerListener!);
      }
      _supportBannerService = supportBannerService;
      _supportBannerListener = () => _refreshSupportBannerVisibility();
      supportBannerService.addListener(_supportBannerListener!);
      _refreshSupportBannerVisibility();
    }

    _refreshProviderAuthStatusIfNeeded();
  }

  void _toggleDisplayMode() async {
    final next = switch (_displayMode) {
      SessionDisplayMode.first => SessionDisplayMode.last,
      SessionDisplayMode.last => SessionDisplayMode.summary,
      SessionDisplayMode.summary => SessionDisplayMode.first,
    };
    setState(() => _displayMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_list_display_mode', next.name);
  }

  @override
  void didUpdateWidget(covariant HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部から searchQuery がクリアされたら検索UIも閉じる
    if (widget.searchQuery.isEmpty && oldWidget.searchQuery.isNotEmpty) {
      setState(() => _isSearching = false);
      _searchController.clear();
    }
    // Reset dismiss state when reconnected (new bridgeVersion received)
    if (widget.bridgeVersion != oldWidget.bridgeVersion) {
      _updateBannerDismissed = false;
      _refreshSupportBannerVisibility();
      _providerAuthBaseUrl = null;
      _refreshProviderAuthStatusIfNeeded();
    }
  }

  @override
  void dispose() {
    if (_revenueCatService != null && _catalogStateListener != null) {
      _revenueCatService!.catalogState.removeListener(_catalogStateListener!);
    }
    if (_supportBannerService != null && _supportBannerListener != null) {
      _supportBannerService!.removeListener(_supportBannerListener!);
    }
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        context.read<SessionListCubit>().setSearchQuery('');
      }
    });
  }

  /// Open search field programmatically (e.g. from keyboard shortcut).
  void openSearch() {
    if (!_isSearching) {
      _toggleSearch();
    }
  }

  Widget? _buildAppUpdateBanner() {
    if (widget.appUpdateInfo == null) return null;
    return AppUpdateBanner(
      updateInfo: widget.appUpdateInfo!,
      onDismiss: widget.onDismissAppUpdate,
    );
  }

  Widget? _buildMacOSNativeAppBanner() {
    if (!widget.showMacOSNativeAppBanner) return null;
    return MacOSNativeAppBanner(
      onDismiss: widget.onDismissMacOSNativeAppBanner,
      onOpen: widget.onOpenMacOSNativeAppReleases,
    );
  }

  Widget? _buildUpdateBanner() {
    if (_updateBannerDismissed) return null;
    if (!BridgeUpdateBanner.shouldShow(
      widget.bridgeVersion,
      AppConstants.expectedBridgeVersion,
      latestBridgeVersion: widget.latestBridgeVersion,
    )) {
      return null;
    }
    return BridgeUpdateBanner(
      currentVersion: widget.bridgeVersion!,
      expectedVersion: AppConstants.expectedBridgeVersion,
      latestBridgeVersion: widget.latestBridgeVersion,
      onTap:
          widget.onOpenBridgeSettings ??
          () => context.pushRoute(SettingsRoute(focusConnection: true)),
      onDismiss: () => setState(() => _updateBannerDismissed = true),
    );
  }

  bool _hasVisibleBridgeUpdateBanner() {
    return !_updateBannerDismissed &&
        BridgeUpdateBanner.shouldShow(
          widget.bridgeVersion,
          AppConstants.expectedBridgeVersion,
          latestBridgeVersion: widget.latestBridgeVersion,
        );
  }

  Future<void> _refreshSupportBannerVisibility() async {
    final revenueCatService = _revenueCatService;
    if (revenueCatService == null) return;

    final supportBannerService = context.read<SupportBannerService>();
    final shouldShow = await supportBannerService.shouldShow(
      hasBridgeUpdate: _hasVisibleBridgeUpdateBanner(),
      catalog: revenueCatService.catalogState.value,
    );
    if (!mounted || shouldShow == _showSupportBanner) return;
    setState(() {
      _showSupportBanner = shouldShow;
    });
  }

  Widget? _buildSupportBanner() {
    if (!_showSupportBanner) return null;
    return SupportBanner(
      onTap:
          widget.onOpenSupportSettings ??
          () => context.pushRoute(SettingsRoute(focusSupport: true)),
      onDismiss: () async {
        await context.read<SupportBannerService>().dismiss();
        if (!mounted) return;
        setState(() {
          _showSupportBanner = false;
        });
      },
    );
  }

  void _refreshProviderAuthStatusIfNeeded() {
    if (widget.connectionState != BridgeConnectionState.connected) return;
    final bridge = context.read<BridgeService?>();
    final baseUrl = bridge?.httpBaseUrl;
    if (bridge == null || baseUrl == null || baseUrl.isEmpty) return;
    if (_providerAuthLoading && _providerAuthBaseUrl == baseUrl) return;
    if (_providerAuthBaseUrl == baseUrl && _providerAuthStatuses.isNotEmpty) {
      return;
    }

    _providerAuthLoading = true;
    _providerAuthBaseUrl = baseUrl;
    unawaited(_loadProviderAuthStatus(bridge, baseUrl));
  }

  Future<void> _loadProviderAuthStatus(
    BridgeService bridge,
    String baseUrl,
  ) async {
    try {
      final statuses = await bridge.fetchProviderAuthStatus();
      if (!mounted || _providerAuthBaseUrl != baseUrl) return;
      setState(() {
        _providerAuthStatuses = statuses;
        _providerAuthLoading = false;
      });
    } catch (_) {
      if (!mounted || _providerAuthBaseUrl != baseUrl) return;
      setState(() {
        _providerAuthStatuses = const [];
        _providerAuthLoading = false;
      });
    }
  }

  Widget? _buildProviderAuthStrip() {
    if (_providerAuthStatuses.isEmpty) return null;
    final visibleStatuses = _providerAuthStatuses
        .where(
          (status) => status.provider == 'claude' || status.provider == 'codex',
        )
        .toList(growable: false);
    if (visibleStatuses.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < visibleStatuses.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _ProviderAuthStatusChip(status: visibleStatuses[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _buildConnectedBridgeBanner(BuildContext context) {
    final label = widget.connectedBridgeLabel;
    if (label == null || label.isEmpty) return null;
    if (WorkspaceShellScreen.maybeOf(context) == null) return null;
    final chrome = resolveWorkspacePaneChrome(
      platform: Theme.of(context).platform,
      isAdaptiveWorkspace: true,
      isLeftPaneVisible: true,
      slot: WorkspacePaneSlot.left,
    );
    if (!chrome.useMacOSAdaptiveChrome) return null;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.dns_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Coarse date bucket for the Recent date-group subheaders, ordered newest
  /// first: 0=Today, 1=Yesterday, 2=This week (last 7 days), 3=Earlier. Buckets
  /// on [RecentSession.modified]; falls back to the last bucket on a missing or
  /// unparseable timestamp so it never crashes or hides a card.
  int _recentDateBucket(String modifiedIso) {
    if (modifiedIso.isEmpty) return 3;
    final DateTime dt;
    try {
      dt = DateTime.parse(modifiedIso).toLocal();
    } catch (_) {
      return 3;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dtDate = DateTime(dt.year, dt.month, dt.day);
    final dayDiff = today.difference(dtDate).inDays;
    if (dayDiff <= 0) return 0; // today (or a future-dated stamp)
    if (dayDiff == 1) return 1; // yesterday
    if (dayDiff < 7) return 2; // this week
    return 3; // earlier
  }

  String _recentDateBucketLabel(int bucket, AppLocalizations l) {
    // Hardcoded English to match the sibling status words ('Working'/'Needs
    // You'/'Done'/'Idle') which are raw English literals, not AppLocalizations.
    // If these need localizing later, add l10n keys + run gen-l10n.
    return switch (bucket) {
      0 => 'TODAY',
      1 => 'YESTERDAY',
      2 => 'THIS WEEK',
      _ => 'EARLIER',
    };
  }

  /// Builds the Recent list as date-grouped cards: a quiet subheader is emitted
  /// before each non-empty Today/Yesterday/This week/Earlier bucket, then each
  /// session's Slidable+RecentSessionCard exactly as before (keys, archive
  /// swipe, displayMode, draft, isProcessing, callbacks all unchanged).
  List<Widget> _buildGroupedRecentCards(
    BuildContext context,
    List<RecentSession> sessions,
    AppLocalizations l,
  ) {
    final children = <Widget>[];
    final emittedBuckets = <int>{};
    for (final session in sessions) {
      final bucket = _recentDateBucket(session.modified);
      // Emit each bucket's subheader at most once, the first time that bucket
      // appears. Tracking already-emitted buckets (rather than only comparing
      // to the previous item) avoids double-emitting a header if the filtered
      // list is not strictly newest-first.
      if (emittedBuckets.add(bucket)) {
        children.add(
          _DateGroupSubheader(label: _recentDateBucketLabel(bucket, l)),
        );
      }
      children.add(
        Slidable(
          key: ValueKey('recent_session_${session.sessionId}'),
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.18,
            children: [
              CustomSlidableAction(
                onPressed: (_) => widget.onArchiveSession(session),
                backgroundColor: Colors.transparent,
                padding: EdgeInsets.zero,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.archive_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
          child: RecentSessionCard(
            session: session,
            displayMode: _displayMode,
            // Only running sessions show the active selection state.
            isSelected: false,
            draftText: context.read<DraftService>().getDraft(session.sessionId),
            isProcessing: widget.archivingSessionIds.contains(
              session.sessionId,
            ),
            onTap: () => widget.onResumeSession(session),
            onLongPress: () => widget.onLongPressRecentSession(session, null),
            onShowActions: (position) =>
                widget.onLongPressRecentSession(session, position),
          ),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final shell = WorkspaceShellScreen.maybeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        NotificationService.instance,
        if (shell != null) shell.presentationListenable,
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appColors = Theme.of(context).extension<AppColors>()!;
    final hasPendingActions = widget.offlinePendingActions.isNotEmpty;
    final hasRunningSessions = widget.sessions.isNotEmpty || hasPendingActions;
    final hasRecentSessions = widget.recentSessions.isNotEmpty;
    final isReconnecting =
        widget.connectionState == BridgeConnectionState.reconnecting;
    final updateBanner = _buildUpdateBanner();
    final supportBannerService = context.read<SupportBannerService>();
    final supportBanner =
        updateBanner == null || supportBannerService.shouldForceShowInDebug
        ? _buildSupportBanner()
        : null;
    final appUpdateBanner = _buildAppUpdateBanner();
    final macOSNativeAppBanner = _buildMacOSNativeAppBanner();
    // Cap promotional/update banners to a single one per load. Priority:
    // bridge-update > app-update > macOS-native > support. The debug
    // force-show escape hatch keeps support eligible above the bridge update.
    // The reconnect banner is transient *state* (not promo) and stays separate.
    final promoBanner = supportBannerService.shouldForceShowInDebug
        ? (supportBanner ??
              updateBanner ??
              appUpdateBanner ??
              macOSNativeAppBanner)
        : (updateBanner ??
              appUpdateBanner ??
              macOSNativeAppBanner ??
              supportBanner);
    final shell = WorkspaceShellScreen.maybeOf(context);
    final selectedSession = shell?.selectedSession;
    final selectedSessionId = selectedSession?.sessionId;
    final selectedSessionProvider = selectedSession?.provider?.value;
    final showInlineStopButton =
        widget.showInlineStopButtonOverride ?? shell != null;
    final connectedBridgeBanner = _buildConnectedBridgeBanner(context);
    final providerAuthStrip = _buildProviderAuthStrip();

    // Compute derived state
    // Exclude running sessions from recent list to avoid duplicates
    final runningSessionIds = widget.sessions
        .expand(
          (s) => [s.id, if (s.claudeSessionId != null) s.claudeSessionId!],
        )
        .toSet();
    final pendingResumeSessionIds = widget.offlinePendingActions
        .where((action) => action.kind == OfflinePendingActionKind.resume)
        .map((action) => action.sessionId)
        .whereType<String>()
        .toSet();

    // Fallback for Codex sessions which use a short proxy ID instead of UUID
    bool isDuplicate(RecentSession rs) {
      if (pendingResumeSessionIds.contains(rs.sessionId)) return true;
      if (runningSessionIds.contains(rs.sessionId)) return true;
      for (final s in widget.sessions) {
        if (s.provider == rs.provider &&
            s.projectPath == rs.projectPath &&
            s.createdAt == rs.created) {
          return true;
        }
      }
      return false;
    }

    // All filtering (project, provider, namedOnly, searchQuery) is applied
    // server-side. Only deduplicate running sessions here.
    final filteredSessions = widget.recentSessions
        .where((s) => !isDuplicate(s))
        .toList();

    final hasActiveFilter =
        widget.currentProjectFilter != null ||
        widget.providerFilter != ProviderFilter.all ||
        widget.namedOnly ||
        widget.searchQuery.isNotEmpty;

    // Presentational, STABLE status-sort over a LOCAL COPY of the running
    // sessions so "Needs You" floats to the top. Tie-break by original index so
    // same-status cards keep server order and ONLY cross-status transitions
    // move; element identity (and the plan-feedback TextField state) survives
    // because the ValueKey('running_session_<id>') travels with each card. The
    // cubit/state is untouched.
    final indexedSessions = widget.sessions.indexed.toList();
    indexedSessions.sort((a, b) {
      final rankA = _statusSortRank(
        a.$2,
        isUnseen: widget.unseenSessionIds.contains(a.$2.id),
      );
      final rankB = _statusSortRank(
        b.$2,
        isUnseen: widget.unseenSessionIds.contains(b.$2.id),
      );
      if (rankA != rankB) return rankA.compareTo(rankB);
      return a.$1.compareTo(b.$1);
    });
    final sortedSessions = [for (final entry in indexedSessions) entry.$2];

    // Count sessions awaiting the user (rank 0) for the optional Running
    // SectionHeader trailing badge.
    final needsYouCount = widget.sessions
        .where(
          (s) =>
              _statusSortRank(
                s,
                isUnseen: widget.unseenSessionIds.contains(s.id),
              ) ==
              0,
        )
        .length;

    if (!hasRunningSessions && !hasRecentSessions && !hasActiveFilter) {
      // Show skeleton while initial data is loading
      if (widget.isInitialLoading) {
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            12,
            12,
            12,
            12 + AppSpacing.fabSafeBottom,
          ),
          children: [
            if (isReconnecting) const SessionReconnectBanner(),
            ?connectedBridgeBanner,
            ?promoBanner,
            ?providerAuthStrip,
            SectionHeader(
              icon: Icons.history,
              label: l.recentSessions,
              color: appColors.subtleText,
            ),
            const SizedBox(height: 8),
            const _SessionListSkeleton(),
          ],
        );
      }

      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (isReconnecting) const SessionReconnectBanner(),
          ?connectedBridgeBanner,
          ?promoBanner,
          ?providerAuthStrip,
          const SizedBox(height: 80),
          SessionListEmptyState(onNewSession: widget.onNewSession),
        ],
      );
    }

    return ListView(
      key: const ValueKey('session_list'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + AppSpacing.fabSafeBottom,
      ),
      children: [
        if (isReconnecting) const SessionReconnectBanner(),
        ?connectedBridgeBanner,
        ?promoBanner,
        ?providerAuthStrip,
        if (hasRunningSessions) ...[
          SectionHeader(
            icon: Icons.play_circle_filled,
            label: l.running,
            color: appColors.statusOnline,
            trailing: needsYouCount > 0
                ? Text(
                    '$needsYouCount need you',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: appColors.statusApproval,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 4),
          for (final action in widget.offlinePendingActions)
            OfflinePendingSessionCard(
              key: ValueKey('pending_session_${action.id}'),
              action: action,
              onCancel:
                  widget.onCancelOfflinePendingAction == null ||
                      !action.canCancel
                  ? null
                  : () => widget.onCancelOfflinePendingAction!(action.id),
            ),
          for (final session in sortedSessions)
            Slidable(
              key: ValueKey('running_session_${session.id}'),
              endActionPane: ActionPane(
                motion: const BehindMotion(),
                extentRatio: 0.18,
                children: [
                  CustomSlidableAction(
                    onPressed: (_) => widget.onStopSession(session.id),
                    backgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.stop_circle_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              child: RunningSessionCard(
                session: session,
                isUnseen: widget.unseenSessionIds.contains(session.id),
                isSelected:
                    selectedSessionId == session.id &&
                    selectedSessionProvider == session.provider,
                onLongPress: () =>
                    widget.onLongPressRunningSession(session, null),
                onShowActions: (position) =>
                    widget.onLongPressRunningSession(session, position),
                onStop: showInlineStopButton
                    ? () => widget.onStopSession(session.id)
                    : null,
                onTap: () => widget.onTapRunning(
                  session.id,
                  projectPath: session.projectPath,
                  gitBranch: session.worktreePath != null
                      ? session.worktreeBranch
                      : session.gitBranch,
                  worktreePath: session.worktreePath,
                  provider: session.provider,
                  permissionMode: session.permissionMode,
                  sandboxMode: session.codexSandboxMode,
                  approvalPolicy: session.codexApprovalPolicy,
                  approvalsReviewer: session.codexApprovalsReviewer,
                ),
                onApprove: (toolUseId, {bool clearContext = false}) => widget
                    .onApprovePermission
                    ?.call(session.id, toolUseId, clearContext: clearContext),
                onApproveAlways: (toolUseId) =>
                    widget.onApproveAlways?.call(session.id, toolUseId),
                onReject: (toolUseId, {String? message}) => widget
                    .onRejectPermission
                    ?.call(session.id, toolUseId, message: message),
                onAnswer: (toolUseId, result) => widget.onAnswerQuestion?.call(
                  session.id,
                  toolUseId,
                  result,
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (widget.isInitialLoading ||
            hasRecentSessions ||
            hasActiveFilter) ...[
          SectionHeader(
            icon: Icons.history,
            label: l.recentSessions,
            color: appColors.subtleText,
            trailing: IconButton(
              key: const ValueKey('search_button'),
              icon: Icon(
                _isSearching ? Icons.close : Icons.search,
                size: 18,
                color: appColors.subtleText,
              ),
              onPressed: _toggleSearch,
              tooltip: l.search,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (_isSearching) ...[
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('search_field'),
              controller: _searchController,
              autofocus: true,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: l.searchSessions,
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: appColors.subtleText,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: appColors.subtleText.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: appColors.subtleText.withValues(alpha: 0.3),
                  ),
                ),
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (v) =>
                  context.read<SessionListCubit>().setSearchQuery(v),
            ),
          ],
          const SizedBox(height: 8),
          SessionFilterBar(
            displayMode: _displayMode,
            onToggleDisplayMode: _toggleDisplayMode,
            providerFilter: widget.providerFilter,
            onToggleProviderFilter: widget.onToggleProvider,
            projects: widget.accumulatedProjectPaths.map((path) {
              return (path: path, name: path.split('/').last);
            }).toList(),
            currentProjectFilter: widget.currentProjectFilter,
            onProjectFilterChanged: widget.onSelectProject,
            namedOnly: widget.namedOnly,
            onToggleNamed: widget.onToggleNamed,
          ),
          const SizedBox(height: 8),
          if (widget.isInitialLoading)
            const _SessionListSkeleton()
          else ...[
            if (filteredSessions.isEmpty)
              _RecentSessionsEmptyResult(
                title: hasActiveFilter
                    ? l.noSessionsMatchFilters
                    : l.noRecentSessions,
                subtitle: hasActiveFilter ? l.adjustFiltersAndSearch : null,
              )
            else
              ..._buildGroupedRecentCards(context, filteredSessions, l),
            if (widget.hasMoreSessions) ...[
              const SizedBox(height: 8),
              Center(
                child: widget.isLoadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        key: const ValueKey('load_more_button'),
                        onPressed: widget.onLoadMore,
                        icon: const Icon(Icons.expand_more, size: 18),
                        label: Text(l.loadMore),
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ],
    );
  }
}

class _ProviderAuthStatusChip extends StatelessWidget {
  final ProviderAuthStatusInfo status;

  const _ProviderAuthStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final provider = status.parsedProvider;
    final providerStyle = providerStyleFor(context, provider);
    final isHealthy = status.installed && status.authenticated;
    final color = isHealthy
        ? appColors.statusOnline
        : status.installed
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final detail = _statusText(status);

    return Tooltip(
      message: '${status.providerLabel}: $detail',
      child: Container(
        key: ValueKey('provider_auth_${status.provider}'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isHealthy ? 0.11 : 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(providerStyle.icon, size: 13, color: providerStyle.foreground),
            const SizedBox(width: 5),
            Text(
              status.providerLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: providerStyle.foreground,
                height: 1,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              isHealthy ? Icons.verified_outlined : Icons.error_outline,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              detail,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusText(ProviderAuthStatusInfo status) {
    if (!status.installed) return 'CLI missing';
    if (!status.authenticated) return 'Sign in needed';
    if (status.provider == Provider.claude.value) {
      final plan = _titleCase(status.subscriptionType);
      if (plan != null) return '$plan signed in';
    }
    return 'Signed in';
  }

  static String? _titleCase(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.length == 1) return trimmed.toUpperCase();
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}';
  }
}

/// Quiet date-group subheader for the Recent list (Today/Yesterday/This
/// week/Earlier). Mirrors [SectionHeader]'s caps typography but without a
/// leading icon and in subtleText, so it reads as a soft divider rather than a
/// second primary section.
class _DateGroupSubheader extends StatelessWidget {
  final String label;

  const _DateGroupSubheader({required this.label});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 12, bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: appColors.subtleText,
        ),
      ),
    );
  }
}

class _RecentSessionsEmptyResult extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _RecentSessionsEmptyResult({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Icon(Icons.filter_alt_off, color: appColors.subtleText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: appColors.subtleText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfflinePendingSessionCard extends StatelessWidget {
  const OfflinePendingSessionCard({
    super.key,
    required this.action,
    this.onCancel,
  });

  final OfflinePendingAction action;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final l = AppLocalizations.of(context);
    final provider = providerFromRaw(action.provider);
    final providerStyle = providerStyleFor(context, provider);
    final statusColor = colorScheme.tertiary;
    final subtitle = switch (action.kind) {
      OfflinePendingActionKind.start => l.pendingActionWillCreateOnReconnect,
      OfflinePendingActionKind.resume => l.pendingActionWillResumeOnReconnect,
    };
    final title = switch (action.kind) {
      OfflinePendingActionKind.start => l.offlinePendingNewSessionTitle,
      OfflinePendingActionKind.resume => l.offlinePendingResumeTitle,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 0),
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: statusColor.withValues(alpha: 0.5), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: statusColor.withValues(alpha: 0.08),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l.pendingActionStatus,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor.withValues(alpha: 0.82),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onCancel != null)
                  IconButton(
                    key: const ValueKey('pending_session_cancel_button'),
                    onPressed: onCancel,
                    tooltip: l.tooltipCancelPendingAction,
                    icon: const Icon(Icons.close),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 28,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: providerStyle.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: providerStyle.border,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        action.projectName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: providerStyle.foreground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 13,
                      color: appColors.subtleText,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        l.queuedLocally,
                        style: TextStyle(
                          fontSize: 11,
                          color: appColors.subtleText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton placeholder that mimics a list of [RecentSessionCard] widgets.
///
/// Uses [Skeletonizer] to render dummy cards with a shimmer animation,
/// providing visual feedback while the initial session list is loading.
class _SessionListSkeleton extends StatelessWidget {
  const _SessionListSkeleton();

  static const _dummySessions = [
    RecentSession(
      sessionId: 'skeleton-1',
      firstPrompt: 'Implement the new feature for user authentication flow',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'feat/auth',
      projectPath: '/projects/my-app',
      isSidechain: false,
    ),
    RecentSession(
      sessionId: 'skeleton-2',
      firstPrompt: 'Fix the CI pipeline build failure on main branch',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'fix/ci',
      projectPath: '/projects/backend',
      isSidechain: false,
    ),
    RecentSession(
      sessionId: 'skeleton-3',
      firstPrompt: 'Add dark mode support to the settings page',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'main',
      projectPath: '/projects/mobile',
      isSidechain: false,
    ),
    RecentSession(
      sessionId: 'skeleton-4',
      firstPrompt: 'Refactor database queries for better performance',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'perf/db',
      projectPath: '/projects/api',
      isSidechain: false,
    ),
    RecentSession(
      sessionId: 'skeleton-5',
      firstPrompt: 'Update documentation for the REST API endpoints',
      created: '2025-01-01T00:00:00Z',
      modified: '2025-01-01T01:00:00Z',
      gitBranch: 'docs',
      projectPath: '/projects/docs',
      isSidechain: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      child: Column(
        children: [
          for (final session in _dummySessions)
            RecentSessionCard(session: session, onTap: () {}),
        ],
      ),
    );
  }
}
