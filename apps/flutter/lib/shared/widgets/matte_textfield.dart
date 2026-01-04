import 'package:flutter/material.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

import 'package:hugeicons/hugeicons.dart';

class MatteTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String hintText;
  final bool isPassword;
  final TextInputType keyboardType;
  final HugeIcon? prefixIcon;
  final Widget? suffixIcon;

  const MatteTextField({
    super.key,
    this.controller,
    required this.hintText,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  State<MatteTextField> createState() => _MatteTextFieldState();
}

class _MatteTextFieldState extends State<MatteTextField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final baseInk = isDark ? Colors.white : Colors.black;
    final double? prefixSize = widget.prefixIcon?.size;
    return GlassSurface(
      borderRadius: 16,
      blurSigma: 12,
      height: 56,
      borderColor: baseInk.withOpacity(isDark ? 0.25 : 0.15),
      child: TextField(
        controller: widget.controller,
        obscureText: _obscure,
        keyboardType: widget.keyboardType,
        style: TextStyle(color: onSurface, fontSize: 16),
        cursorColor: theme.colorScheme.primary,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: onSurface.withOpacity(isDark ? 0.6 : 0.5),
          ),
          border: InputBorder.none,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          prefixIcon: widget.prefixIcon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: SizedBox(
                    width: prefixSize,
                    height: prefixSize,
                    child: IconTheme(
                      data: IconThemeData(
                        color: onSurface.withOpacity(isDark ? 0.7 : 0.6),
                        size: prefixSize,
                      ),
                      child: widget.prefixIcon!,
                    ),
                  ),
                ),
          suffixIcon: widget.isPassword
              ? IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: onSurface.withOpacity(isDark ? 0.7 : 0.6),
                  ),
                  onPressed: () {
                    setState(() {
                      _obscure = !_obscure;
                    });
                  },
                )
              : widget.suffixIcon,
        ),
      ),
    );
  }
}
