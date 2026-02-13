import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ren/features/auth/presentation/components/signin.dart';

void main() {
  testWidgets('SignInForm validates empty credentials before network call', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SignInForm())),
    );

    await tester.tap(find.text('Войти'));
    await tester.pump();

    expect(find.text('Отсутствуют данные для входа'), findsOneWidget);
  });
}
