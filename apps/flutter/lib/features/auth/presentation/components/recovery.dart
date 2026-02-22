import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/shared/widgets/matte_textfield.dart';
import 'package:ren/shared/widgets/matte_button.dart';

class ForgotPasswordForm extends StatefulWidget {
  const ForgotPasswordForm({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordForm> createState() => _ForgotPasswordFormState();
}

class _ForgotPasswordFormState extends State<ForgotPasswordForm> {
  final _loginController = TextEditingController();
  final _keyController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalGap = constraints.maxWidth < 360 ? 20.0 : 28.0;
        return Column(
          children: [
            Text(
              'Сброс пароля',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w300,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: verticalGap),
            Text(
              'Введите логин и ключ доступа, чтобы сбросить пароль.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.65),
                height: 1.4,
                fontWeight: FontWeight.w300,
              ),
            ),
            SizedBox(height: verticalGap),
            MatteTextField(
              controller: _loginController,
              hintText: 'Логин',
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
                color: theme.colorScheme.onSurface.withOpacity(0.85),
                size: 20.0,
              ),
            ),
            SizedBox(height: verticalGap),
            MatteTextField(
              controller: _keyController,
              hintText: 'Ключ доступа',
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedLockKey,
                color: theme.colorScheme.onSurface.withOpacity(0.85),
                size: 20.0,
              ),
            ),
            SizedBox(height: verticalGap),
            MatteButton(
              onPressed: () {
                // Логика восстановления пароля
              },
              text: 'Далее',
            ),
          ],
        );
      },
    );
  }
}
