// Утилита для "красивого" логирования — wrapper над пакетом `logger`.
// Что делает:
// - Настраивает красивый вывод (цвета, время, stack trace)
// - Предоставляет удобные helpers: runWithLogging / runWithLoggingAsync
// - Миксин Logged для классов (ENTER/EXIT/STEP/ERROR)
// - StepTimer для логирования шагов внутри функций с измерением времени
// - Расширение для Future для удобного логирования асинхронных операций
//
// Добавьте в pubspec.yaml:
//   dependencies:
//     logger: ^1.3.0
//
// Пример использования (вкратце):
//  import 'pretty_logger.dart';
//  class RenSdk with Logged { ... }
//  await runWithLoggingAsync('RenSdk', 'init', () async { ... });

import 'dart:async';
import 'dart:convert';

import 'package:logger/logger.dart';

/// Централизованный настроенный логгер
class PrettyLogger {
  static final PrettyPrinter _printer = PrettyPrinter(
    methodCount: 0, // don't print stack frames by default
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printTime: true,
  );

  static final Logger _logger = Logger(printer: _printer);

  /// Небольшой хелпер для добавления тега в сообщение
  static String _tagged(String tag, Object? message) =>
      '[$tag] ${message ?? ''}';

  static void v(
    String tag,
    Object? message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _logger.v(_tagged(tag, message), error: error, stackTrace: stackTrace);
  static void d(
    String tag,
    Object? message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _logger.d(_tagged(tag, message), error: error, stackTrace: stackTrace);
  static void i(
    String tag,
    Object? message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _logger.i(_tagged(tag, message), error: error, stackTrace: stackTrace);
  static void w(
    String tag,
    Object? message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _logger.w(_tagged(tag, message), error: error, stackTrace: stackTrace);
  static void e(
    String tag,
    Object? message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _logger.e(_tagged(tag, message), error: error, stackTrace: stackTrace);

  /// Удобно печатать JSON-структуры
  static void json(String tag, Object? value) {
    try {
      final pretty = const JsonEncoder.withIndent('  ').convert(value);
      _logger.i(_tagged(tag, "\n" + pretty));
    } catch (err) {
      _logger.w(_tagged(tag, 'Не удалось красиво вывести JSON:'), error: err);
    }
  }
}

/// Миксин для включения логирования в классах
mixin Logged {
  String get _loggerTag => runtimeType.toString();

  void logEnter([String name = '']) =>
      PrettyLogger.d(_loggerTag, '▶ ВХОД ${name}');
  void logExit([String name = '', Object? result]) => PrettyLogger.d(
    _loggerTag,
    '◀ ВЫХОД ${name} ${result != null ? '-> $result' : ''}',
  );
  void logStep(String step, [Object? details]) => PrettyLogger.i(
    _loggerTag,
    '• ШАГ: $step ${details != null ? '- $details' : ''}',
  );
  void logInfo(String msg) => PrettyLogger.i(_loggerTag, msg);
  void logWarn(String msg) => PrettyLogger.w(_loggerTag, msg);
  void logError(String where, Object error, [StackTrace? st]) =>
      PrettyLogger.e(_loggerTag, '✖ ОШИБКА в $where: $error', error, st);

  /// Быстро добавить структуру как JSON
  void logJson(Object value) => PrettyLogger.json(_loggerTag, value);
}

/// Простая утилита для логирования шагов и их длительности внутри функции
class StepTimer {
  final String tag;
  final List<_StepEntry> _stack = [];

  StepTimer(this.tag);

  void startStep(String name) {
    _stack.add(_StepEntry(name, DateTime.now()));
    PrettyLogger.d(tag, '→ start: $name');
  }

  void endStep([String? name]) {
    if (_stack.isEmpty) {
      PrettyLogger.w(tag, 'endStep called but stack is empty');
      return;
    }
    final entry = _stack.removeLast();
    final end = DateTime.now();
    final duration = end.difference(entry.start);
    final stepName = name ?? entry.name;
    PrettyLogger.i(
      tag,
      '✔ step: $stepName (took ${duration.inMilliseconds} ms)',
    );
  }

  /// Удобный синхронный wrapper: логируем шаг и возвращаем результат
  T run<T>(String name, T Function() body) {
    startStep(name);
    try {
      final res = body();
      endStep(name);
      return res;
    } catch (e, st) {
      PrettyLogger.e(tag, 'Exception in step $name', e, st as StackTrace?);
      rethrow;
    }
  }

  /// Удобный асинхронный wrapper
  Future<T> runAsync<T>(String name, Future<T> Function() body) async {
    startStep(name);
    try {
      final res = await body();
      endStep(name);
      return res;
    } catch (e, st) {
      PrettyLogger.e(
        tag,
        'Exception in async step $name',
        e,
        st as StackTrace?,
      );
      rethrow;
    }
  }
}

class _StepEntry {
  final String name;
  final DateTime start;
  _StepEntry(this.name, this.start);
}

/// Instrumentation wrappers — оборачивают функцию, логируют вход/выход/время/исключения
T runWithLogging<T>(String tag, String name, T Function() body) {
  final sw = Stopwatch()..start();
  PrettyLogger.d(tag, '▶ ВХОД $name');
  try {
    final res = body();
    sw.stop();
    PrettyLogger.d(
      tag,
      '◀ ВЫХОД $name (заняло ${sw.elapsedMilliseconds} мс) -> $res',
    );
    return res;
  } catch (e, st) {
    sw.stop();
    PrettyLogger.e(
      tag,
      '✖ ИСКЛЮЧЕНИЕ $name (через ${sw.elapsedMilliseconds} мс): $e',
      e,
      st as StackTrace?,
    );
    rethrow;
  }
}

Future<T> runWithLoggingAsync<T>(
  String tag,
  String name,
  Future<T> Function() body,
) async {
  final sw = Stopwatch()..start();
  PrettyLogger.d(tag, '▶ ВХОД async $name');
  try {
    final res = await body();
    sw.stop();
    PrettyLogger.d(
      tag,
      '◀ ВЫХОД async $name (заняло ${sw.elapsedMilliseconds} мс) -> $res',
    );
    return res;
  } catch (e, st) {
    sw.stop();
    PrettyLogger.e(
      tag,
      '✖ ИСКЛЮЧЕНИЕ async $name (через ${sw.elapsedMilliseconds} мс): $e',
      e,
      st as StackTrace?,
    );
    rethrow;
  }
}

/// Расширение для Future — удобно логировать промисы
extension FutureLoggingExtension<T> on Future<T> {
  Future<T> logAs(String tag, String name) {
    return runWithLoggingAsync(tag, name, () => this);
  }
}
