import 'package:flutter/services.dart';

class PrivacyProtectionConfig {
  const PrivacyProtectionConfig._();

  static const bool androidFlagSecure = bool.fromEnvironment(
    'REN_ANDROID_FLAG_SECURE',
    defaultValue: false,
  );

  static const bool iosPrivacyOverlay = bool.fromEnvironment(
    'REN_IOS_PRIVACY_OVERLAY',
    defaultValue: false,
  );

  static const bool iosAntiCapture = bool.fromEnvironment(
    'REN_IOS_ANTI_CAPTURE',
    defaultValue: false,
  );
}

class PrivacyProtection {
  const PrivacyProtection._();

  static const MethodChannel _channel = MethodChannel('ren/privacy_protection');

  static Future<void> configure() async {
    try {
      await _channel.invokeMethod<void>('configure', {
        'androidFlagSecure': PrivacyProtectionConfig.androidFlagSecure,
        'iosPrivacyOverlay': PrivacyProtectionConfig.iosPrivacyOverlay,
        'iosAntiCapture': PrivacyProtectionConfig.iosAntiCapture,
      });
    } on MissingPluginException {
      // no-op on unsupported platforms
    } catch (_) {
      // keep startup robust even if platform hook failed
    }
  }
}
