import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/messages.dart';
import 'package:auto_route/auto_route.dart';

import '../../router/app_router.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_text_style.dart';
import '../../utils/tool_categories.dart';
import '../google_search_text_selection.dart';
import 'image_preview.dart';
import 'tool_row_header.dart';

/// Three-level expansion state for tool result content.
enum ToolResultExpansion { collapsed, preview, expanded }

/// Glanceable outcome of a tool call, used to give failures real salience in
/// the stream (color + glyph, never color alone).
///
/// The wire `ToolResultMessage` carries no explicit `is_error` flag (the bridge
/// folds failures into the result text), so this is inferred from the content
/// with a conservative marker heuristic. False negatives degrade gracefully to
/// a normal row; we never style a success as an error.
enum ToolResultStatus { ok, error, empty }

/// Leading substrings that reliably indicate a failed tool result across the
/// Claude CLI / Codex bridges (matched case-insensitively against the trimmed
/// content). Kept intentionally narrow to avoid false positives on normal
/// output that merely mentions the word "error".
const _errorContentMarkers = <String>[
  'error:',
  'error ',
  'error\n',
  '<tool_use_error>',
  'tool execution failed',
  'command failed',
  'execution failed',
  'traceback (most recent call last)',
  'exception:',
  'fatal:',
  'permission denied',
  'no such file or directory',
];

/// True when [content] looks like a failed tool result.
bool _looksLikeToolError(String content) {
  final trimmed = content.trimLeft();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  // Bare "Error" (whole content) or any of the leading markers.
  if (lower == 'error') return true;
  for (final marker in _errorContentMarkers) {
    if (lower.startsWith(marker)) return true;
  }
  return false;
}

const _imageGenerationToolName = 'ImageGeneration';

class ToolResultBubble extends StatefulWidget {
  final ToolResultMessage message;
  final String? httpBaseUrl;

  /// When this notifier's value changes, the bubble auto-collapses.
  /// ClaudeSessionScreen increments it whenever a new assistant message arrives.
  final ValueNotifier<int>? collapseNotifier;

  const ToolResultBubble({
    super.key,
    required this.message,
    this.httpBaseUrl,
    this.collapseNotifier,
  });

  @override
  State<ToolResultBubble> createState() => ToolResultBubbleState();
}

class ToolResultBubbleState extends State<ToolResultBubble> {
  late ToolResultExpansion _expansion;
  bool _restoredFromStorage = false;

  @override
  void initState() {
    super.initState();
    _expansion = _defaultExpansion;
    widget.collapseNotifier?.addListener(_onCollapseSignal);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredFromStorage) return;
    _restoredFromStorage = true;

    final saved = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _storageKey);
    if (saved is String) {
      for (final value in ToolResultExpansion.values) {
        if (value.name == saved) {
          _expansion = value;
          return;
        }
      }
    }
    _expansion = _defaultExpansion;
  }

  @override
  void didUpdateWidget(ToolResultBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapseNotifier != widget.collapseNotifier) {
      oldWidget.collapseNotifier?.removeListener(_onCollapseSignal);
      widget.collapseNotifier?.addListener(_onCollapseSignal);
    }
  }

  @override
  void dispose() {
    widget.collapseNotifier?.removeListener(_onCollapseSignal);
    super.dispose();
  }

  void _onCollapseSignal() {
    if (_expansion != ToolResultExpansion.collapsed) {
      setState(() => _expansion = ToolResultExpansion.collapsed);
      _persistExpansion();
    }
  }

  void _cycleExpansion() {
    setState(() {
      _expansion = switch (_expansion) {
        ToolResultExpansion.collapsed => ToolResultExpansion.preview,
        ToolResultExpansion.preview => ToolResultExpansion.expanded,
        ToolResultExpansion.expanded => ToolResultExpansion.collapsed,
      };
    });
    _persistExpansion();
    HapticFeedback.selectionClick();
  }

  String get _storageKey => 'tool_result:${widget.message.toolUseId}';

  bool get _isCodeEditResult {
    final toolName = widget.message.toolName;
    return toolName == 'Edit' ||
        toolName == 'FileEdit' ||
        toolName == 'MultiEdit' ||
        toolName == 'Write' ||
        toolName == 'NotebookEdit' ||
        toolName == 'FileChange';
  }

  bool get _isMcpImageResult {
    final toolName = widget.message.toolName ?? '';
    return widget.message.images.isNotEmpty &&
        (toolName.startsWith('mcp__') || toolName.startsWith('mcp:'));
  }

  bool get _isImageGenerationResult =>
      widget.message.toolName == _imageGenerationToolName;

  bool get _hasRenderableImage =>
      widget.message.images.isNotEmpty && widget.httpBaseUrl != null;

  ToolResultExpansion get _defaultExpansion =>
      (_isCodeEditResult || _isMcpImageResult)
      ? ToolResultExpansion.preview
      : ToolResultExpansion.collapsed;

  void _persistExpansion() {
    PageStorage.maybeOf(
      context,
    )?.writeState(context, _expansion.name, identifier: _storageKey);
  }

  late final ToolCategory _category = categorizeToolName(
    widget.message.toolName ?? '',
  );

  /// Glanceable outcome of this result (error / empty / ok). Errors must read
  /// differently from successes; empty output gets a calm muted placeholder.
  ToolResultStatus get _status {
    final hasContent = widget.message.content.trim().isNotEmpty;
    if (!hasContent && widget.message.images.isEmpty) {
      return ToolResultStatus.empty;
    }
    if (_looksLikeToolError(widget.message.content)) {
      return ToolResultStatus.error;
    }
    return ToolResultStatus.ok;
  }

  String _buildSummary(String content, String? toolName, AppLocalizations l) {
    final lines = content.split('\n');
    final lineCount = lines.length;

    if (toolName == 'Edit' ||
        toolName == 'FileEdit' ||
        toolName == 'FileChange') {
      var added = 0;
      var removed = 0;
      for (final line in lines) {
        if (line.startsWith('+') && !line.startsWith('+++')) added++;
        if (line.startsWith('-') && !line.startsWith('---')) removed++;
      }
      if (added > 0 || removed > 0) {
        return l.diffSummaryAddedRemoved(added, removed);
      }
    }

    if (lineCount == 1 && content.length < 40) {
      return content;
    }

    return l.lineCountSummary(lineCount);
  }

  /// Whether this tool result contains a viewable diff.
  bool get _isDiffContent {
    final toolName = widget.message.toolName;
    if (toolName != 'Edit' &&
        toolName != 'FileEdit' &&
        toolName != 'FileChange') {
      return false;
    }
    final content = widget.message.content;
    // Check for unified diff markers
    return content.contains('---') && content.contains('+++') ||
        _hasDiffLines(content);
  }

  static bool _hasDiffLines(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      if ((line.startsWith('+') && !line.startsWith('+++')) ||
          (line.startsWith('-') && !line.startsWith('---'))) {
        return true;
      }
    }
    return false;
  }

  /// Whether tapping/expanding this result would actually reveal anything
  /// beyond the collapsed summary. False for zero-output and single-line
  /// results whose full text is already shown inline -- those render as a
  /// calm static row with no chevron and no tap target.
  bool get _hasExpandableContent {
    if (_isDiffContent) return true; // tap opens the diff/git screen
    if (widget.message.images.isNotEmpty) return true; // expansion shows images
    final content = widget.message.content;
    if (content.split('\n').length > 1) return true; // multi-line to reveal
    // Single line: only expandable if the collapsed summary truncates it
    // (i.e. the summary is not the full content). Mirrors _buildSummary.
    return content.length >= 40;
  }

  String? _extractFilePath() {
    final content = widget.message.content;
    final match = RegExp(r'\+\+\+ b/(.+)').firstMatch(content);
    return match?.group(1);
  }

  void _openGitScreen() {
    context.router.push(
      GitRoute(initialDiff: widget.message.content, title: _extractFilePath()),
    );
  }

  void _onTap() {
    if (_isDiffContent) {
      _openGitScreen();
    } else {
      _cycleExpansion();
    }
  }

  void _copyContent(BuildContext context) {
    final content = widget.message.content;
    if (content.isEmpty) return;
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).copiedToClipboard),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isImageGenerationResult && _hasRenderableImage) {
      return _ImageGenerationResultCard(
        message: widget.message,
        httpBaseUrl: widget.httpBaseUrl!,
        onLongPress: () => _copyContent(context),
      );
    }

    final l = AppLocalizations.of(context);
    final summary = _buildSummary(
      widget.message.content,
      widget.message.toolName,
      l,
    );

    final status = _status;

    if (_expansion == ToolResultExpansion.collapsed) {
      final hasExpandableContent = _hasExpandableContent;
      return _CollapsedToolResult(
        toolName: widget.message.toolName,
        category: _category,
        summary: summary,
        status: status,
        hasExpandableContent: hasExpandableContent,
        onTap: hasExpandableContent ? _onTap : null,
        onLongPress: () => _copyContent(context),
      );
    }
    return _ExpandedToolResult(
      message: widget.message,
      httpBaseUrl: widget.httpBaseUrl,
      category: _category,
      summary: summary,
      status: status,
      expansion: _expansion,
      onTap: _onTap,
      onLongPress: () => _copyContent(context),
    );
  }
}

class _ImageGenerationResultCard extends StatefulWidget {
  final ToolResultMessage message;
  final String httpBaseUrl;
  final VoidCallback onLongPress;

  const _ImageGenerationResultCard({
    required this.message,
    required this.httpBaseUrl,
    required this.onLongPress,
  });

  @override
  State<_ImageGenerationResultCard> createState() =>
      _ImageGenerationResultCardState();
}

class _ImageGenerationResultCardState
    extends State<_ImageGenerationResultCard> {
  bool _detailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final colorScheme = Theme.of(context).colorScheme;
    final metadata = _ImageGenerationMetadata.fromContent(
      widget.message.content,
    );

    return Container(
      key: const ValueKey('image_generation_result_card'),
      margin: const EdgeInsets.symmetric(
        vertical: 4,
        horizontal: AppSpacing.bubbleMarginH,
      ),
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: appColors.toolResultBackground,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: colorScheme.secondary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ImagePreviewWidget(
                images: widget.message.images,
                httpBaseUrl: widget.httpBaseUrl,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 15,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Generated image',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (metadata.status != null)
                    _ImageGenerationStatusChip(status: metadata.status!),
                ],
              ),
              if (metadata.revisedPrompt != null) ...[
                const SizedBox(height: 6),
                Text(
                  metadata.revisedPrompt!,
                  style: TextStyle(
                    fontSize: 12,
                    color: appColors.subtleText,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('image_generation_details_button'),
                  onPressed: () {
                    setState(() => _detailsExpanded = !_detailsExpanded);
                    HapticFeedback.selectionClick();
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: appColors.subtleText,
                  ),
                  icon: Icon(
                    _detailsExpanded ? Icons.expand_less : Icons.chevron_right,
                    size: 16,
                  ),
                  label: Text(
                    _detailsExpanded ? 'Hide details' : 'Details',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_detailsExpanded) ...[
                const SizedBox(height: 4),
                SelectableText(
                  widget.message.content,
                  style: codeTextSettingsOf(context).style(
                    color: appColors.toolResultTextExpanded,
                  ),
                  contextMenuBuilder:
                      googleSearchSelectableTextContextMenuBuilder,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageGenerationStatusChip extends StatelessWidget {
  final String status;

  const _ImageGenerationStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colorScheme.secondary,
        ),
      ),
    );
  }
}

class _ImageGenerationMetadata {
  final String? status;
  final String? revisedPrompt;

  const _ImageGenerationMetadata({this.status, this.revisedPrompt});

  factory _ImageGenerationMetadata.fromContent(String content) {
    return _ImageGenerationMetadata(
      status: _readPrefixedLine(content, 'status'),
      revisedPrompt: _readPrefixedLine(content, 'revisedPrompt'),
    );
  }
}

String? _readPrefixedLine(String content, String key) {
  final prefix = '$key:';
  for (final line in content.split('\n')) {
    if (!line.startsWith(prefix)) continue;
    final value = line.substring(prefix.length).trim();
    return value.isEmpty ? null : value;
  }
  return null;
}

/// Resolved per-status visuals for a tool-result row, so the collapsed row,
/// the expanded card, and any accents all read from one place (one concept,
/// one component, one token). Errors get a distinct glyph AND color so the
/// state is never carried by color alone.
class _ToolStatusVisuals {
  final IconData icon;

  /// Tint for the leading glyph + tool name + the call->result accent rule.
  final Color accent;

  /// Whether the summary should read as a muted placeholder ("(no output)").
  final bool muted;

  /// Drives the error tint/border on the row and card.
  final bool isError;

  const _ToolStatusVisuals({
    required this.icon,
    required this.accent,
    required this.muted,
    required this.isError,
  });

  factory _ToolStatusVisuals.resolve(
    ToolResultStatus status,
    ToolCategory category,
    AppColors appColors,
  ) {
    return switch (status) {
      ToolResultStatus.error => _ToolStatusVisuals(
        icon: Icons.error_outline,
        accent: appColors.errorText,
        muted: false,
        isError: true,
      ),
      ToolResultStatus.empty => _ToolStatusVisuals(
        icon: getToolCategoryIcon(category),
        accent: appColors.subtleText,
        muted: true,
        isError: false,
      ),
      ToolResultStatus.ok => _ToolStatusVisuals(
        icon: getToolCategoryIcon(category),
        accent: getToolCategoryColor(category, appColors),
        muted: false,
        isError: false,
      ),
    };
  }
}

/// Collapsed: inline log row. A >=44px hit area, a glyph-backed status tint,
/// and a thin left accent rule that visually ties the result to the call that
/// produced it (call -> result reads as a pair).
class _CollapsedToolResult extends StatelessWidget {
  final String? toolName;
  final ToolCategory category;
  final String summary;
  final ToolResultStatus status;

  /// Whether expanding would reveal anything beyond the inline summary.
  /// When false, the row is static: no chevron and not tap-to-expand.
  final bool hasExpandableContent;

  /// Null when the row has nothing more to reveal (renders non-tappable).
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  const _CollapsedToolResult({
    required this.toolName,
    required this.category,
    required this.summary,
    required this.status,
    required this.hasExpandableContent,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final l = AppLocalizations.of(context);
    final visuals = _ToolStatusVisuals.resolve(status, category, appColors);
    final isError = status == ToolResultStatus.error;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.bubbleMarginH,
        // Tighter vertical rhythm pulls the result up toward its call.
        vertical: 1,
      ),
      child: InkWell(
        // Tap-to-expand only when there is genuinely more to reveal; long-press
        // (copy) stays available so static rows are still copyable.
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppSpacing.codeRadius),
        child: ConstrainedBox(
          // Compact, space-efficient log row — deliberately denser than the
          // 44px standard since tool results stack many-per-screen and density
          // matters more than tap size for this scannable stream.
          constraints: const BoxConstraints(
            minHeight: AppSizes.compactRowMinHeight,
          ),
          child: Container(
            // Failures get a subtle tint + border so they pop out of an
            // otherwise-neutral stream; successes stay chrome-free.
            decoration: isError
                ? BoxDecoration(
                    color: appColors.errorBubble,
                    borderRadius: BorderRadius.circular(AppSpacing.codeRadius),
                    border: Border.all(color: appColors.errorBubbleBorder),
                  )
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: isError ? AppSpacing.sm : 0,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                // Left accent rule: shared hue with the status glyph ties the
                // result to its call.
                Container(
                  width: 2,
                  height: 16,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: visuals.accent.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                Expanded(
                  child: ToolRowHeader(
                    icon: visuals.icon,
                    accent: visuals.accent,
                    isError: visuals.isError,
                    muted: visuals.muted,
                    name: toolName ?? l.toolResult,
                    summaryText: status == ToolResultStatus.empty
                        ? '(no output)'
                        : summary,
                    iconSize: AppIconSize.chip,
                    trailing: hasExpandableContent
                        ? Icon(
                            Icons.chevron_right,
                            size: AppIconSize.chip,
                            color: appColors.subtleText,
                          )
                        : null,
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

/// Preview / Expanded: one card recipe shared with the tool-use card --
/// [AppSpacing.cardRadius] + a fill + [AppColors.toolBubbleBorder] (error
/// variants on failure). Monospace bodies route through CodeTextSettings so
/// they honour the user's configured code font + size.
class _ExpandedToolResult extends StatelessWidget {
  final ToolResultMessage message;
  final String? httpBaseUrl;
  final ToolCategory category;
  final String summary;
  final ToolResultStatus status;
  final ToolResultExpansion expansion;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const _previewLines = toolPreviewLines;

  const _ExpandedToolResult({
    required this.message,
    required this.httpBaseUrl,
    required this.category,
    required this.summary,
    required this.status,
    required this.expansion,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final l = AppLocalizations.of(context);
    final visuals = _ToolStatusVisuals.resolve(status, category, appColors);
    final isError = status == ToolResultStatus.error;
    final content = message.content;
    final toolName = message.toolName;
    final lines = content.split('\n');
    final hasMore = lines.length > _previewLines;
    final previewText = hasMore
        ? lines.take(_previewLines).join('\n')
        : content;

    final codeSettings = codeTextSettingsOf(context);
    final chevronIcon = expansion == ToolResultExpansion.preview
        ? Icons.expand_more
        : Icons.expand_less;

    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: AppSpacing.bubbleMarginV,
        horizontal: AppSpacing.bubbleMarginH,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isError
                ? appColors.errorBubble
                : appColors.toolResultBackground,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: isError
                  ? appColors.errorBubbleBorder
                  : appColors.toolBubbleBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.images.isNotEmpty && httpBaseUrl != null) ...[
                ImagePreviewWidget(
                  images: message.images,
                  httpBaseUrl: httpBaseUrl!,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              // Header row -- shared recipe with the collapsed row.
              ToolRowHeader(
                icon: visuals.icon,
                accent: visuals.accent,
                isError: visuals.isError,
                muted: visuals.muted,
                name: toolName ?? l.toolResult,
                summaryText: summary,
                iconSize: AppIconSize.chip,
                trailing: Icon(
                  chevronIcon,
                  size: AppIconSize.inline,
                  color: appColors.subtleText,
                ),
              ),
              // Content — settle the height when toggling preview<->expanded
              // instead of jumping. Height tween only; degrades to instant
              // under reduced motion via motionDuration.
              AnimatedSize(
                duration: motionDuration(context, AppMotion.standard),
                curve: AppMotion.curve,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (expansion == ToolResultExpansion.preview) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        previewText,
                        style: codeSettings.style(
                          color: isError
                              ? appColors.errorText
                              : appColors.toolResultText,
                        ),
                        maxLines: _previewLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: MoreLinesHint(
                            remaining: lines.length - _previewLines,
                          ),
                        ),
                    ] else if (expansion ==
                        ToolResultExpansion.expanded) ...[
                      const SizedBox(height: AppSpacing.xs),
                      SelectableText(
                        content,
                        style: codeSettings.style(
                          color: isError
                              ? appColors.errorText
                              : appColors.toolResultTextExpanded,
                        ),
                        contextMenuBuilder:
                            googleSearchSelectableTextContextMenuBuilder,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
