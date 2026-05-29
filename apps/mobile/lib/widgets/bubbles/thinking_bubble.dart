import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../google_search_text_selection.dart';

/// Displays Claude's thinking content with a collapsible UI.
///
/// When [isStreaming] is true, shows an animated indicator.
class ThinkingBubble extends StatefulWidget {
  final String thinking;
  final bool initiallyExpanded;

  /// Whether thinking is still streaming (shows animation).
  final bool isStreaming;

  const ThinkingBubble({
    super.key,
    required this.thinking,
    this.initiallyExpanded = false,
    this.isStreaming = false,
  });

  @override
  State<ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isStreaming) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ThinkingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isStreaming && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final trimmedThinking = widget.thinking.trim();

    // Empty/whitespace thinking deltas should paint nothing unless we are
    // actively streaming (where the animated indicator is still meaningful).
    if (trimmedThinking.isEmpty && !widget.isStreaming) {
      return const SizedBox.shrink();
    }

    final thinkingColor = appColors.thinking;
    final preview = trimmedThinking.length > 80
        ? '${trimmedThinking.substring(0, 80)}...'
        : trimmedThinking;
    final lineCount = trimmedThinking.isEmpty
        ? 0
        : '\n'.allMatches(trimmedThinking).length + 1;
    // Only surface the line count when it adds information (>= 2 lines);
    // never show "0 lines" or a redundant "1 line".
    final lineLabel = '$lineCount lines';
    final showLineCount = lineCount >= 2;
    final showPreview = preview.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: thinkingColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: appColors.thinkingBorder,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Animated icon when streaming
                    if (widget.isStreaming)
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _pulseAnimation.value,
                            child: Icon(
                              Icons.psychology,
                              size: 16,
                              color: thinkingColor,
                            ),
                          );
                        },
                      )
                    else
                      Icon(Icons.psychology, size: 16, color: thinkingColor),
                    const SizedBox(width: 6),
                    Text(
                      widget.isStreaming ? 'Thinking...' : 'Thinking',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: thinkingColor,
                      ),
                    ),
                    if (showLineCount) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: thinkingColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          lineLabel,
                          style: TextStyle(fontSize: 10, color: thinkingColor),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: thinkingColor.withValues(alpha: 0.6),
                    ),
                  ],
                ),
                if (!_expanded && showPreview) ...[
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (_expanded) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        widget.thinking,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.8),
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                        contextMenuBuilder:
                            googleSearchSelectableTextContextMenuBuilder,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
