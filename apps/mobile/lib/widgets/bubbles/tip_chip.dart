import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/messages.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

/// A gentle, non-intrusive hint for informational tips (e.g. "no git detected").
///
/// Deliberately container-less: a soft info glyph + subtle text, no background
/// pill — quieter than [SystemChip], so a passing tip never reads as a state
/// the user must act on.
class TipChip extends StatelessWidget {
  final SystemMessage message;
  const TipChip({super.key, required this.message});

  String _text(AppLocalizations l) => switch (message.tipCode) {
    'git_not_available' => l.gitUnavailableTip,
    'auto_mode_fallback_default' => l.autoModeFallbackDefaultTip,
    _ => message.subtype,
  };

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: AppIconSize.chip,
              color: appColors.subtleText,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                _text(l),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: appColors.subtleText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
