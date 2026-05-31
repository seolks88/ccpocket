import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/markdown_style.dart';

const _liveMarkdownMaxChars = 2400;
final _markdownFencePattern = RegExp(r'```');

@visibleForTesting
bool shouldRenderStreamingMarkdown(String text) {
  if (text.length > _liveMarkdownMaxChars) return false;
  return !_markdownFencePattern.allMatches(text).length.isOdd;
}

/// Renders an in-progress assistant turn.
///
/// Shares the calm, left-anchored bubble idiom with the finished assistant
/// answer ([AssistantBubble]), but adds an explicit "live" affordance — a
/// pulsing status dot + label header — so a glance tells the user the agent is
/// still composing its reply rather than done.
class StreamingBubble extends StatefulWidget {
  final String text;
  final String thinking;
  final bool showPlaceholder;

  const StreamingBubble({
    super.key,
    required this.text,
    this.thinking = '',
    this.showPlaceholder = false,
  });

  @override
  State<StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<StreamingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;
  late final DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // reducedMotion() needs a BuildContext (unavailable in initState), so the
    // repeat() decision lives here. Also re-runs if the reduced-motion setting
    // changes at runtime: stop blinking and settle to a solid caret.
    if (reducedMotion(context)) {
      if (_cursorController.isAnimating) {
        _cursorController.stop();
        _cursorController.reset();
      }
    } else if (!_cursorController.isAnimating) {
      _cursorController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmedText = widget.text.trim();
    final trimmedThinking = widget.thinking.trim();
    final hasText = trimmedText.isNotEmpty;
    final hasThinking = trimmedThinking.isNotEmpty;
    if (!hasText && !hasThinking && !widget.showPlaceholder) {
      return const SizedBox.shrink();
    }

    final appColors = Theme.of(context).extension<AppColors>()!;
    final textTheme = Theme.of(context).textTheme;
    final liveLabel = hasThinking && !hasText
        ? 'Thinking...'
        : AppLocalizations.of(context).working;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(
          vertical: AppSpacing.bubbleMarginV,
          horizontal: AppSpacing.bubbleMarginH,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.bubblePaddingV,
          horizontal: AppSpacing.bubblePaddingH,
        ),
        // Full width so streamed tables / code blocks / wide markdown are
        // readable (the answer is what you read — give it the room).
        width: double.infinity,
        decoration: BoxDecoration(
          color: appColors.assistantBubble,
          borderRadius: AppSpacing.assistantBubbleBorderRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Live header: pulsing dot + label. Color (statusRunning) is always
            // paired with the text label so the state is never color-only.
            _LiveHeader(
              controller: _cursorController,
              color: appColors.statusRunning,
              label: liveLabel,
              startedAt: _startedAt,
              labelStyle: textTheme.labelMedium?.copyWith(
                color: appColors.statusRunning,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hasText) ...[
              const SizedBox(height: AppSpacing.sm),
              _LiveTextContent(text: widget.text),
            ] else if (hasThinking) ...[
              const SizedBox(height: AppSpacing.sm),
              _ThinkingPreview(text: trimmedThinking),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveTextContent extends StatelessWidget {
  final String text;

  const _LiveTextContent({required this.text});

  @override
  Widget build(BuildContext context) {
    if (!shouldRenderStreamingMarkdown(text)) {
      return Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
      );
    }

    return suppressMarkdownScrollbarIndicators(
      context,
      child: MarkdownBody(
        data: text,
        styleSheet: buildMarkdownStyle(context),
        onTapLink: handleMarkdownLink,
        inlineSyntaxes: colorCodeInlineSyntaxes,
        builders: streamingMarkdownBuilders,
      ),
    );
  }
}

class _ThinkingPreview extends StatelessWidget {
  final String text;

  const _ThinkingPreview({required this.text});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final preview = text.length > 180 ? '${text.substring(0, 180)}...' : text;
    return Text(
      preview,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: appColors.subtleText,
        height: 1.35,
      ),
    );
  }
}

/// Animated "live" header row: a pulsing dot next to a status label.
///
/// Mirrors the animated header pattern used by the thinking bubble so the two
/// in-progress states read as part of one family.
class _LiveHeader extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  final String label;
  final DateTime startedAt;
  final TextStyle? labelStyle;

  const _LiveHeader({
    required this.controller,
    required this.color,
    required this.label,
    required this.startedAt,
    required this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Under reduced motion the controller is parked; show a solid,
        // non-blinking dot (the pulse's full-opacity end-state).
        if (reducedMotion(context))
          dot
        else
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              // Pulse opacity between a calm floor and full so the dot reads as
              // alive without strobing.
              final opacity = 0.4 + (controller.value * 0.6);
              return Opacity(opacity: opacity, child: child);
            },
            child: dot,
          ),
        const SizedBox(width: AppSpacing.sm),
        _ElapsedLabel(label: label, startedAt: startedAt, style: labelStyle),
      ],
    );
  }
}

class _ElapsedLabel extends StatefulWidget {
  final String label;
  final DateTime startedAt;
  final TextStyle? style;

  const _ElapsedLabel({
    required this.label,
    required this.startedAt,
    required this.style,
  });

  @override
  State<_ElapsedLabel> createState() => _ElapsedLabelState();
}

class _ElapsedLabelState extends State<_ElapsedLabel> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(widget.startedAt);
      });
    });
  }

  @override
  void didUpdateWidget(covariant _ElapsedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _elapsed = DateTime.now().difference(widget.startedAt);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelWithElapsed = _elapsed.inSeconds > 0
        ? '${widget.label} ${_formatElapsed(_elapsed)}'
        : widget.label;
    return Text(labelWithElapsed, style: widget.style);
  }

  String _formatElapsed(Duration duration) {
    if (duration.inMinutes >= 1) {
      return '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${duration.inSeconds}s';
  }
}
