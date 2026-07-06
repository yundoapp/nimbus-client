import 'dart:convert';

class NimbusUser {
  const NimbusUser({required this.id, required this.username, required this.status, this.mustChangePassword = false});

  factory NimbusUser.fromJson(Map<String, dynamic> json) {
    return NimbusUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      status: json['status'] as String? ?? '',
      mustChangePassword: json['mustChangePassword'] as bool? ?? false,
    );
  }

  final String id;
  final String username;
  final String status;
  final bool mustChangePassword;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'status': status,
    'mustChangePassword': mustChangePassword,
  };
}

class NimbusDevice {
  const NimbusDevice({required this.id, required this.deviceId, required this.platform, required this.deviceName});

  factory NimbusDevice.fromJson(Map<String, dynamic> json) {
    return NimbusDevice(
      id: json['id'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? '',
    );
  }

  final String id;
  final String deviceId;
  final String platform;
  final String deviceName;

  Map<String, dynamic> toJson() => {'id': id, 'deviceId': deviceId, 'platform': platform, 'deviceName': deviceName};
}

class NimbusAuthSession {
  const NimbusAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    required this.device,
  });

  factory NimbusAuthSession.fromJson(Map<String, dynamic> json) {
    return NimbusAuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      user: NimbusUser.fromJson(Map<String, dynamic>.from(json['user'] as Map? ?? const {})),
      device: NimbusDevice.fromJson(Map<String, dynamic>.from(json['device'] as Map? ?? const {})),
    );
  }

  final String accessToken;
  final String refreshToken;
  final NimbusUser user;
  final NimbusDevice device;

  NimbusAuthSession copyWith({String? accessToken, String? refreshToken, NimbusUser? user, NimbusDevice? device}) {
    return NimbusAuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      user: user ?? this.user,
      device: device ?? this.device,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'user': user.toJson(),
    'device': device.toJson(),
  };

  String encode() => jsonEncode(toJson());
}

class NimbusSubscription {
  const NimbusSubscription({
    required this.status,
    this.planName,
    this.expiresAt,
    this.cycleStartAt,
    this.cycleEndAt,
    this.quotaBytes,
    this.usedBytes = 0,
    this.remainingBytes,
  });

  factory NimbusSubscription.fromJson(Map<String, dynamic> json) {
    return NimbusSubscription(
      status: json['status'] as String? ?? 'none',
      planName: json['planName'] as String?,
      expiresAt: _dateTime(json['expiresAt']),
      cycleStartAt: _dateTime(json['cycleStartAt']),
      cycleEndAt: _dateTime(json['cycleEndAt']),
      quotaBytes: _int(json['quotaBytes']),
      usedBytes: _int(json['usedBytes']) ?? 0,
      remainingBytes: _int(json['remainingBytes']),
    );
  }

  final String status;
  final String? planName;
  final DateTime? expiresAt;
  final DateTime? cycleStartAt;
  final DateTime? cycleEndAt;
  final int? quotaBytes;
  final int usedBytes;
  final int? remainingBytes;

  bool get hasActivePlan => status == 'active';
}

class NimbusDeviceQuota {
  const NimbusDeviceQuota({required this.used, required this.limit});

  factory NimbusDeviceQuota.fromJson(Map<String, dynamic> json) {
    return NimbusDeviceQuota(used: _int(json['used']) ?? 0, limit: _int(json['limit']) ?? 0);
  }

  final int used;
  final int limit;
}

class NimbusRulesInfo {
  const NimbusRulesInfo({this.publicRulesVersion});

  factory NimbusRulesInfo.fromJson(Map<String, dynamic> json) {
    return NimbusRulesInfo(publicRulesVersion: json['publicRulesVersion'] as String?);
  }

  final String? publicRulesVersion;
}

class NimbusMe {
  const NimbusMe({required this.user, required this.subscription, required this.devices, required this.rules});

  factory NimbusMe.fromJson(Map<String, dynamic> json) {
    return NimbusMe(
      user: NimbusUser.fromJson(Map<String, dynamic>.from(json['user'] as Map? ?? const {})),
      subscription: NimbusSubscription.fromJson(Map<String, dynamic>.from(json['subscription'] as Map? ?? const {})),
      devices: NimbusDeviceQuota.fromJson(Map<String, dynamic>.from(json['devices'] as Map? ?? const {})),
      rules: NimbusRulesInfo.fromJson(Map<String, dynamic>.from(json['rules'] as Map? ?? const {})),
    );
  }

  final NimbusUser user;
  final NimbusSubscription subscription;
  final NimbusDeviceQuota devices;
  final NimbusRulesInfo rules;
}

class NimbusRegisteredDevice {
  const NimbusRegisteredDevice({
    required this.id,
    required this.deviceId,
    required this.platform,
    required this.deviceName,
    required this.appVersion,
    required this.status,
    required this.isCurrent,
    required this.firstLoginAt,
    this.lastActiveAt,
  });

  factory NimbusRegisteredDevice.fromJson(Map<String, dynamic> json) {
    return NimbusRegisteredDevice(
      id: json['id'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      platform: json['platform'] as String? ?? 'unknown',
      deviceName: json['deviceName'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? '',
      status: json['status'] as String? ?? '',
      isCurrent: json['isCurrent'] as bool? ?? false,
      firstLoginAt: _dateTime(json['firstLoginAt']),
      lastActiveAt: _dateTime(json['lastActiveAt']),
    );
  }

  final String id;
  final String deviceId;
  final String platform;
  final String deviceName;
  final String appVersion;
  final String status;
  final bool isCurrent;
  final DateTime? firstLoginAt;
  final DateTime? lastActiveAt;
}

class NimbusDevicesList {
  const NimbusDevicesList({required this.limit, required this.items});

  factory NimbusDevicesList.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return NimbusDevicesList(
      limit: _int(json['limit']) ?? 0,
      items: rawItems is List
          ? rawItems
                .map((item) => NimbusRegisteredDevice.fromJson(Map<String, dynamic>.from(item as Map? ?? const {})))
                .toList()
          : const [],
    );
  }

  final int limit;
  final List<NimbusRegisteredDevice> items;

  int get used => items.length;
}

class NimbusDeviceRemoveResult {
  const NimbusDeviceRemoveResult({required this.success, required this.deletedCurrentDevice});

  factory NimbusDeviceRemoveResult.fromJson(Map<String, dynamic> json) {
    return NimbusDeviceRemoveResult(
      success: json['success'] as bool? ?? false,
      deletedCurrentDevice: json['deletedCurrentDevice'] as bool? ?? false,
    );
  }

  final bool success;
  final bool deletedCurrentDevice;
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

int? _int(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
