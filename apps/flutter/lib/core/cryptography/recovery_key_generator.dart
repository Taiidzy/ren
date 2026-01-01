import 'dart:math';

String generateRecoveryKey({int length = 6}) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();

  return List.generate(
    length,
    (_) => chars[random.nextInt(chars.length)],
  ).join();
}
