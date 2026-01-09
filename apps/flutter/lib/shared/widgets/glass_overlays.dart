import 'package:flutter/material.dart';

class GlassOverlays {
  static Future<T?> showGlassBottomSheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    Color backgroundColor = Colors.transparent,
    Color? barrierColor,
    bool useSafeArea = false,
    bool enableDrag = true,
    bool isDismissible = true,
    ShapeBorder? shape,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor ?? Colors.black.withOpacity(0.35),
      useSafeArea: useSafeArea,
      enableDrag: enableDrag,
      isDismissible: isDismissible,
      shape: shape,
    );
  }

  static Future<T?> showGlassDialog<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    Color? barrierColor,
    bool barrierDismissible = true,
    String? barrierLabel,
    bool useSafeArea = true,
    RouteSettings? routeSettings,
  }) {
    return showDialog<T>(
      context: context,
      builder: builder,
      barrierColor: barrierColor ?? Colors.black.withOpacity(0.35),
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
    );
  }
}
