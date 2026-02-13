import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:ren/features/profile/data/profile_repository.dart';
import 'package:ren/features/profile/domain/security_session.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;
  List<SecuritySession> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = context.read<ProfileRepository>();
      final sessions = await repo.sessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _terminateSession(SecuritySession session) async {
    if (_isBusy) return;

    final shouldDelete = await GlassOverlays.showGlassDialog<bool>(
      context,
      builder: (dialogContext) {
        return _ConfirmDialog(
          title: 'Завершить сессию?',
          text:
              'Устройство "${session.deviceName}" выйдет из аккаунта и потребует повторный вход.',
          actionLabel: 'Завершить',
          onConfirm: () => Navigator.of(dialogContext).pop(true),
        );
      },
    );

    if (shouldDelete != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await context.read<ProfileRepository>().deleteSession(session.id);
      await _loadSessions();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _terminateOtherSessions() async {
    if (_isBusy) return;

    final shouldDelete = await GlassOverlays.showGlassDialog<bool>(
      context,
      builder: (dialogContext) {
        return _ConfirmDialog(
          title: 'Выйти из других устройств?',
          text: 'Все остальные активные сессии будут завершены.',
          actionLabel: 'Выйти везде',
          onConfirm: () => Navigator.of(dialogContext).pop(true),
        );
      },
    );

    if (shouldDelete != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await context.read<ProfileRepository>().deleteOtherSessions();
      await _loadSessions();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.replaceFirst('Exception: ', ''))),
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm.$yyyy $hh:$min';
  }

  List<List<dynamic>> _deviceIcon(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('android')) {
      return HugeIcons.strokeRoundedAndroid;
    }

    if (lower.contains('iphone') ||
        lower.contains('ios') ||
        lower.contains('mobile') ||
        lower.contains('phone')) {
      return HugeIcons.strokeRoundedSmartPhone01;
    }

    if (lower.contains('ipad') || lower.contains('tablet')) {
      return HugeIcons.strokeRoundedSmartPhoneLandscape;
    }

    if (lower.contains('mac') || lower.contains('apple')) {
      return HugeIcons.strokeRoundedApple;
    }

    if (lower.contains('windows') ||
        lower.contains('linux') ||
        lower.contains('desktop') ||
        lower.contains('computer')) {
      return HugeIcons.strokeRoundedComputer;
    }

    if (lower.contains('laptop')) {
      return HugeIcons.strokeRoundedLaptop;
    }

    return HugeIcons.strokeRoundedDeviceAccess;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return AppBackground(
      imageOpacity: 1,
      imageBlurSigma: 0,
      imageFit: BoxFit.cover,
      animate: true,
      animationDuration: const Duration(seconds: 20),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Безопасность'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: [
                GlassSurface(
                  borderRadius: 26,
                  blurSigma: 16,
                  width: double.infinity,
                  borderColor: baseInk.withOpacity(isDark ? 0.24 : 0.14),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    children: [
                      GlassSurface(
                        borderRadius: 18,
                        blurSigma: 14,
                        width: 94,
                        height: 110,
                        borderColor: baseInk.withOpacity(isDark ? 0.22 : 0.12),
                        child: Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedShield01,
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.92,
                            ),
                            size: 46,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Щит аккаунта',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Управляй активными входами и закрывай лишние устройства',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.74),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassSurface(
                        borderRadius: 14,
                        blurSigma: 12,
                        width: double.infinity,
                        borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.12),
                        onTap: _isBusy ? null : _terminateOtherSessions,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedShieldKey,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.9,
                              ),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Выйти из всех других устройств',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadSessions,
                    child: _buildList(theme, isDark, baseInk),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, bool isDark, Color baseInk) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 40),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!.replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      );
    }

    if (_sessions.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 40),
          Center(
            child: Text(
              'Активных сессий не найдено',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = _sessions[i];
        return GlassSurface(
          borderRadius: 16,
          blurSigma: 12,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HugeIcon(
                    icon: _deviceIcon(s.deviceName),
                    color: theme.colorScheme.onSurface.withOpacity(0.9),
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.deviceName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (s.isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Текущее',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('IP: ${s.ipAddress}', style: theme.textTheme.bodySmall),
              Text('Город: ${s.city}', style: theme.textTheme.bodySmall),
              Text('Версия: ${s.appVersion}', style: theme.textTheme.bodySmall),
              Text(
                'Вход: ${_formatDateTime(s.loginAt)}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Последняя активность: ${_formatDateTime(s.lastSeenAt)}',
                style: theme.textTheme.bodySmall,
              ),
              if (!s.isCurrent) ...[
                const SizedBox(height: 10),
                GlassSurface(
                  borderRadius: 12,
                  blurSigma: 10,
                  height: 40,
                  color: const Color(0xFF991B1B).withOpacity(0.55),
                  borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.12),
                  onTap: _isBusy ? null : () => _terminateSession(s),
                  child: Center(
                    child: Text(
                      'Завершить сессию',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: GlassSurface(
        borderRadius: 22,
        blurSigma: 14,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        borderColor: baseInk.withOpacity(isDark ? 0.22 : 0.12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.75),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GlassSurface(
                    borderRadius: 14,
                    blurSigma: 12,
                    height: 44,
                    borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
                    onTap: () => Navigator.of(context).pop(false),
                    child: Center(
                      child: Text(
                        'Отмена',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassSurface(
                    borderRadius: 14,
                    blurSigma: 12,
                    height: 44,
                    color: const Color(0xFF991B1B).withOpacity(0.55),
                    borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
                    onTap: onConfirm,
                    child: Center(
                      child: Text(
                        actionLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
