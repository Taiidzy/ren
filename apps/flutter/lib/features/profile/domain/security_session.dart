class SecuritySession {
  final String id;
  final String deviceName;
  final String ipAddress;
  final String city;
  final String appVersion;
  final DateTime loginAt;
  final DateTime lastSeenAt;
  final bool isCurrent;

  SecuritySession({
    required this.id,
    required this.deviceName,
    required this.ipAddress,
    required this.city,
    required this.appVersion,
    required this.loginAt,
    required this.lastSeenAt,
    required this.isCurrent,
  });

  factory SecuritySession.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      final raw = (value ?? '').toString();
      return DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    }

    return SecuritySession(
      id: (map['id'] ?? '').toString(),
      deviceName: ((map['device_name'] ?? 'Unknown device').toString()).trim(),
      ipAddress: ((map['ip_address'] ?? 'unknown').toString()).trim(),
      city: ((map['city'] ?? 'Unknown').toString()).trim(),
      appVersion: ((map['app_version'] ?? 'unknown').toString()).trim(),
      loginAt: parseDate(map['login_at']),
      lastSeenAt: parseDate(map['last_seen_at']),
      isCurrent: map['is_current'] == true,
    );
  }
}
