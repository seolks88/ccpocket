import 'package:flutter/material.dart';

import '../../models/messages.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_text_style.dart';
import '../permission_presentation_view.dart';

class PermissionRequestBubble extends StatefulWidget {
  final PermissionRequestMessage message;
  final bool isCodex;
  const PermissionRequestBubble({
    super.key,
    required this.message,
    this.isCodex = false,
  });

  @override
  State<PermissionRequestBubble> createState() =>
      _PermissionRequestBubbleState();
}

class _PermissionRequestBubbleState extends State<PermissionRequestBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final presentation = widget.message.presentation;
    final detailLines = presentation.secondaryDetails;
    final inputStr = presentation.rawDetails;
    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: AppSpacing.bubbleMarginV,
        horizontal: AppSpacing.bubbleMarginH,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: appColors.permissionBubble,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: appColors.permissionBubbleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PermissionPresentationView(
            title: presentation.title,
            summary: Text(presentation.summary),
            primaryTarget: presentation.primaryTarget,
            detailLines: detailLines,
            onHeaderTap: () => setState(() => _expanded = !_expanded),
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: AppIconSize.action,
              color: appColors.subtleText,
            ),
          ),
          // Settle the inline detail height on toggle instead of jumping.
          // Height tween only; instant under reduced motion.
          AnimatedSize(
            duration: motionDuration(context, AppMotion.standard),
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_expanded) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    inputStr,
                    style: codeTextSettingsOf(context).style(
                      color: appColors.subtleText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
