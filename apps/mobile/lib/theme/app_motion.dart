import 'package:flutter/widgets.dart';

/// Motion tokens — deliberately tiny and restrained.
///
/// Transitions only, all <= 240ms with ONE easing family. Perceptual
/// "heartbeat" loops (caret/pulse/glow) keep their own longer durations and are
/// NOT part of this transition scale; they are instead gated by [reducedMotion].
abstract class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration emphasized = Duration(milliseconds: 240);
  static const Curve curve = Curves.easeOutCubic;
}

/// True when the OS requests reduced motion (Settings > Accessibility).
///
/// The single chokepoint for motion accessibility: gate looping animations on
/// `!reducedMotion(context)` and collapse transition durations to zero.
bool reducedMotion(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  return mq?.disableAnimations == true || mq?.accessibleNavigation == true;
}

/// A transition duration that respects reduced-motion: returns [Duration.zero]
/// when reduced motion is on, otherwise [d].
Duration motionDuration(BuildContext context, Duration d) =>
    reducedMotion(context) ? Duration.zero : d;
