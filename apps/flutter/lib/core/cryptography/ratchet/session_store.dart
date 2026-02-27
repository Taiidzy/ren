/// Session Store
///
/// Хранение сессий Double Ratchet
///
/// Использует Hive для персистентного хранения сессий

import 'package:hive/hive.dart';
import 'ratchet_session.dart';

/// Session Store Interface
abstract class SessionStore {
  /// Получить сессию по ID получателя
  Future<RatchetSessionState?> getSession(String recipientId);

  /// Сохранить сессию
  Future<void> storeSession(String recipientId, RatchetSessionState session);

  /// Удалить сессию
  Future<void> deleteSession(String recipientId);

  /// Получить все ID сессий
  Future<List<String>> getAllSessionIds();

  /// Очистить все сессии
  Future<void> clearAll();
}

/// In-Memory Session Store (для тестирования и разработки)
class InMemorySessionStore implements SessionStore {
  final Map<String, RatchetSessionState> _sessions = {};

  @override
  Future<RatchetSessionState?> getSession(String recipientId) async {
    return _sessions[recipientId];
  }

  @override
  Future<void> storeSession(String recipientId, RatchetSessionState session) async {
    _sessions[recipientId] = session;
  }

  @override
  Future<void> deleteSession(String recipientId) async {
    _sessions.remove(recipientId);
  }

  @override
  Future<List<String>> getAllSessionIds() async {
    return _sessions.keys.toList();
  }

  @override
  Future<void> clearAll() async {
    _sessions.clear();
  }
}

/// Hive Session Store для продакшена
///
/// Хранит сессии в Hive box с опциональным шифрованием
class HiveSessionStore implements SessionStore {
  final Box<Map> _box;
  static const String _boxName = 'ratchet_sessions';

  /// Создать HiveSessionStore
  /// 
  /// [box] - Hive box для хранения сессий
  HiveSessionStore(this._box);

  /// Инициализировать Hive box
  /// 
  /// Должен быть вызван перед использованием HiveSessionStore
  /// 
  /// [boxName] - имя box для хранения сессий (по умолчанию 'ratchet_sessions')
  /// [encryptionCipher] - опциональный cipher для шифрования данных
  static Future<HiveSessionStore> initialize({
    String boxName = _boxName,
    HiveCipher? encryptionCipher,
  }) async {
    final box = await Hive.openBox<Map>(
      boxName,
      keyComparator: (a, b) => (a as String).compareTo(b as String),
    );
    return HiveSessionStore(box);
  }

  @override
  Future<RatchetSessionState?> getSession(String recipientId) async {
    final data = _box.get(recipientId);
    if (data == null) return null;

    return RatchetSessionState.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> storeSession(String recipientId, RatchetSessionState session) async {
    await _box.put(recipientId, session.toJson());
  }

  @override
  Future<void> deleteSession(String recipientId) async {
    await _box.delete(recipientId);
  }

  @override
  Future<List<String>> getAllSessionIds() async {
    return _box.keys.cast<String>().toList();
  }

  @override
  Future<void> clearAll() async {
    await _box.clear();
  }

  /// Закрыть box и освободить ресурсы
  Future<void> close() async {
    await _box.close();
  }
}
