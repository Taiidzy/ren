import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ren/features/auth/presentation/auth_page.dart';
import 'package:ren/features/chats/presentation/chats_page.dart';
import 'package:ren/core/realtime/realtime_client.dart';

import 'package:ren/shared/widgets/animated_gradient.dart';
import 'package:ren/shared/widgets/ren_logo.dart';
import 'package:ren/shared/widgets/adaptive_page_route.dart';

import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/features/auth/data/auth_repository.dart';
import 'package:ren/features/splash/data/spalsh_repository.dart';
import 'package:ren/features/splash/data/spalsh_api.dart';
import 'package:ren/core/e2ee/signal_protocol_client.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late AnimationController _backgroundController;
  late AnimationController _solarSystemController;
  late AnimationController _fadeController;

  late Animation<double> _backgroundAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Контроллер для анимации фона
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();

    // Контроллер для анимации солнечной системы
    _solarSystemController = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    )..repeat();

    // Контроллер для fade-in анимации
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _backgroundAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _backgroundController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    // Запускаем fade-in анимацию
    _fadeController.forward();

    // Запускаем инициализацию SDK
    _initSDK();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _solarSystemController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _initSDK() async {
    try {
      final minSplashDelay = Future.delayed(const Duration(seconds: 1));
      await minSplashDelay;

      // small delay to let animation finish nicely
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) {
        return;
      }

      // Используем Future.microtask для гарантии, что context доступен
      Future.microtask(() {
        _initApp();
      });
    } catch (e) {
      if (!mounted) return;
    }
  }

  void _initApp() async {
    // Сохраняем контекст до начала асинхронных операций
    final currentContext = context;
    SplashRepository? repo;
    final storedUserIdRaw = await SecureStorage.readKey(Keys.userId);
    final storedUserId = int.tryParse(storedUserIdRaw ?? '') ?? 0;

    Future<void> ensureSignalReady([int? fallbackUserId]) async {
      final userId = fallbackUserId ?? storedUserId;
      if (userId <= 0) return;
      try {
        final bundle = await SignalProtocolClient.instance.initUser(
          userId: userId,
        );
        if (bundle.isNotEmpty) {
          await currentContext.read<AuthRepository>().api.updateSignalBundle(
            bundle,
          );
        }
      } catch (_) {
        // Keep splash resilient: auth/network flow should proceed even if Signal init fails.
      }
    }

    Future<void> goAuth() async {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(adaptivePageRoute((_) => const AuthPage()));
      });
    }

    Future<void> goChats() async {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(adaptivePageRoute((_) => const ChatsPage()));
      });
    }

    try {
      final token = await SecureStorage.readKey(Keys.token);

      if (token == null || token.isEmpty) {
        await goAuth();
        return;
      }

      // Получаем репозиторий с использованием сохраненного контекста
      try {
        repo = currentContext.read<SplashRepository>();
      } catch (e) {
        // Если провайдер недоступен, но токен есть, даём оффлайн-вход в приложение.
        await goChats();
        return;
      }

      final userJson = await repo.checkAuth(token);
      final hasUser = userJson['id'] != null;

      if (hasUser) {
        final verifiedUserId = (userJson['id'] is int)
            ? userJson['id'] as int
            : int.tryParse('${userJson['id']}') ?? storedUserId;
        await ensureSignalReady(verifiedUserId);
        unawaited(currentContext.read<RealtimeClient>().connect());
        await goChats();
      } else {
        await goAuth();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // Только невалидная сессия должна принудительно разлогинивать.
        await SecureStorage.deleteAllKeys();
        await goAuth();
        return;
      }
      // Сеть/сервер недоступны: при существующем токене пускаем в приложение оффлайн.
      await ensureSignalReady();
      unawaited(currentContext.read<RealtimeClient>().connect());
      await goChats();
    } catch (e) {
      // Любая не-401 ошибка и наличие токена -> главный экран.
      await ensureSignalReady();
      unawaited(currentContext.read<RealtimeClient>().connect());
      await goChats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_backgroundAnimation, _fadeAnimation]),
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              // Используем утилитный класс для создания градиента
              gradient: AnimatedGradientUtils.buildAnimatedGradient(
                _backgroundAnimation.value,
                isDarkMode,
                primaryColor: Theme.of(context).colorScheme.primary,
                secondaryColor: Theme.of(context).colorScheme.secondary,
              ),
            ),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Используем новый виджет логотипа
                  RenLogo(
                    size: 200,
                    controller: _solarSystemController,
                    fontSize: 32,
                    strokeWidth: 1.5,
                    dotRadius: 3.5,
                  ),

                  const SizedBox(height: 40),

                  // Анимированный прогресс-бар
                  Container(
                    width: 200,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.1),
                    ),
                    child: Stack(
                      children: [
                        // Движущаяся полоска
                        AnimatedBuilder(
                          animation: _backgroundAnimation,
                          builder: (context, child) {
                            final position =
                                math.sin(
                                      _backgroundAnimation.value * 4 * math.pi,
                                    ) *
                                    0.5 +
                                0.5;

                            return Positioned(
                              left: position * 140, // 200 - 60 (ширина полоски)
                              child: Container(
                                width: 60,
                                height: 4,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  gradient: LinearGradient(
                                    colors: isDarkMode
                                        ? [
                                            Colors.white.withOpacity(0.2),
                                            Colors.white.withOpacity(0.8),
                                            Colors.white.withOpacity(0.2),
                                          ]
                                        : [
                                            const Color(
                                              0xFF1A1B2E,
                                            ).withOpacity(0.2),
                                            const Color(
                                              0xFF1A1B2E,
                                            ).withOpacity(0.8),
                                            const Color(
                                              0xFF1A1B2E,
                                            ).withOpacity(0.2),
                                          ],
                                    stops: const [0.0, 0.5, 1.0],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
