import 'package:ren/features/splash/data/spalsh_api.dart';

class SplashRepository {
  final SplashApi api;

  SplashRepository(this.api);

  Future<Map<String, dynamic>> checkAuth(String token) async {
    final json = await api.verefyToken(token);
    return json;
  }
}
