// lib/src/main.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import 'package:ren/features/splash/presentation/splash_page.dart';

import 'package:ren/theme/themes.dart';

import 'package:ren/core/providers/background_settings.dart';
import 'package:ren/core/providers/theme_settings.dart';

import 'package:ren/core/sdk/ren_sdk.dart';
import 'package:ren/features/auth/data/auth_api.dart';
import 'package:ren/features/auth/data/auth_repository.dart';
import 'package:ren/features/splash/data/spalsh_api.dart';
import 'package:ren/features/splash/data/spalsh_repository.dart';

import 'package:ren/features/chats/data/chats_api.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/presentation/chat_page.dart';

import 'package:ren/features/profile/data/profile_api.dart';
import 'package:ren/features/profile/data/profile_repository.dart';
import 'package:ren/features/profile/presentation/profile_store.dart';

import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/core/notifications/local_notifications.dart';
import 'package:ren/core/network/auth_session_interceptor.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await RenSdk.instance.initialize();

      await LocalNotifications.instance.initialize();

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BackgroundSettings>(
          create: (_) => BackgroundSettings(),
        ),
        ChangeNotifierProvider<ThemeSettings>(create: (_) => ThemeSettings()),
        Provider<RenSdk>.value(value: RenSdk.instance),
        Provider<Dio>(
          create: (_) {
            final dio = Dio();
            dio.interceptors.add(AuthSessionInterceptor(dio));
            return dio;
          },
        ),
        ProxyProvider<Dio, AuthApi>(update: (_, dio, __) => AuthApi(dio)),
        ProxyProvider<Dio, SplashApi>(update: (_, dio, __) => SplashApi(dio)),
        ProxyProvider<Dio, ChatsApi>(update: (_, dio, __) => ChatsApi(dio)),
        ProxyProvider<Dio, ProfileApi>(update: (_, dio, __) => ProfileApi(dio)),
        ProxyProvider2<AuthApi, RenSdk, AuthRepository>(
          update: (_, api, sdk, __) => AuthRepository(api, sdk),
        ),
        ProxyProvider<SplashApi, SplashRepository>(
          update: (_, api, __) => SplashRepository(api),
        ),
        ProxyProvider2<ChatsApi, RenSdk, ChatsRepository>(
          update: (_, api, sdk, __) => ChatsRepository(api, sdk),
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
      child: Consumer<ThemeSettings>(
        builder: (context, settings, _) {
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

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            theme: AppTheme.lightThemeFor(settings.colorScheme),
            darkTheme: AppTheme.darkThemeFor(settings.colorScheme),
            themeMode: settings.themeMode,
            home: const SplashPage(),
          );
        },
      ),
    );
  }
}
