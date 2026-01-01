import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:ren/shared/widgets/matte_textfield.dart';
import 'package:ren/shared/widgets/matte_button.dart';

import 'package:ren/core/cryptography/recovery_key_generator.dart';

import 'package:ren/features/auth/data/auth_repository.dart';

class SignUpForm extends StatefulWidget {
  const SignUpForm({Key? key}) : super(key: key);

  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  // Контроллеры для первого шага
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late String loginError = '';
  late String passError = '';
  late String confirmPassError = '';
  late String recoverykey = '';
  late String registrationError = '';
  late String registrationSuccessful = '';
  bool _isLoading = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Переменная для определения текущего шага
  int reg_step = 1;

  @override
  void initState() {
    super.initState();

    // Добавляем слушатели для очистки ошибок при вводе
    _loginController.addListener(_onLoginChanged);
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onConfirmPasswordChanged);
  }

  // Очистка ошибки логина при вводе
  void _onLoginChanged() {
    if (loginError.isNotEmpty && _loginController.text.isNotEmpty) {
      setState(() {
        loginError = '';
      });
    }
  }

  // Очистка ошибки пароля при вводе
  void _onPasswordChanged() {
    if (passError.isNotEmpty && _passwordController.text.isNotEmpty) {
      setState(() {
        passError = '';
      });
    }
    // Также проверяем совпадение паролей если есть ошибка подтверждения
    if (confirmPassError.isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        _confirmPasswordController.text.isNotEmpty &&
        _passwordController.text == _confirmPasswordController.text) {
      setState(() {
        confirmPassError = '';
      });
    }
  }

  // Очистка ошибки подтверждения пароля при вводе
  void _onConfirmPasswordChanged() {
    if (confirmPassError.isNotEmpty &&
        _confirmPasswordController.text.isNotEmpty &&
        _passwordController.text == _confirmPasswordController.text) {
      setState(() {
        confirmPassError = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
    return Column(
      children: [
        _buildFieldWithError(
          field: MatteTextField(
            controller: _loginController,
            hintText: 'Логин',
            prefixIcon: HugeIcon(
              icon: HugeIcons.strokeRoundedUser,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : Colors.black.withOpacity(0.5),
              size: 24.0,
            ),
          ),
          error: loginError,
        ),
        const SizedBox(height: 10), // Уменьшенный отступ
        _buildFieldWithError(
          field: MatteTextField(
            controller: _passwordController,
            hintText: 'Пароль',
            prefixIcon: HugeIcon(
              icon: HugeIcons.strokeRoundedSquareLock02,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : Colors.black.withOpacity(0.5),
              size: 24.0,
            ),
            isPassword: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: isDark
                    ? Colors.white.withOpacity(0.5)
                    : Colors.black.withOpacity(0.5),
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
        const SizedBox(height: 10), // Уменьшенный отступ
        _buildFieldWithError(
          field: MatteTextField(
            controller: _confirmPasswordController,
            hintText: 'Подтвердить пароль',
            prefixIcon: HugeIcon(
              icon: HugeIcons.strokeRoundedSquareLock02,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : Colors.black.withOpacity(0.5),
              size: 24.0,
            ),
            isPassword: _obscureConfirmPassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: isDark
                    ? Colors.white.withOpacity(0.5)
                    : Colors.black.withOpacity(0.5),
              ),
              onPressed: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                });
              },
            ),
          ),
          error: confirmPassError,
        ),
      ],
    );
  }

  // Виджет для поля с ошибкой (компактная версия)
  Widget _buildFieldWithError({required Widget field, required String error}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        // Фиксированная высота для ошибок (избегаем скачков интерфейса)
        SizedBox(
          height: error.isNotEmpty ? 18 : 4, // Минимальное место под ошибку
          child: error.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                    error,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                      fontSize: 12, // Уменьшенный размер шрифта
                    ),
                  ),
                )
              : null,
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
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontSize: 18),
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
          const SizedBox(height: 10), // Уменьшенный отступ
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
      passError = '';
      confirmPassError = '';
    });

    if (_loginController.text.isEmpty) {
      setState(() {
        loginError = 'Введите логин';
      });
      isValid = false;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        passError = 'Введите пароль';
      });
      isValid = false;
    }

    if (_confirmPasswordController.text.isEmpty) {
      setState(() {
        confirmPassError = 'Подтвердите пароль';
      });
      isValid = false;
    } else if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        confirmPassError = 'Пароли не совпадают';
      });
      isValid = false;
    }

    return isValid;
  }

  // Завершение регистрации
  Future<void> _completeRegistration() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    final rk = recoverykey;
    setState(() {
      _isLoading = true;
      registrationError = '';
      registrationSuccessful = '';
    });
    try {
      final repo = context.read<AuthRepository>();
      final result = await repo.register(login, password, rk);
      if (result.id.isNotEmpty) {
        registrationSuccessful = 'Регистрация успешно завершена';
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
    // Удаляем слушатели перед освобождением ресурсов
    _loginController.removeListener(_onLoginChanged);
    _passwordController.removeListener(_onPasswordChanged);
    _confirmPasswordController.removeListener(_onConfirmPasswordChanged);

    // Освобождаем ресурсы
    _loginController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
