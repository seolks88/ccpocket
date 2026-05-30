import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../l10n/app_localizations.dart';
import '../theme/markdown_style.dart';
import 'sheet_handle.dart';
import 'workspace_pane_chrome.dart';

/// Shows a full-screen bottom sheet with the complete plan text.
Future<void> showPlanDetailSheet(BuildContext context, String planText) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: macOSModalBottomSheetConstraints(context),
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _PlanDetailContent(planText: planText),
  );
}

class _PlanDetailContent extends StatelessWidget {
  final String planText;

  const _PlanDetailContent({required this.planText});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.assignment, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.implementationPlan,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(child: _PlanViewMode(planText: planText)),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _PlanViewMode extends StatelessWidget {
  final String planText;

  const _PlanViewMode({required this.planText});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: suppressMarkdownScrollbarIndicators(
        context,
        child: MarkdownBody(
          data: planText,
          selectable: true,
          styleSheet: buildMarkdownStyle(context),
          onTapLink: handleMarkdownLink,
          inlineSyntaxes: colorCodeInlineSyntaxes,
          builders: markdownBuilders,
        ),
      ),
    );
  }
}
