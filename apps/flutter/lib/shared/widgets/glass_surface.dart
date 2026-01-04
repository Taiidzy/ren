import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ren/theme/themes.dart';

class GlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final BorderRadiusGeometry? borderRadiusGeometry;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  final VoidCallback? onTap;
  final Color? splashColor;
  final Color? highlightColor;

  final Gradient? gradient;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.borderRadiusGeometry,
    this.blurSigma = 12,
    this.padding,
    this.width,
    this.height,
    this.onTap,
    this.splashColor,
    this.highlightColor,
    this.gradient,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    final effectiveBorderRadius =
        borderRadiusGeometry ?? BorderRadius.circular(borderRadius);

    final effectiveGradient =
        gradient ?? (isDark ? AppGradients.glassDark : AppGradients.glassLight);

    final effectiveBorderColor =
        borderColor ?? baseInk.withOpacity(isDark ? 0.18 : 0.10);

    final decoration = BoxDecoration(
      borderRadius: effectiveBorderRadius,
      gradient: color == null ? effectiveGradient : null,
      color: color,
      border: Border.all(color: effectiveBorderColor, width: borderWidth),
      boxShadow: boxShadow,
    );

    Widget body = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap != null) {
      final BorderRadius inkBorderRadius =
          effectiveBorderRadius is BorderRadius
              ? effectiveBorderRadius
              : BorderRadius.circular(borderRadius);
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: inkBorderRadius,
          onTap: onTap,
          splashColor: splashColor,
          highlightColor: highlightColor,
          child: body,
        ),
      );
    }

    return ClipRRect(
      borderRadius: effectiveBorderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: body,
      ),
    );
  }
}

class GlassBlur extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final BorderRadiusGeometry? borderRadiusGeometry;
  final double blurSigma;

  const GlassBlur({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.borderRadiusGeometry,
    this.blurSigma = 12,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius =
        borderRadiusGeometry ?? BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: effectiveBorderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: child,
      ),
    );
  }
}

class GlassAppBarBackground extends StatelessWidget {
  final double blurSigma;
  final BorderSide? bottomBorder;

  const GlassAppBarBackground({
    super.key,
    this.blurSigma = 14,
    this.bottomBorder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    final effectiveBottomBorder = bottomBorder ??
        BorderSide(
          color: baseInk.withOpacity(isDark ? 0.18 : 0.10),
          width: 1,
        );

    final gradient = isDark ? AppGradients.glassDark : AppGradients.glassLight;

    return GlassBlur(
      borderRadius: 0,
      blurSigma: blurSigma,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          border: Border(bottom: effectiveBottomBorder),
        ),
      ),
    );
  }
}
