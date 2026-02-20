import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class PerformanceTuning {
  const PerformanceTuning._();

  static bool preferReducedEffectsForPlatform() {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  static bool preferReducedEffects(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final osReduceMotion = media?.disableAnimations ?? false;
    final isAndroid = preferReducedEffectsForPlatform();
    return osReduceMotion || isAndroid;
  }

  static bool shouldAnimateBackground(BuildContext context, bool requested) {
    if (!requested) return false;
    return !preferReducedEffects(context);
  }

  static double effectiveBlurSigma(BuildContext context, double sigma) {
    if (sigma <= 0) return 0;
    if (!preferReducedEffects(context)) return sigma;
    return sigma * 0.35;
  }
}
