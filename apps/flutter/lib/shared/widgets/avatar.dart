import 'package:flutter/material.dart';

class RenAvatar extends StatelessWidget {
  final String url;
  final String name;
  final bool isOnline;
  final double size;
  final double onlineDotSize;
  final BorderRadius? borderRadius;

  const RenAvatar({
    super.key,
    required this.url,
    required this.name,
    required this.isOnline,
    this.size = 44,
    this.onlineDotSize = 12,
    this.borderRadius,
  });

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p.characters.first).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(size / 2);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: br,
            child: url.isEmpty
                ? Container(
                    width: size,
                    height: size,
                    color: Theme.of(context).colorScheme.surface,
                    child: Center(
                      child: Text(
                        _initials(name),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: size * 0.34,
                        ),
                      ),
                    ),
                  )
                : Image.network(
                    url,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) {
                      return Container(
                        width: size,
                        height: size,
                        color: Theme.of(context).colorScheme.surface,
                        child: Center(
                          child: Text(
                            _initials(name),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: size * 0.34,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: onlineDotSize,
              height: onlineDotSize,
              decoration: BoxDecoration(
                color: isOnline ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withOpacity(0.25), width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
