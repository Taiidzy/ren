import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

PageRoute<T> adaptivePageRoute<T>(
  WidgetBuilder builder, {
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  final platform = defaultTargetPlatform;
  final bool isCupertino = !kIsWeb &&
      (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS);

  if (isCupertino) {
    return CupertinoPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }

  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) {
      return builder(context);
    },
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
      final slide = Tween<Offset>(
        begin: const Offset(0.02, 0.03),
        end: Offset.zero,
      ).animate(curved);
      final scale = Tween<double>(begin: 0.985, end: 1.0).animate(curved);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(
            scale: scale,
            child: child,
          ),
        ),
      );
    },
  );
}
