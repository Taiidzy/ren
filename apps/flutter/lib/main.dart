// lib/src/main.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import 'package:ren/features/splash/presentation/splash_page.dart';
import 'package:ren/features/auth/presentation/auth_page.dart';

import 'package:ren/theme/themes.dart';

import 'package:ren/core/providers/background_settings.dart';
import 'package:ren/core/providers/notifications_settings.dart';
import 'package:ren/core/providers/theme_settings.dart';

import 'package:ren/core/e2ee/signal_protocol_client.dart';
import 'package:ren/features/auth/data/auth_api.dart';
import 'package:ren/features/auth/data/auth_repository.dart';
import 'package:ren/features/splash/data/spalsh_api.dart';
import 'package:ren/features/splash/data/spalsh_repository.dart';

import 'package:ren/features/chats/data/chats_api.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/presentation/chat_page.dart';

import 'package:ren/features/profile/data/profile_api.dart';
import 'package:ren/features/profile/data/profile_repository.dart';
import 'package:ren/core/providers/profile_store.dart';

import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/core/notifications/local_notifications.dart';
import 'package:ren/core/network/auth_session_interceptor.dart';
import 'package:ren/core/network/server_retry_interceptor.dart';
import 'package:ren/core/security/privacy_protection.dart';
import 'package:ren/shared/widgets/adaptive_page_route.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await SignalProtocolClient.instance.initialize();

      await LocalNotifications.instance.initialize();
      await PrivacyProtection.configure();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.dumpErrorToConsole(details);
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        FlutterError.dumpErrorToConsole(
          FlutterErrorDetails(exception: error, stack: stack),
        );
        return true;
      };

      final isolateErrorPort = ReceivePort();
      isolateErrorPort.listen((dynamic pair) {
        try {
          final List<dynamic> list = pair as List<dynamic>;
          final error = list[0];
          final stack = list[1] as StackTrace?;
          FlutterError.dumpErrorToConsole(
            FlutterErrorDetails(exception: error, stack: stack),
          );
        } catch (_) {
          debugPrint('Unparsable isolate error: $pair');
        }
      });
      Isolate.current.addErrorListener(isolateErrorPort.sendPort);

      runApp(const MyApp());
    },
    (Object error, StackTrace stack) {
      FlutterError.dumpErrorToConsole(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    LocalNotifications.instance.setOnOpenChat((chatId) async {
      // Ensure tree is ready
      for (var i = 0; i < 20; i++) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }

        final repo = Provider.of<ChatsRepository>(ctx, listen: false);
        final chats = await repo.fetchChats();
        final chat = chats.firstWhere(
          (c) => (int.tryParse(c.id) ?? 0) == chatId,
          orElse: () => throw Exception('chat not found'),
        );

        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ChatPage(chat: chat)),
        );
        return;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BackgroundSettings>(
          create: (_) => BackgroundSettings(),
        ),
        ChangeNotifierProvider<NotificationsSettings>(
          create: (_) => NotificationsSettings(),
        ),
        ChangeNotifierProvider<ThemeSettings>(create: (_) => ThemeSettings()),
        Provider<SignalProtocolClient>.value(
          value: SignalProtocolClient.instance,
        ),
        Provider<Dio>(
          create: (_) {
            final dio = Dio();
            dio.interceptors.add(ServerRetryInterceptor(dio));
            dio.interceptors.add(
              AuthSessionInterceptor(
                dio,
                onUnauthorized: () async {
                  final nav = rootNavigatorKey.currentState;
                  final ctx = rootNavigatorKey.currentContext;
                  if (nav == null || ctx == null) return;
                  nav.pushAndRemoveUntil(
                    adaptivePageRoute((_) => const AuthPage()),
                    (route) => false,
                  );
                },
              ),
            );
            return dio;
          },
        ),
        ProxyProvider<Dio, AuthApi>(update: (_, dio, __) => AuthApi(dio)),
        ProxyProvider<Dio, SplashApi>(update: (_, dio, __) => SplashApi(dio)),
        ProxyProvider<Dio, ChatsApi>(update: (_, dio, __) => ChatsApi(dio)),
        ProxyProvider<Dio, ProfileApi>(update: (_, dio, __) => ProfileApi(dio)),
        ProxyProvider2<AuthApi, SignalProtocolClient, AuthRepository>(
          update: (_, api, signal, __) => AuthRepository(api, signal),
        ),
        ProxyProvider<SplashApi, SplashRepository>(
          update: (_, api, __) => SplashRepository(api),
        ),
        ProxyProvider2<ChatsApi, SignalProtocolClient, ChatsRepository>(
          update: (_, api, signal, prev) =>
              prev ?? ChatsRepository(api, signal),
        ),

        Provider<RealtimeClient>(create: (_) => RealtimeClient()),

        ProxyProvider<ProfileApi, ProfileRepository>(
          update: (_, api, __) => ProfileRepository(api),
        ),
        ChangeNotifierProxyProvider<ProfileRepository, ProfileStore>(
          create: (context) => ProfileStore(context.read<ProfileRepository>()),
          update: (_, repo, store) {
            store ??= ProfileStore(repo);
            store.setRepo(repo);
            return store;
          },
        ),
      ],
      child: Consumer2<ThemeSettings, BackgroundSettings>(
        builder: (context, settings, backgroundSettings, _) {
          final lightAutoSeed =
              settings.colorScheme == AppColorSchemePreset.auto
              ? backgroundSettings.autoSeedLight
              : null;
          final darkAutoSeed = settings.colorScheme == AppColorSchemePreset.auto
              ? backgroundSettings.autoSeedDark
              : null;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            theme: AppTheme.lightThemeFor(
              settings.colorScheme,
              autoSeedColor: lightAutoSeed,
            ),
            darkTheme: AppTheme.darkThemeFor(
              settings.colorScheme,
              autoSeedColor: darkAutoSeed,
            ),
            themeMode: settings.themeMode,
            home: const SplashPage(),
          );
        },
      ),
    );
  }
}
