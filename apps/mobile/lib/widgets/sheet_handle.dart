import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// The standard drag handle for modal bottom sheets.
///
/// Renders a centered 32x4 pill with ~[AppSpacing.md] vertical padding so the
/// handle looks identical across every sheet. Dependency-light and const so it
/// can be dropped in place of the old inline `Container` handles.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            // Matches the original inline handles this widget replaced.
            color: appColors.subtleText.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
