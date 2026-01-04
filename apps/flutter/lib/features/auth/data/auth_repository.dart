import 'package:ren/features/auth/data/auth_api.dart';
import 'package:ren/features/auth/domain/auth_user.dart';
import 'package:ren/features/auth/domain/auth_models.dart';


import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/core/constants/keys.dart';

import 'package:ren/core/sdk/ren_sdk.dart';

class AuthRepository {
  final AuthApi api;
  final RenSdk renSdk;

  AuthRepository(this.api, this.renSdk);

  Future<AuthUser> login(String login, String password, bool rememberMe) async {
    final json = await api.login(login, password, rememberMe);

    final resp = LoginResponse.fromMap(json);

    final masterKey = renSdk.deriveKeyFromPassword(
      password,
      resp.user.salt ?? '',
    );

    final privateKey = renSdk.decryptData(resp.user.pkebymk ?? '', masterKey);

    if (privateKey == null) {
      throw Exception('Failed to decrypt private key');
    }

    final priv = privateKey.trim();
    final pub = (resp.user.pubk ?? '').trim();
    if (pub.isEmpty) {
      throw Exception('Public key is missing');
    }

    // Self-check: pub/priv должны образовывать пару.
    final mk = renSdk.generateMessageKey().trim();
    final wrapped = renSdk.wrapSymmetricKey(mk, pub);
    final w = (wrapped?['wrapped'] ?? '').trim();
    final eph = (wrapped?['ephemeral_public_key'] ?? '').trim();
    final n = (wrapped?['nonce'] ?? '').trim();
    final unwrapped = (wrapped == null) ? null : renSdk.unwrapSymmetricKey(w, eph, n, priv);
    if (unwrapped == null || unwrapped.isEmpty) {
      await SecureStorage.deleteAllKeys();
      throw Exception('E2EE keys mismatch: server returned incompatible pubk/pkebymk');
    }

    await SecureStorage.writeKey(Keys.PrivateKey, priv);
    await SecureStorage.writeKey(Keys.PublicKey, pub);
    await SecureStorage.writeKey(Keys.Token, resp.token);
    await SecureStorage.writeKey(Keys.UserId, resp.user.id.toString());

    return AuthUser(
      id: resp.user.id,
      login: resp.user.login,
      username: resp.user.username,
      avatar: resp.user.avatar,
      pkebymk: resp.user.pkebymk,
      pkebyrk: resp.user.pkebyrk,
      pubk: resp.user.pubk,
      token: resp.token,
    );
  }

  Future<RegisterUser> register(
    String login,
    String password,
    String recoveryKey,
  ) async {
    final username = login;
    // Генерируем пару ключей и производные значения через публичные методы SDK
    final kp = renSdk.generateKeyPair();
    if (kp == null) {
      throw Exception('Key pair generation failed');
    }
    final publicKey = kp['public_key']!;
    final privateKey = kp['private_key']!;

    // Соль и мастер-ключ: MK = KDF(password, salt)
    final salt = renSdk.generateSalt();
    final masterKey = renSdk.deriveKeyFromPassword(password, salt);

    // pkebymk: приватный ключ, зашифрованный мастер-ключом
    final encByMk = renSdk.encryptData(privateKey, masterKey);
    if (encByMk == null) {
      throw Exception('Failed to encrypt private key by master key');
    }
    final pkebymk = encByMk;

    // pkebyrk: приватный ключ, зашифрованный ключом восстановления (6 символов)
    final recoveryKdf = renSdk.deriveKeyFromString(recoveryKey);
    final encByRk = renSdk.encryptData(privateKey, recoveryKdf);
    if (encByRk == null) {
      throw Exception('Failed to encrypt private key by recovery key');
    }
    final pkebyrk = encByRk;

    // pubk: публичный ключ как есть
    final pubk = publicKey;

    // Вызываем API register. Порядок аргументов: login, password, username, ...
    final json = await api.register(
      login,
      password,
      username,
      pkebymk,
      pkebyrk,
      pubk,
      salt,
    );

    return RegisterUser(
      id: (json['id'] ?? '').toString(),
      login: (json['login'] ?? login).toString(),
      username: (json['username'] ?? username).toString(),
      pkebymk: (json['pkebymk'] ?? pkebymk).toString(),
      pkebyrk: (json['pkebyrk'] ?? pkebyrk).toString(),
      pubk: (json['pubk'] ?? pubk).toString(),
      salt: (json['salt'] ?? salt).toString(),
    );
  }
}
