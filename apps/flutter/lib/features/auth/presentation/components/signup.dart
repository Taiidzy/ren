import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:ren/shared/widgets/matte_textfield.dart';
import 'package:ren/shared/widgets/matte_button.dart';

import 'package:ren/core/cryptography/recovery_key_generator.dart';

import 'package:ren/features/auth/data/auth_repository.dart';

class SignUpForm extends StatefulWidget {
  final VoidCallback? onRegistrationSuccess;

  const SignUpForm({Key? key, this.onRegistrationSuccess}) : super(key: key);

  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  // Контроллеры для первого шага
  final _loginController = TextEditingController();
  final _usernameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();

  late String loginError = '';
  late String usernameError = '';
  late String nicknameError = '';
  late String passError = '';
  late String recoverykey = '';
  late String registrationError = '';
  late String registrationSuccessful = '';
  bool _isLoading = false;

  // Флаги проверки доступности
  bool _isCheckingLogin = false;
  bool _isCheckingUsername = false;
  bool _isLoginAvailable = false;
  bool _isUsernameAvailable = false;

  Timer? _loginDebounce;
  Timer? _usernameDebounce;

  bool _obscurePassword = true;

  // Переменная для определения текущего шага
  int reg_step = 1;

  @override
  void initState() {
    super.initState();

    // Добавляем слушатели для очистки ошибок и проверки доступности при вводе
    _loginController.addListener(_onLoginChanged);
    _usernameController.addListener(_onUsernameChanged);
    _nicknameController.addListener(_onNicknameChanged);
    _passwordController.addListener(_onPasswordChanged);
  }

  // Проверка доступности логина
  Future<void> _checkLoginAvailability(String login) async {
    _loginDebounce?.cancel();
    if (login.isEmpty) {
      setState(() {
        _isLoginAvailable = false;
        _isCheckingLogin = false;
      });
      return;
    }

    _loginDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isCheckingLogin = true);
      try {
        final api = context.read<AuthRepository>().api;
        // Используем searchUsers для проверки — если найден точный match, логин занят
        final results = await api.searchUsers(login, limit: 10);
        final isTaken = results.any((u) =>
            (u['username'] as String?)?.toLowerCase() == login.toLowerCase() ||
            (u['login'] as String?)?.toLowerCase() == login.toLowerCase());
        if (mounted) {
          setState(() {
            _isLoginAvailable = !isTaken;
            _isCheckingLogin = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isCheckingLogin = false);
        }
      }
    });
  }

  // Проверка доступности username
  Future<void> _checkUsernameAvailability(String username) async {
    _usernameDebounce?.cancel();
    if (username.isEmpty) {
      setState(() {
        _isUsernameAvailable = false;
        _isCheckingUsername = false;
      });
      return;
    }

    _usernameDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isCheckingUsername = true);
      try {
        final api = context.read<AuthRepository>().api;
        final results = await api.searchUsers(username, limit: 10);
        final isTaken = results.any((u) =>
            (u['username'] as String?)?.toLowerCase() == username.toLowerCase());
        if (mounted) {
          setState(() {
            _isUsernameAvailable = !isTaken;
            _isCheckingUsername = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isCheckingUsername = false);
        }
      }
    });
  }

  // Очистка ошибки логина при вводе
  void _onLoginChanged() {
    if (loginError.isNotEmpty && _loginController.text.isNotEmpty) {
      setState(() => loginError = '');
    }
    _checkLoginAvailability(_loginController.text.trim());
  }

  // Очистка ошибки username при вводе
  void _onUsernameChanged() {
    if (usernameError.isNotEmpty && _usernameController.text.isNotEmpty) {
      setState(() => usernameError = '');
    }
    _checkUsernameAvailability(_usernameController.text.trim());
  }

  // Очистка ошибки nickname при вводе
  void _onNicknameChanged() {
    if (nicknameError.isNotEmpty && _nicknameController.text.isNotEmpty) {
      setState(() => nicknameError = '');
    }
  }

  // Очистка ошибки пароля при вводе
  void _onPasswordChanged() {
    if (passError.isNotEmpty && _passwordController.text.isNotEmpty) {
      setState(() => passError = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Показываем форму в зависимости от reg_step
        if (reg_step == 1) _buildFirstStep(isDark),
        if (reg_step == 2) _buildSecondStep(isDark),

        // Уменьшенный отступ
        const SizedBox(height: 16),

        // Кнопка меняется в зависимости от шага
        _buildActionButton(),
      ],
    );
  }

  // Первый шаг - основная информация для входа
  Widget _buildFirstStep(bool isDark) {
    final theme = Theme.of(context);
    final onSurfaceFaint = theme.colorScheme.onSurface.withOpacity(0.55);
    return Column(
      children: [
        _buildFieldWithError(
          field: MatteTextField(
            controller: _loginController,
            hintText: 'Логин',
            prefixIcon: HugeIcon(
              icon: HugeIcons.strokeRoundedUser,
              color: onSurfaceFaint,
              size: 24.0,
            ),
          ),
          error: loginError,
          suffixIcon: _isCheckingLogin
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _loginController.text.isNotEmpty
                  ? Icon(
                      _isLoginAvailable
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      color: _isLoginAvailable ? Colors.green : Colors.red,
                      size: 20,
                    )
                  : null,
        ),
        const SizedBox(height: 10),
        _buildFieldWithError(
          field: MatteTextField(
            controller: _usernameController,
            hintText: 'Username',
            prefixIcon: HugeIcon(
              icon: HugeIcons.strokeRoundedUser,
              color: onSurfaceFaint,
              size: 24.0,
            ),
          ),
          error: usernameError,
          suffixIcon: _isCheckingUsername
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _usernameController.text.isNotEmpty
                  ? Icon(
                      _isUsernameAvailable
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      color: _isUsernameAvailable ? Colors.green : Colors.red,
                      size: 20,
                    )
                  : null,
        ),
        const SizedBox(height: 10),
        _buildFieldWithError(
          field: MatteTextField(
            controller: _nicknameController,
            hintText: 'Nickname (опционально)',
            prefixIcon: HugeIcon(
              icon: HugeIcons.strokeRoundedUser,
              color: onSurfaceFaint,
              size: 24.0,
            ),
          ),
          error: nicknameError,
        ),
        const SizedBox(height: 10),
        _buildFieldWithError(
          field: MatteTextField(
            controller: _passwordController,
            hintText: 'Пароль',
            prefixIcon: HugeIcon(
              icon: HugeIcons.strokeRoundedSquareLock02,
              color: onSurfaceFaint,
              size: 24.0,
            ),
            isPassword: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: onSurfaceFaint,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          error: passError,
        ),
      ],
    );
  }

  Widget _buildFieldWithError({
    required Widget field,
    required String error,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            field,
            if (suffixIcon != null)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(child: suffixIcon),
              ),
          ],
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  // Второй шаг - дополнительная информация
  Widget _buildSecondStep(bool isDark) {
    return Column(
      children: [
        Text(
          'Ключ восстановления аккаунта',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.15)
                  : Colors.black.withOpacity(0.1),
            ),
          ),
          child: SelectableText(
            recoverykey.isEmpty ? '• • • • • • ' : recoverykey,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Text(
          'Скопируйте ключ восстановления и сохраните его в безопасном месте.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
      ],
    );
  }

  // Кнопки для навигации между шагами
  Widget _buildActionButton() {
    if (reg_step == 1) {
      return MatteButton(
        onPressed: () {
          // Валидация первого шага
          if (_validateFirstStep()) {
            setState(() {
              reg_step = 2;
              recoverykey = generateRecoveryKey();
            });
          }
        },
        text: 'Продолжить',
      );
    } else {
      return Column(
        children: [
          _isLoading
              ? SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: Center(child: CircularProgressIndicator()),
                )
              : MatteButton(
                  onPressed: () {
                    _completeRegistration();
                  },
                  text: 'Завершить регистрацию',
                ),
          const SizedBox(height: 10),
          MatteButton(
            onPressed: () {
              setState(() {
                reg_step = 1;
              });
            },
            text: 'Назад',
          ),
          if (registrationError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                registrationError,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                      fontSize: 12,
                    ),
              ),
            ),
          if (registrationSuccessful.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                registrationSuccessful,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontSize: 12,
                    ),
              ),
            ),
        ],
      );
    }
  }

  // Валидация первого шага
  bool _validateFirstStep() {
    bool isValid = true;

    // Сбрасываем все ошибки
    setState(() {
      loginError = '';
      usernameError = '';
      nicknameError = '';
      passError = '';
    });

    // Проверка nickname (опционально, но если введён - макс. 32 символа)
    if (_nicknameController.text.isNotEmpty && _nicknameController.text.length > 32) {
      setState(() {
        nicknameError = 'Nickname не может быть длиннее 32 символов';
      });
      isValid = false;
    }

    if (_loginController.text.isEmpty) {
      setState(() {
        loginError = 'Введите логин';
      });
      isValid = false;
    } else if (!_isLoginAvailable) {
      setState(() {
        loginError = 'Логин уже занят';
      });
      isValid = false;
    }

    if (_usernameController.text.isEmpty) {
      setState(() {
        usernameError = 'Введите username';
      });
      isValid = false;
    } else if (!_isUsernameAvailable) {
      setState(() {
        usernameError = 'Username уже занят';
      });
      isValid = false;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        passError = 'Введите пароль';
      });
      isValid = false;
    } else if (_passwordController.text.length < 6) {
      setState(() {
        passError = 'Пароль должен быть не менее 6 символов';
      });
      isValid = false;
    }

    return isValid;
  }

  // Завершение регистрации
  Future<void> _completeRegistration() async {
    final login = _loginController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final rk = recoverykey;
    final nickname = _nicknameController.text.trim().isEmpty
        ? null
        : _nicknameController.text.trim();
    setState(() {
      _isLoading = true;
      registrationError = '';
      registrationSuccessful = '';
    });
    try {
      final repo = context.read<AuthRepository>();
      final result = await repo.register(login, password, rk, nickname, username);
      if (result.id.isNotEmpty) {
        setState(() {
          registrationSuccessful = 'Регистрация успешно завершена';
        });
        widget.onRegistrationSuccess?.call();
      }
    } catch (e) {
      setState(() {
        registrationError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _loginDebounce?.cancel();
    _usernameDebounce?.cancel();
    _loginController.removeListener(_onLoginChanged);
    _usernameController.removeListener(_onUsernameChanged);
    _nicknameController.removeListener(_onNicknameChanged);
    _passwordController.removeListener(_onPasswordChanged);
    _loginController.dispose();
    _usernameController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
