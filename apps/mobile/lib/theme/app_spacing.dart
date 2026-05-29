import 'package:flutter/painting.dart';

abstract class AppSpacing {
  // ---- Bubble / card geometry (existing) ----
  static const double bubbleMarginH = 12;
  static const double bubbleMarginV = 4;
  static const double bubblePaddingH = 14;
  static const double bubblePaddingV = 10;
  static const double bubbleRadius = 16;
  static const double cardRadius = 12;
  static const double codeRadius = 8;
  static const double maxBubbleWidthFraction = 0.80;

  // ---- General spacing scale (4pt grid) ----
  // Single source of truth for paddings/gaps. Prefer these over raw literals
  // so density can be tuned in one place.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Bottom inset so scrollable content clears a floating extended FAB.
  static const double fabSafeBottom = 88;

  /// Asymmetric corners for premium chat feel.
  static const BorderRadius userBubbleBorderRadius = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(18),
    bottomRight: Radius.circular(4),
  );
  static const BorderRadius assistantBubbleBorderRadius = BorderRadius.only(
    topLeft: Radius.circular(4),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(18),
    bottomRight: Radius.circular(18),
  );
}

/// Interaction sizing tokens.
abstract class AppSizes {
  /// Minimum touch target per WCAG 2.5.5 / Apple HIG (44x44 logical px).
  /// The painted control may look smaller; the *hit area* must meet this.
  static const double minTouchTarget = 44;
}

/// Icon sizing scale. Pairs with the 24px iconTheme default.
abstract class AppIconSize {
  static const double chip = 14; // glyph inside a chip/pill
  static const double inline = 16; // inline-with-text / dismiss
  static const double action = 20; // app-bar / row actions
  static const double normal = 24; // default icon
}
