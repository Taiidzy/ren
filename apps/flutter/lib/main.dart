// lib/src/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import 'package:ren/features/splash/presentation/splash_page.dart';

import 'package:ren/theme/themes.dart';

import 'package:ren/core/providers/background_settings.dart';

import 'package:ren/core/sdk/ren_sdk.dart';
import 'package:ren/features/auth/data/auth_api.dart';
import 'package:ren/features/auth/data/auth_repository.dart';
import 'package:ren/features/splash/data/spalsh_api.dart';
import 'package:ren/features/splash/data/spalsh_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RenSdk.instance.initialize();
  runApp(const MyApp());
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
        Provider<RenSdk>.value(value: RenSdk.instance),
        Provider<Dio>(create: (_) => Dio()),
        ProxyProvider<Dio, AuthApi>(update: (_, dio, __) => AuthApi(dio)),
        ProxyProvider<Dio, SplashApi>(update: (_, dio, __) => SplashApi(dio)),
        ProxyProvider2<AuthApi, RenSdk, AuthRepository>(
          update: (_, api, sdk, __) => AuthRepository(api, sdk),
        ),
        ProxyProvider<SplashApi, SplashRepository>(
          update: (_, api, __) => SplashRepository(api),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system, // авто переключение
        home: const SplashPage(),
      ),
    );
  }
}
