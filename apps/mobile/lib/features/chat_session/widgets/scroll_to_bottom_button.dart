import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';

class ScrollToBottomButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ScrollToBottomButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Scroll to bottom',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
          boxShadow: AppElevation.overlay,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('scroll_to_bottom_button'),
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 24,
                  color: cs.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
