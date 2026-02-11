import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import 'package:ren/shared/widgets/matte_textfield.dart';
import 'package:ren/shared/widgets/matte_button.dart';
import 'package:ren/shared/widgets/matte_toggle.dart';
import 'package:ren/shared/widgets/adaptive_page_route.dart';

import 'package:ren/features/splash/presentation/splash_page.dart';

import 'package:ren/features/auth/data/auth_repository.dart';

class SignInForm extends StatefulWidget {
  const SignInForm({super.key});

  @override
  State<SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<SignInForm>
    with TickerProviderStateMixin {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  String _loginError = "";
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  Future<void> _login() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
    });

    _animationController.repeat(reverse: true);

    if (login.isEmpty || password.isEmpty) {
      setState(() {
        _isLoading = false;
        _loginError = 'Отсутствуют данные для входа';
      });
      return;
    }

    try {
      if (!mounted) return;

      final login = _loginController.text.trim();
      final password = _passwordController.text;

      final repo = context.read<AuthRepository>();
      final result = await repo.login(login, password, _rememberMe);
      if (result.id >= 0) {
        Navigator.of(context).pushReplacement(
          adaptivePageRoute((_) => SplashPage()),
        );
      }
    } catch (error) {
      debugPrint(error.toString());
      setState(() {
        _isLoading = false;
        _loginError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _animationController.stop(); // Останавливаем анимацию
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        MatteTextField(
          controller: _loginController,
          hintText: 'Логин',
          prefixIcon: HugeIcon(
            icon: HugeIcons.strokeRoundedUser,
            color: theme.colorScheme.onSurface.withOpacity(0.85),
            size: 24.0,
          ),
        ),
        const SizedBox(height: 16),
        MatteTextField(
          controller: _passwordController,
          hintText: 'Пароль',
          prefixIcon: HugeIcon(
            icon: HugeIcons.strokeRoundedSquareLock02,
            color: theme.colorScheme.onSurface.withOpacity(0.85),
            size: 24.0,
          ),
          isPassword: _obscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
              color: theme.colorScheme.onSurface.withOpacity(0.85),
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        MatteToggle(
          value: _rememberMe,
          onChanged: (bool value) => setState(() {
            _rememberMe = value;
          }),
          label: "Запомнить меня",
        ),
        const SizedBox(height: 16),
        _isLoading
            ? _buildLoadingAnimation(
                isDark,
              ) // Если идет загрузка, показываем анимацию
            : MatteButton(
                // Иначе, показываем кнопку
                onPressed: _login,
                text: 'Войти',
              ),
        _loginError.isNotEmpty
            ? Text(_loginError, style: const TextStyle(color: Colors.red))
            : const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildLoadingAnimation(bool isDark) {
    // Контейнер-обертка, чтобы анимация занимала место кнопки
    return SizedBox(
      height: 50, // Высота, как у вашей кнопки
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          // Чтобы анимация шла по всей ширине, рассчитаем максимальное смещение
          // Ширина контейнера (предположим 200) - ширина полоски (60) = 140
          // Лучше использовать LayoutBuilder для точных размеров, но для примера сойдет
          return LayoutBuilder(
            builder: (context, constraints) {
              final double travelDistance = constraints.maxWidth - 60;
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Ваш код анимации, адаптированный
                  Positioned(
                    left: _animation.value * travelDistance,
                    child: Container(
                      width: 60,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  Colors.white.withOpacity(0.2),
                                  Colors.white.withOpacity(0.8),
                                  Colors.white.withOpacity(0.2),
                                ]
                              : [
                                  const Color(0xFF1A1B2E).withOpacity(0.2),
                                  const Color(0xFF1A1B2E).withOpacity(0.8),
                                  const Color(0xFF1A1B2E).withOpacity(0.2),
                                ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
