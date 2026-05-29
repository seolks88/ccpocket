import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/markdown_style.dart';

/// Renders an in-progress assistant turn.
///
/// Shares the calm, left-anchored bubble idiom with the finished assistant
/// answer ([AssistantBubble]), but adds an explicit "live" affordance — a
/// pulsing status dot + label header and a blinking caret — so a glance tells
/// the user the agent is still composing its reply rather than done.
class StreamingBubble extends StatefulWidget {
  final String text;
  const StreamingBubble({super.key, required this.text});

  @override
  State<StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<StreamingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();

    final appColors = Theme.of(context).extension<AppColors>()!;
    final textTheme = Theme.of(context).textTheme;

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
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              AppSpacing.maxBubbleWidthFraction,
        ),
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
              label: AppLocalizations.of(context).working,
              labelStyle: textTheme.labelMedium?.copyWith(
                color: appColors.statusRunning,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            suppressMarkdownScrollbarIndicators(
              context,
              child: MarkdownBody(
                data: widget.text,
                styleSheet: buildMarkdownStyle(context),
                onTapLink: handleMarkdownLink,
                inlineSyntaxes: colorCodeInlineSyntaxes,
                builders: markdownBuilders,
              ),
            ),
            // Blinking caret as a secondary, inline "still typing" cue.
            AnimatedBuilder(
              animation: _cursorController,
              builder: (context, child) {
                return Opacity(
                  opacity: _cursorController.value,
                  child: Text(
                    '▍',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1,
                      color: appColors.statusRunning,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
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
  final TextStyle? labelStyle;

  const _LiveHeader({
    required this.controller,
    required this.color,
    required this.label,
    required this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            // Pulse opacity between a calm floor and full so the dot reads as
            // alive without strobing.
            final opacity = 0.4 + (controller.value * 0.6);
            return Opacity(
              opacity: opacity,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: labelStyle),
      ],
    );
  }
}
