import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  return MaterialPageRoute<T>(
    builder: builder,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
  );
}
