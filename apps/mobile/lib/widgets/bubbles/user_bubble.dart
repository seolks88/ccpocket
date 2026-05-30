import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/messages.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_text_style.dart';
import '../../utils/command_parser.dart';
import '../adaptive_context_menu.dart';

class UserBubble extends StatelessWidget {
  final String text;
  final MessageStatus status;
  final VoidCallback? onRetry;
  final VoidCallback? onRewind;
  final List<String> imageUrls;
  final String? httpBaseUrl;
  final List<Uint8List> imageBytesList;

  /// Number of images attached (from history restoration when actual data is unavailable).
  final int imageCount;

  const UserBubble({
    super.key,
    required this.text,
    this.status = MessageStatus.sent,
    this.onRetry,
    this.onRewind,
    this.imageUrls = const [],
    this.httpBaseUrl,
    this.imageBytesList = const [],
    this.imageCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Detect command message with XML tags
    final parsed = parseCommandMessage(text);
    if (parsed != null) {
      return _CommandBubble(
        command: parsed,
        status: status,
        text: text,
        onRetry: onRetry,
        onRewind: onRewind,
        onShowContextMenu: (position) =>
            _showContextMenu(context, position: position),
      );
    }

    return _StandardBubble(
      displayText: text,
      status: status,
      onRetry: onRetry,
      onRewind: onRewind,
      imageBytesList: imageBytesList,
      imageUrls: imageUrls,
      httpBaseUrl: httpBaseUrl,
      onShowContextMenu: (position) =>
          _showContextMenu(context, position: position),
    );
  }

  void _showContextMenu(BuildContext context, {Offset? position}) async {
    final action = await showAdaptiveActionMenu<String>(
      context: context,
      position: position,
      items: [
        AdaptiveActionMenuItem(
          value: 'copy',
          icon: Icons.copy,
          label: AppLocalizations.of(context).copy,
        ),
        if (onRewind != null)
          AdaptiveActionMenuItem(
            value: 'rewind',
            icon: Icons.history,
            label: AppLocalizations.of(context).rewindToHere,
          ),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action == 'copy') {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).copied),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    if (action == 'rewind') {
      onRewind?.call();
    }
  }
}

/// Standard user message bubble.
class _StandardBubble extends StatelessWidget {
  final String displayText;
  final MessageStatus status;
  final VoidCallback? onRetry;
  final VoidCallback? onRewind;
  final List<Uint8List> imageBytesList;
  final List<String> imageUrls;
  final String? httpBaseUrl;
  final ValueChanged<Offset?> onShowContextMenu;

  const _StandardBubble({
    required this.displayText,
    required this.status,
    required this.onRetry,
    required this.onRewind,
    required this.imageBytesList,
    required this.imageUrls,
    required this.httpBaseUrl,
    required this.onShowContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerRight,
      child: AdaptiveContextMenuRegion(
        onOpen: onShowContextMenu,
        child: GestureDetector(
          onTap: status == MessageStatus.failed ? onRetry : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(
                  vertical: AppSpacing.bubbleMarginV,
                  horizontal: AppSpacing.bubbleMarginH,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.bubblePaddingV,
                  horizontal: AppSpacing.bubblePaddingH,
                ),
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width *
                      AppSpacing.maxBubbleWidthFraction,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: AppSpacing.userBubbleBorderRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (imageBytesList.isNotEmpty ||
                        (imageUrls.isNotEmpty && httpBaseUrl != null))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final bytes in imageBytesList)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  bytes,
                                  width: imageBytesList.length == 1 ? 200 : 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        width: imageBytesList.length == 1
                                            ? 200
                                            : 120,
                                        height: 80,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHigh,
                                        child: const Icon(Icons.broken_image),
                                      ),
                                ),
                              ),
                            if (imageBytesList.isEmpty)
                              for (final url in imageUrls)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    '$httpBaseUrl$url',
                                    width: imageUrls.length == 1 ? 200 : 120,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              width: imageUrls.length == 1
                                                  ? 200
                                                  : 120,
                                              height: 80,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHigh,
                                              child: const Icon(
                                                Icons.broken_image,
                                              ),
                                            ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    if (displayText.isNotEmpty)
                      _UserMessageBody(text: displayText),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.bubbleMarginH),
                child: _StatusIndicator(status: status),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Body for a standard (non-command) user message.
///
/// Short, normal chat text renders as plain proportional text and is visually
/// unchanged. Large or code-like payloads — injected context dumps (e.g. a
/// leading "# Files mentioned" marker), fenced code blocks, or anything over
/// [_lineThreshold] lines — are detected conservatively and rendered:
///   * in monospace via [codeTextSettingsOf] when the content is code-like, and
///   * collapsed behind a >=44px "Show more" affordance so a huge paste cannot
///     dominate the conversation.
///
/// Plain [Text] (not [SelectableText]) is used so the surrounding
/// [AdaptiveContextMenuRegion] long-press menu (copy / rewind) and tap-to-retry
/// on failed messages keep working; copy stays available via that menu.
class _UserMessageBody extends StatefulWidget {
  final String text;

  const _UserMessageBody({required this.text});

  /// A user message with more than this many lines is treated as "large" and
  /// gets the selectable + collapsible treatment.
  static const int _lineThreshold = 8;

  /// Number of lines shown before the message is collapsed.
  static const int _collapsedMaxLines = 6;

  @override
  State<_UserMessageBody> createState() => _UserMessageBodyState();
}

class _UserMessageBodyState extends State<_UserMessageBody> {
  bool _expanded = false;

  /// True when the payload looks like injected context / a dump that benefits
  /// from monospace rendering (file lists, pasted code), as opposed to long
  /// prose. Kept deliberately conservative.
  bool get _isCodeLike {
    final t = widget.text;
    if (t.contains('```')) return true;
    final trimmedStart = t.trimLeft();
    // Client-injected context markers, e.g. "# Files mentioned by the user:".
    if (trimmedStart.startsWith('# Files mentioned') ||
        trimmedStart.startsWith('<files') ||
        trimmedStart.startsWith('# File contents') ||
        trimmedStart.startsWith('# Code')) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;

    final lines = widget.text.split('\n');
    final isCodeLike = _isCodeLike;
    final isLarge =
        isCodeLike || lines.length > _UserMessageBody._lineThreshold;

    // Short, normal chat message: plain text — matches pre-refactor behavior so
    // the bubble's long-press copy/rewind menu and tap-to-retry still fire.
    if (!isLarge) {
      return Text(
        widget.text,
        style: TextStyle(color: cs.onPrimaryContainer),
      );
    }

    final TextStyle bodyStyle = isCodeLike
        ? codeTextSettingsOf(context).style(color: cs.onPrimaryContainer)
        : TextStyle(color: cs.onPrimaryContainer, height: 1.4);

    final collapsedMaxLines = _UserMessageBody._collapsedMaxLines;
    final hasMore = lines.length > collapsedMaxLines;
    final hiddenLines = lines.length - collapsedMaxLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: bodyStyle,
          maxLines: _expanded ? null : collapsedMaxLines,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasMore)
          _ShowMoreToggle(
            expanded: _expanded,
            hiddenLines: hiddenLines,
            color: appColors.subtleText,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
      ],
    );
  }
}

/// "Show more / Show less" affordance with a guaranteed >=44px hit area even
/// though the painted label is compact.
class _ShowMoreToggle extends StatelessWidget {
  final bool expanded;
  final int hiddenLines;
  final Color color;
  final VoidCallback onTap;

  const _ShowMoreToggle({
    required this.expanded,
    required this.hiddenLines,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = expanded
        ? l10n.showLess
        : '${l10n.showMore} (${l10n.lineCountSummary(hiddenLines)})';

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.codeRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: AppIconSize.inline,
                  color: color,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// CLI-style command bubble: "/command-name args" in a single bubble.
class _CommandBubble extends StatelessWidget {
  final ParsedCommand command;
  final MessageStatus status;
  final String text;
  final VoidCallback? onRetry;
  final VoidCallback? onRewind;
  final ValueChanged<Offset?> onShowContextMenu;

  const _CommandBubble({
    required this.command,
    required this.status,
    required this.text,
    required this.onRetry,
    required this.onRewind,
    required this.onShowContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasArgs = command.args != null && command.args!.isNotEmpty;

    return Align(
      alignment: Alignment.centerRight,
      child: AdaptiveContextMenuRegion(
        onOpen: onShowContextMenu,
        child: GestureDetector(
          onTap: status == MessageStatus.failed ? onRetry : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(
                  vertical: AppSpacing.bubbleMarginV,
                  horizontal: AppSpacing.bubbleMarginH,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.bubblePaddingV,
                  horizontal: AppSpacing.bubblePaddingH,
                ),
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width *
                      AppSpacing.maxBubbleWidthFraction,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: AppSpacing.userBubbleBorderRadius,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: command.commandName,
                        style: codeTextSettingsOf(context).style(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasArgs) ...[
                        TextSpan(
                          text: ' ${command.args}',
                          style: TextStyle(color: cs.onPrimaryContainer),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.bubbleMarginH),
                child: _StatusIndicator(status: status),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final MessageStatus status;

  const _StatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;

    return switch (status) {
      MessageStatus.sending => SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: appColors.subtleText,
        ),
      ),
      MessageStatus.queued => Icon(
        Icons.schedule,
        size: 14,
        color: appColors.subtleText,
      ),
      MessageStatus.sent => Icon(
        Icons.check,
        size: 14,
        color: appColors.subtleText,
      ),
      MessageStatus.failed => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 14,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).tapToRetry,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    };
  }
}
