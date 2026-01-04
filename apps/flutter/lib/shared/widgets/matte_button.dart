import 'package:flutter/material.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class MatteButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final double width;
  final double height;
  final double borderRadius;

  const MatteButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.width = double.infinity,
    this.height = 56,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final baseInk = isDark ? Colors.white : Colors.black;
    return SizedBox(
      width: width,
      height: height,
      child: GlassSurface(
        borderRadius: borderRadius,
        blurSigma: 12,
        borderColor: baseInk.withOpacity(isDark ? 0.25 : 0.12),
        splashColor: baseInk.withOpacity(isDark ? 0.2 : 0.12),
        highlightColor: baseInk.withOpacity(isDark ? 0.12 : 0.08),
        onTap: onPressed,
        child: Center(
          child: Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
