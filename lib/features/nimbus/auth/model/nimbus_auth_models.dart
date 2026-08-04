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
    this.startedAt,
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
      startedAt: _dateTime(json['startedAt']),
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
  final DateTime? startedAt;
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

class NimbusLocation {
  const NimbusLocation({required this.code, required this.displayName, this.displayNames = const {}});

  factory NimbusLocation.fromJson(Map<String, dynamic> json) {
    final rawDisplayNames = json['displayNames'];
    return NimbusLocation(
      code: json['code'] as String? ?? 'auto',
      displayName: json['displayName'] as String? ?? '',
      displayNames: rawDisplayNames is Map
          ? rawDisplayNames.map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''))
          : const {},
    );
  }

  final String code;
  final String displayName;
  final Map<String, String> displayNames;

  String displayNameForLanguage(String languageCode) {
    if (code == 'auto') return '';
    final english = (displayNames['en'] ?? '').trim();
    final chinese = (displayNames['zh-CN'] ?? displayNames['zh'] ?? displayName).trim();
    if (languageCode.toLowerCase().startsWith('zh')) {
      if (english.isNotEmpty && chinese.isNotEmpty && english != chinese) return '$english · $chinese';
      final localized = chinese.isNotEmpty ? chinese : english;
      return localized.isEmpty ? code : localized;
    }
    final localized = english.isNotEmpty ? english : displayName.trim();
    return localized.isEmpty ? code : localized;
  }
}

class NimbusLocationsList {
  const NimbusLocationsList({required this.items});

  factory NimbusLocationsList.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return NimbusLocationsList(
      items: rawItems is List
          ? rawItems
                .map((item) => NimbusLocation.fromJson(Map<String, dynamic>.from(item as Map? ?? const {})))
                .toList()
          : const [NimbusLocation(code: 'auto', displayName: '')],
    );
  }

  final List<NimbusLocation> items;

  NimbusLocation get fallback => items.firstWhere(
    (item) => item.code == 'auto',
    orElse: () => const NimbusLocation(code: 'auto', displayName: ''),
  );
}

class NimbusRoutePreference {
  const NimbusRoutePreference({
    required this.id,
    required this.type,
    required this.targetType,
    required this.value,
    required this.createdAt,
    this.updatedAt,
  });

  factory NimbusRoutePreference.fromJson(Map<String, dynamic> json) {
    return NimbusRoutePreference(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'accelerate',
      targetType: json['targetType'] as String? ?? 'domain',
      value: json['value'] as String? ?? '',
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
    );
  }

  final String id;
  final String type;
  final String targetType;
  final String value;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get requiresConnection => type == 'accelerate';
}

class NimbusRoutePreferencesList {
  const NimbusRoutePreferencesList({required this.limit, required this.items});

  factory NimbusRoutePreferencesList.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return NimbusRoutePreferencesList(
      limit: _int(json['limit']) ?? 0,
      items: rawItems is List
          ? rawItems
                .map((item) => NimbusRoutePreference.fromJson(Map<String, dynamic>.from(item as Map? ?? const {})))
                .toList()
          : const [],
    );
  }

  final int limit;
  final List<NimbusRoutePreference> items;

  int get used => items.length;
}

class NimbusIssueReport {
  const NimbusIssueReport({
    required this.id,
    required this.status,
    required this.category,
    required this.message,
    required this.contact,
    required this.createdAt,
    this.resolvedAt,
  });

  factory NimbusIssueReport.fromJson(Map<String, dynamic> json) {
    return NimbusIssueReport(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      category: json['category'] as String?,
      message: json['message'] as String? ?? '',
      contact: json['contact'] as String?,
      createdAt: _dateTime(json['createdAt']),
      resolvedAt: _dateTime(json['resolvedAt']),
    );
  }

  final String id;
  final String status;
  final String? category;
  final String message;
  final String? contact;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
}

class NimbusAppVersionCheck {
  const NimbusAppVersionCheck({
    required this.platform,
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumVersion,
    required this.updateAvailable,
    required this.forceUpdate,
    this.downloadUrl,
    this.releaseNotes,
  });

  factory NimbusAppVersionCheck.fromJson(Map<String, dynamic> json) {
    return NimbusAppVersionCheck(
      platform: json['platform'] as String? ?? '',
      currentVersion: json['currentVersion'] as String? ?? '',
      latestVersion: json['latestVersion'] as String? ?? '',
      minimumVersion: json['minimumVersion'] as String? ?? '',
      updateAvailable: json['updateAvailable'] as bool? ?? false,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      downloadUrl: json['downloadUrl'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
    );
  }

  final String platform;
  final String currentVersion;
  final String latestVersion;
  final String minimumVersion;
  final bool updateAvailable;
  final bool forceUpdate;
  final String? downloadUrl;
  final String? releaseNotes;
}

class NimbusAnnouncement {
  const NimbusAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.language,
    this.startsAt,
    this.endsAt,
    this.updatedAt,
  });

  factory NimbusAnnouncement.fromJson(Map<String, dynamic> json) {
    return NimbusAnnouncement(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      startsAt: _dateTime(json['startsAt']),
      endsAt: _dateTime(json['endsAt']),
      updatedAt: _dateTime(json['updatedAt']),
    );
  }

  final String id;
  final String title;
  final String body;
  final String language;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? updatedAt;
}

class NimbusConnectTraffic {
  const NimbusConnectTraffic({required this.usedBytes, required this.remainingBytes, required this.quotaBytes});

  factory NimbusConnectTraffic.fromJson(Map<String, dynamic> json) {
    return NimbusConnectTraffic(
      usedBytes: _int(json['usedBytes']) ?? 0,
      remainingBytes: _int(json['remainingBytes']) ?? 0,
      quotaBytes: _int(json['quotaBytes']) ?? 0,
    );
  }

  final int usedBytes;
  final int remainingBytes;
  final int quotaBytes;
}

class NimbusRulesManifest {
  const NimbusRulesManifest({
    required this.publicRulesVersion,
    required this.userRulesVersion,
    required this.configVersion,
    required this.requiresUpdate,
    required this.publicRulesChanged,
    required this.userRulesChanged,
    required this.configChanged,
    this.downloadUrl,
  });

  factory NimbusRulesManifest.fromJson(Map<String, dynamic> json) {
    final changes = Map<String, dynamic>.from(json['changes'] as Map? ?? const {});
    return NimbusRulesManifest(
      publicRulesVersion: json['publicRulesVersion'] as String?,
      userRulesVersion: json['userRulesVersion'] as String? ?? '',
      configVersion: json['configVersion'] as String? ?? '',
      requiresUpdate: json['requiresUpdate'] as bool? ?? true,
      publicRulesChanged: changes['publicRules'] as bool? ?? true,
      userRulesChanged: changes['userRules'] as bool? ?? true,
      configChanged: changes['config'] as bool? ?? true,
      downloadUrl: json['downloadUrl'] as String?,
    );
  }

  final String? publicRulesVersion;
  final String userRulesVersion;
  final String configVersion;
  final bool requiresUpdate;
  final bool publicRulesChanged;
  final bool userRulesChanged;
  final bool configChanged;
  final String? downloadUrl;

  bool sameVersions(NimbusRulesManifest other) =>
      publicRulesVersion == other.publicRulesVersion &&
      userRulesVersion == other.userRulesVersion &&
      configVersion == other.configVersion;

  Map<String, dynamic> toJson() => {
    'publicRulesVersion': publicRulesVersion,
    'userRulesVersion': userRulesVersion,
    'configVersion': configVersion,
    'requiresUpdate': requiresUpdate,
    'changes': {'publicRules': publicRulesChanged, 'userRules': userRulesChanged, 'config': configChanged},
    'downloadUrl': downloadUrl,
  };
}

class NimbusRulePackageItem {
  const NimbusRulePackageItem({
    required this.pattern,
    required this.patternType,
    required this.action,
    this.kind = 'custom',
    this.sourceUrl,
    this.format,
    this.updateInterval,
  });

  factory NimbusRulePackageItem.fromJson(Map<String, dynamic> json) {
    final sourceUrl = json['sourceUrl'] as String?;
    return NimbusRulePackageItem(
      pattern: json['pattern'] as String? ?? '',
      patternType: json['patternType'] as String? ?? '',
      action: json['action'] as String? ?? '',
      kind: json['kind'] as String? ?? (sourceUrl?.isNotEmpty == true ? 'rule_set' : 'custom'),
      sourceUrl: sourceUrl,
      format: json['format'] as String?,
      updateInterval: json['updateInterval'] as String?,
    );
  }

  final String pattern;
  final String patternType;
  final String action;
  final String kind;
  final String? sourceUrl;
  final String? format;
  final String? updateInterval;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'pattern': pattern,
    'patternType': patternType,
    'action': action,
    'sourceUrl': sourceUrl,
    'format': format,
    'updateInterval': updateInterval,
  };
}

class NimbusRulesPackage {
  const NimbusRulesPackage({required this.manifest, required this.userRules, required this.publicRules, this.cachedAt});

  factory NimbusRulesPackage.fromJson(Map<String, dynamic> json) {
    return NimbusRulesPackage(
      manifest: NimbusRulesManifest.fromJson(Map<String, dynamic>.from(json['manifest'] as Map? ?? const {})),
      userRules: _ruleItems(json['userRules']),
      publicRules: _ruleItems(json['publicRules']),
      cachedAt: _dateTime(json['cachedAt']),
    );
  }

  final NimbusRulesManifest manifest;
  final List<NimbusRulePackageItem> userRules;
  final List<NimbusRulePackageItem> publicRules;
  final DateTime? cachedAt;

  NimbusRulesPackage copyWith({DateTime? cachedAt}) => NimbusRulesPackage(
    manifest: manifest,
    userRules: userRules,
    publicRules: publicRules,
    cachedAt: cachedAt ?? this.cachedAt,
  );

  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'userRules': userRules.map((item) => item.toJson()).toList(),
    'publicRules': publicRules.map((item) => item.toJson()).toList(),
    'cachedAt': cachedAt?.toUtc().toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  static List<NimbusRulePackageItem> _ruleItems(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => NimbusRulePackageItem.fromJson(Map<String, dynamic>.from(item))).toList();
  }
}

class NimbusConnectPlan {
  const NimbusConnectPlan({
    required this.planId,
    required this.sessionId,
    required this.expiresAt,
    required this.locationLabel,
    required this.heartbeatIntervalSeconds,
    required this.traffic,
    required this.singBoxConfigPatch,
    required this.rulesManifest,
    this.publicRulesVersion,
    this.profileContent,
  });

  factory NimbusConnectPlan.fromJson(Map<String, dynamic> json) {
    return NimbusConnectPlan(
      planId: json['planId'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      expiresAt: _dateTime(json['expiresAt']),
      locationLabel: json['locationLabel'] as String? ?? '',
      publicRulesVersion: json['publicRulesVersion'] as String?,
      rulesManifest: NimbusRulesManifest.fromJson(Map<String, dynamic>.from(json['rulesManifest'] as Map? ?? const {})),
      heartbeatIntervalSeconds: _int(json['heartbeatIntervalSeconds']) ?? 60,
      traffic: NimbusConnectTraffic.fromJson(Map<String, dynamic>.from(json['traffic'] as Map? ?? const {})),
      singBoxConfigPatch: Map<String, dynamic>.from(json['singBoxConfigPatch'] as Map? ?? const {}),
      profileContent: json['profileContent'] as String?,
    );
  }

  final String planId;
  final String sessionId;
  final DateTime? expiresAt;
  final String locationLabel;
  final String? publicRulesVersion;
  final NimbusRulesManifest rulesManifest;
  final int heartbeatIntervalSeconds;
  final NimbusConnectTraffic traffic;

  /// Complete Hiddify-compatible profile content. The client must not build a
  /// sing-box runtime config from [singBoxConfigPatch].
  final String? profileContent;
  final Map<String, dynamic> singBoxConfigPatch;
}

class NimbusConnectHeartbeat {
  const NimbusConnectHeartbeat({
    required this.ok,
    required this.disconnectRequired,
    required this.traffic,
    this.reason,
  });

  factory NimbusConnectHeartbeat.fromJson(Map<String, dynamic> json) {
    return NimbusConnectHeartbeat(
      ok: json['ok'] as bool? ?? false,
      disconnectRequired: json['disconnectRequired'] as bool? ?? false,
      reason: json['reason'] as String?,
      traffic: NimbusConnectTraffic.fromJson(Map<String, dynamic>.from(json['traffic'] as Map? ?? const {})),
    );
  }

  final bool ok;
  final bool disconnectRequired;
  final String? reason;
  final NimbusConnectTraffic traffic;
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
