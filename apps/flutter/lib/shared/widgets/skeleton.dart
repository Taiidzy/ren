import 'package:flutter/material.dart';
import 'package:ren/core/performance/performance_tuning.dart';

class RenSkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Duration duration;

  const RenSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    required this.radius,
    this.duration = const Duration(milliseconds: 1100),
  });

  @override
  State<RenSkeletonBox> createState() => _RenSkeletonBoxState();
}

class _RenSkeletonBoxState extends State<RenSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = !PerformanceTuning.preferReducedEffects(context);
    if (shouldAnimate == _isAnimating) return;
    _isAnimating = shouldAnimate;
    if (_isAnimating) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0.5;
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
    final base = isDark ? Colors.white : Colors.black;

    final c1 = base.withOpacity(isDark ? 0.10 : 0.06);
    final c2 = base.withOpacity(isDark ? 0.18 : 0.10);

    if (!_isAnimating) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Container(width: widget.width, height: widget.height, color: c1),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final begin = Alignment(-1.0 - 2.0 * t, 0);
        final end = Alignment(1.0 - 2.0 * t, 0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: begin,
                end: end,
                colors: [c1, c2, c1],
                stops: const [0.2, 0.5, 0.8],
              ),
            ),
          ),
        );
      },
    );
  }
}
