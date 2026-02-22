import 'package:flutter/material.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class MatteToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const MatteToggle({
    required this.value,
    required this.onChanged,
    required this.label,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        GestureDetector(
          onTap: () => onChanged(!value),
          behavior: HitTestBehavior.translucent,
          child: GlassBlur(
            borderRadius: 18,
            blurSigma: 10,
            child: SizedBox(
              height: 44,
              width: 60,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  height: 32,
                  width: 60,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              Colors.white.withOpacity(0.08),
                              Colors.white.withOpacity(0.02),
                            ]
                          : [
                              const Color(0xFFFFFFFF).withOpacity(0.35),
                              const Color(0xFFFFFFFF).withOpacity(0.15),
                            ],
                    ),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.18)
                          : Colors.black.withOpacity(0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? Colors.black : Colors.grey.shade400)
                            .withOpacity(0.20),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 220),
                        alignment: value
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: value
                                  ? [
                                      const Color(0xFF6EE7F9).withOpacity(0.9),
                                      const Color(0xFF7C3AED).withOpacity(0.9),
                                    ]
                                  : [
                                      Colors.white.withOpacity(0.75),
                                      Colors.white.withOpacity(0.55),
                                    ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (value
                                            ? const Color(0xFF7C3AED)
                                            : Colors.black)
                                        .withOpacity(0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.25)
                                  : Colors.black.withOpacity(0.06),
                              width: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
