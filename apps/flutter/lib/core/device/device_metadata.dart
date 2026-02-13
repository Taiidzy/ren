import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceMetadata {
  final String deviceName;
  final String appVersion;

  const DeviceMetadata({required this.deviceName, required this.appVersion});
}

class DeviceMetadataProvider {
  static const String _appVersion = '1.0.0+1';
  static Future<DeviceMetadata>? _cache;

  static Future<DeviceMetadata> load() {
    return _cache ??= _loadInternal();
  }

  static Future<DeviceMetadata> _loadInternal() async {
    try {
      final plugin = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final data = info.data;
        final manufacturer = _pick(data, const ['manufacturer', 'brand']);
        final model = _pick(data, const ['model', 'device']);
        final release = _pick(data, const ['version.release']);
        final pretty = _nonEmptyOrFallback(
          _join([manufacturer, model, release]),
          'Android device',
        );
        return DeviceMetadata(deviceName: pretty, appVersion: _appVersion);
      }

      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final data = info.data;
        final name = _pick(data, const ['name']);
        final model = _pick(data, const ['model', 'utsname.machine']);
        final system = _join([
          _pick(data, const ['systemName']),
          _pick(data, const ['systemVersion']),
        ]);
        final pretty = _nonEmptyOrFallback(
          _join([name, model, system]),
          'iOS device',
        );
        return DeviceMetadata(deviceName: pretty, appVersion: _appVersion);
      }

      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        final data = info.data;
        final computer = _pick(data, const ['computerName', 'hostName']);
        final model = _pick(data, const ['model']);
        final os = _join([
          _pick(data, const ['osRelease']),
          _pick(data, const ['arch']),
        ]);
        final pretty = _nonEmptyOrFallback(
          _join([computer, model, os]),
          'macOS device',
        );
        return DeviceMetadata(deviceName: pretty, appVersion: _appVersion);
      }

      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        final data = info.data;
        final computer = _pick(data, const ['computerName']);
        final product = _pick(data, const ['productName']);
        final version = _pick(data, const ['displayVersion', 'buildNumber']);
        final pretty = _nonEmptyOrFallback(
          _join([computer, product, version]),
          'Windows device',
        );
        return DeviceMetadata(deviceName: pretty, appVersion: _appVersion);
      }

      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        final data = info.data;
        final name = _pick(data, const ['prettyName', 'name']);
        final version = _pick(data, const ['version']);
        final machine = _pick(data, const ['machineId']);
        final pretty = _nonEmptyOrFallback(
          _join([name, version, machine]),
          'Linux device',
        );
        return DeviceMetadata(deviceName: pretty, appVersion: _appVersion);
      }
    } catch (_) {
      // Fallback below.
    }

    final fallback =
        '${Platform.operatingSystem[0].toUpperCase()}${Platform.operatingSystem.substring(1)} ${Platform.operatingSystemVersion}';
    return DeviceMetadata(deviceName: fallback, appVersion: _appVersion);
  }

  static String _pick(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _resolvePath(data, key);
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static Object? _resolvePath(Map<String, dynamic> data, String path) {
    final parts = path.split('.');
    dynamic cursor = data;
    for (final part in parts) {
      if (cursor is Map<String, dynamic> && cursor.containsKey(part)) {
        cursor = cursor[part];
      } else {
        return null;
      }
    }
    return cursor;
  }

  static String _join(List<String> values) {
    return values
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty && v.toLowerCase() != 'unknown')
        .toSet()
        .join(' • ');
  }

  static String _nonEmptyOrFallback(String value, String fallback) {
    final normalized = value.trim();
    return normalized.isEmpty ? fallback : normalized;
  }
}
