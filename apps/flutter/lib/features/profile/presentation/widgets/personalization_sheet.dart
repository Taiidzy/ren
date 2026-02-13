import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:ren/core/providers/background_settings.dart';
import 'package:ren/core/providers/theme_settings.dart';
import 'package:ren/shared/widgets/animated_gradient.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class PersonalizationSheet {
  static Future<void> show(BuildContext context) async {
    await GlassOverlays.showGlassBottomSheet<void>(
      context,
      builder: (context) {
        return const _SheetBody();
      },
    );
  }

}

class _SegmentedItem<T> {
  final T value;
  final String label;

  const _SegmentedItem({required this.value, required this.label});
}

class _SegmentedRow<T> extends StatelessWidget {
  final T value;
  final List<_SegmentedItem<T>> items;
  final ValueChanged<T> onChanged;

  const _SegmentedRow({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          _ChoiceChip(
            label: item.label,
            selected: item.value == value,
            onTap: () => onChanged(item.value),
          ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return GlassSurface(
      borderRadius: 14,
      blurSigma: 12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: selected
          ? theme.colorScheme.primary.withOpacity(isDark ? 0.22 : 0.18)
          : null,
      borderColor: selected
          ? theme.colorScheme.primary
          : baseInk.withOpacity(isDark ? 0.18 : 0.10),
      onTap: onTap,
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<BackgroundSettings>();
    final themeSettings = context.watch<ThemeSettings>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return GlassSurface(
          blurSigma: 16,
          borderRadiusGeometry: const BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
          ),
          borderColor: baseInk.withOpacity(isDark ? 0.22 : 0.12),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Персонализация',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      settings.setBackgroundImage(null);
                      settings.setImageBlurSigma(0);
                      settings.setImageOpacity(1);
                    },
                    child: Text(
                      'Сбросить',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionTitle(title: 'Тема'),
              const SizedBox(height: 10),
              _SegmentedRow<ThemeMode>(
                value: themeSettings.themeMode,
                items: const [
                  _SegmentedItem(value: ThemeMode.system, label: 'Система'),
                  _SegmentedItem(value: ThemeMode.light, label: 'Светлая'),
                  _SegmentedItem(value: ThemeMode.dark, label: 'Тёмная'),
                ],
                onChanged: (m) => themeSettings.setThemeMode(m),
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Цветовая схема'),
              const SizedBox(height: 10),
              _SegmentedRow<AppColorSchemePreset>(
                value: themeSettings.colorScheme,
                items: const [
                  _SegmentedItem(
                    value: AppColorSchemePreset.indigo,
                    label: 'Indigo',
                  ),
                  _SegmentedItem(
                    value: AppColorSchemePreset.emerald,
                    label: 'Emerald',
                  ),
                  _SegmentedItem(
                    value: AppColorSchemePreset.rose,
                    label: 'Rose',
                  ),
                  _SegmentedItem(
                    value: AppColorSchemePreset.orange,
                    label: 'Orange',
                  ),
                  _SegmentedItem(
                    value: AppColorSchemePreset.cyan,
                    label: 'Cyan',
                  ),
                ],
                onChanged: (p) => themeSettings.setColorScheme(p),
              ),
              const SizedBox(height: 18),
              _SectionTitle(title: 'Фон'),
              const SizedBox(height: 10),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: BackgroundPresets.wallpaperUrls.length +
                      settings.galleryHistoryPaths.length +
                      2,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = settings.backgroundImage == null;
                      return _WallpaperTile(
                        label: 'Градиент',
                        isSelected: isSelected,
                        onTap: () => settings.setBackgroundImage(null),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: AnimatedGradientUtils.buildStaticGradient(
                              isDark,
                            ),
                          ),
                        ),
                      );
                    }

                    if (index == 1) {
                      final isSelected = settings.backgroundImage is FileImage;
                      return _WallpaperTile(
                        label: 'Галерея',
                        isSelected: isSelected,
                        onTap: () async {
                          final picker = ImagePicker();
                          final file = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 90,
                          );
                          if (file == null) return;
                          if (!context.mounted) return;
                          await settings.setBackgroundFromPickedFilePath(
                            file.path,
                          );
                        },
                        child: isSelected
                            ? Image(
                                image: settings.backgroundImage!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(isDark ? 0.10 : 0.08),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.photo_library_outlined,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.85),
                                  ),
                                ),
                              ),
                      );
                    }

                    final historyIndex = index - 2;
                    if (historyIndex < settings.galleryHistoryPaths.length) {
                      final path = settings.galleryHistoryPaths[historyIndex];
                      final isSelected = settings.currentFilePath == path;
                      return _WallpaperTile(
                        label: ' ',
                        isSelected: isSelected,
                        onTap: () => settings.setBackgroundFromFilePath(path),
                        child: Image.file(File(path), fit: BoxFit.cover),
                      );
                    }

                    final urlIndex =
                        index - 2 - settings.galleryHistoryPaths.length;
                    final url = BackgroundPresets.wallpaperUrls[urlIndex];
                    final isSelected =
                        (settings.backgroundImage is NetworkImage) &&
                            (settings.backgroundImage as NetworkImage).url ==
                                url;
                    return _WallpaperTile(
                      label: ' ',
                      isSelected: isSelected,
                      onTap: () => settings.setBackgroundFromUrl(url),
                      child: Image.network(url, fit: BoxFit.cover),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle(title: 'Блюр картинки'),
              const SizedBox(height: 8),
              _SliderRow(
                value: settings.imageBlurSigma,
                min: 0,
                max: 20,
                onChanged: settings.setImageBlurSigma,
                labelFormatter: (v) => v.toStringAsFixed(0),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.onSurface
                        .withOpacity(isDark ? 0.15 : 0.12),
                    foregroundColor: theme.colorScheme.onSurface,
                    elevation: 0,
                  ),
                  child: const Text('Готово'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  final Widget child;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  const _WallpaperTile({
    required this.child,
    required this.label,
    required this.onTap,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : baseInk.withOpacity(isDark ? 0.22 : 0.12),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (isSelected)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (label.trim().isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(blurRadius: 10, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double) labelFormatter;

  const _SliderRow({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.labelFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            labelFormatter(value),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.75),
            ),
          ),
        ),
      ],
    );
  }
}
