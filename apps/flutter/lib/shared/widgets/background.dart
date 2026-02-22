import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ren/shared/widgets/animated_gradient.dart';
import 'package:ren/core/providers/background_settings.dart';
import 'package:ren/core/performance/performance_tuning.dart';

class AppBackground extends StatefulWidget {
  final Widget child;
  final ImageProvider? backgroundImage;
  final double imageOpacity;
  final BoxFit imageFit;
  final Alignment imageAlignment;
  final double imageBlurSigma;
  final bool showGradient;
  final bool animate;
  final Duration animationDuration;

  const AppBackground({
    super.key,
    required this.child,
    this.backgroundImage,
    this.imageOpacity = 1.0,
    this.imageFit = BoxFit.cover,
    this.imageAlignment = Alignment.center,
    this.imageBlurSigma = 0.0,
    this.showGradient = true,
    this.animate = true,
    this.animationDuration = const Duration(seconds: 20),
  });

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.animationDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _controller.reverse();
            } else if (status == AnimationStatus.dismissed) {
              _controller.forward();
            }
          });
    final shouldAnimate =
        widget.animate && !PerformanceTuning.preferReducedEffectsForPlatform();
    if (shouldAnimate) {
      _controller.forward();
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void didUpdateWidget(covariant AppBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate ||
        oldWidget.animationDuration != widget.animationDuration) {
      if (oldWidget.animationDuration != widget.animationDuration) {
        _controller.duration = widget.animationDuration;
      }
      final shouldAnimate =
          widget.animate &&
          !PerformanceTuning.preferReducedEffectsForPlatform();
      if (shouldAnimate && !_controller.isAnimating) {
        if (_controller.status == AnimationStatus.dismissed) {
          _controller.forward();
        } else {
          _controller.repeat(reverse: true);
        }
      } else if (!shouldAnimate && _controller.isAnimating) {
        _controller.stop();
        _controller.value = 0.5;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shouldAnimate = PerformanceTuning.shouldAnimateBackground(
      context,
      widget.animate,
    );

    BackgroundSettings? settings;
    try {
      settings = context.watch<BackgroundSettings>();
    } catch (_) {
      settings = null;
    }

    final effectiveBackgroundImage =
        settings?.backgroundImage ?? widget.backgroundImage;
    final effectiveImageOpacity = settings?.imageOpacity ?? widget.imageOpacity;
    final effectiveImageBlurSigma = PerformanceTuning.effectiveBlurSigma(
      context,
      settings?.imageBlurSigma ?? widget.imageBlurSigma,
    );
    final effectiveShowGradient = effectiveBackgroundImage == null;
    final effectiveGradientOpacity = 1.0;

    Widget gradientLayer(double t) {
      final gradient = shouldAnimate
          ? AnimatedGradientUtils.buildAnimatedGradient(
              t,
              isDark,
              primaryColor: theme.colorScheme.primary,
              secondaryColor: theme.colorScheme.secondary,
            )
          : AnimatedGradientUtils.buildStaticGradient(
              isDark,
              primaryColor: theme.colorScheme.primary,
              secondaryColor: theme.colorScheme.secondary,
            );
      return IgnorePointer(
        child: Opacity(
          opacity: effectiveShowGradient ? effectiveGradientOpacity : 0.0,
          child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
        ),
      );
    }

    Widget? imageLayer() {
      if (effectiveBackgroundImage == null) return null;
      Widget img = Image(
        image: effectiveBackgroundImage,
        fit: widget.imageFit,
        alignment: widget.imageAlignment,
      );
      if (effectiveImageBlurSigma > 0) {
        img = ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: effectiveImageBlurSigma,
            sigmaY: effectiveImageBlurSigma,
          ),
          child: img,
        );
      }
      return IgnorePointer(
        child: Opacity(opacity: effectiveImageOpacity, child: img),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (effectiveBackgroundImage != null)
          Positioned.fill(child: imageLayer()!),
        if (shouldAnimate)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => gradientLayer(_controller.value),
            ),
          )
        else
          Positioned.fill(child: gradientLayer(0.5)),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
