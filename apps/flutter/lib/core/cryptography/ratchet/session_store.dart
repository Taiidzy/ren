/// Session Store
/// 
/// Хранение сессий Double Ratchet

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

/// In-Memory Session Store (для тестирования)
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

/// TODO: Hive Session Store для продакшена
/// 
/// ```dart
/// import 'package:hive/hive.dart';
/// 
/// class HiveSessionStore implements SessionStore {
///   final Box<RatchetSessionBox> _box;
///   
///   HiveSessionStore(this._box);
///   
///   @override
///   Future<RatchetSessionState?> getSession(String recipientId) async {
///     return _box.get(recipientId)?.toSessionState();
///   }
///   
///   @override
///   Future<void> storeSession(String recipientId, RatchetSessionState session) async {
///     await _box.put(recipientId, RatchetSessionBox.fromSessionState(session));
///   }
///   
///   // ... остальные методы
/// }
/// ```
