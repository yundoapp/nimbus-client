import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_session_store.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const nimbusApiBaseUrl = String.fromEnvironment('NIMBUS_API_BASE_URL', defaultValue: 'http://localhost:4000/api/v1');

final nimbusAuthRepositoryProvider = Provider<NimbusAuthRepository>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider).requireValue;
  return NimbusAuthRepository(
    preferences: preferences,
    appInfo: ref.watch(appInfoProvider).requireValue,
    sessionStore: !kIsWeb && Platform.isMacOS ? const MacOSKeychainNimbusSessionStore() : null,
  );
});

class NimbusAuthRepository {
  NimbusAuthRepository({
    required SharedPreferences preferences,
    required AppInfoEntity appInfo,
    NimbusSessionStore? sessionStore,
    Dio? dio,
  }) : _preferences = preferences,
       _appInfo = appInfo,
       _sessionStore = sessionStore ?? PreferencesNimbusSessionStore(preferences, _sessionKey),
       _migrateLegacySession = sessionStore != null,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: _normalizeApiBaseUrl(nimbusApiBaseUrl),
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 20),
               headers: const {'accept': 'application/json', 'content-type': 'application/json'},
             ),
           );

  static const _sessionKey = 'nimbus.auth.session';
  static const _deviceIdKey = 'nimbus.auth.device_id';
  static const _selectedLocationKey = 'nimbus.connect.selected_location';
  static const _rulesPackageKeyPrefix = 'nimbus.rules.package.';

  final SharedPreferences _preferences;
  final AppInfoEntity _appInfo;
  final NimbusSessionStore _sessionStore;
  final bool _migrateLegacySession;
  final Dio _dio;

  Future<NimbusAuthSession?> readSession() async {
    var raw = await _sessionStore.read();
    if ((raw == null || raw.isEmpty) && _migrateLegacySession) {
      final legacy = _preferences.getString(_sessionKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _sessionStore.write(legacy);
        await _preferences.remove(_sessionKey);
        raw = legacy;
      }
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      return NimbusAuthSession.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      await _sessionStore.delete();
      await _preferences.remove(_sessionKey);
      return null;
    }
  }

  Future<void> saveSession(NimbusAuthSession session) async {
    await _sessionStore.write(session.encode());
    await _preferences.remove(_sessionKey);
  }

  Future<void> clearSession() async {
    await _sessionStore.delete();
    await _preferences.remove(_sessionKey);
  }

  Future<NimbusAuthSession> register({
    required String username,
    required String password,
    required bool acceptedTerms,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/register',
      data: {'username': username, 'password': password, 'acceptedTerms': acceptedTerms, 'device': _devicePayload()},
    );
    return NimbusAuthSession.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<NimbusAuthSession> login({required String username, required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/login',
      data: {'username': username, 'password': password, 'device': _devicePayload()},
    );
    return NimbusAuthSession.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<NimbusAuthSession> completePasswordReset({
    required String username,
    required String temporaryPassword,
    required String newPassword,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/complete-password-reset',
      data: {
        'username': username,
        'temporaryPassword': temporaryPassword,
        'newPassword': newPassword,
        'device': _devicePayload(),
      },
    );
    return NimbusAuthSession.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<void> changePassword({
    required NimbusAuthSession session,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.post<void>(
      'account/change-password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
  }

  Future<NimbusAuthSession> refresh(NimbusAuthSession session) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/refresh',
      data: {'refreshToken': session.refreshToken},
    );
    final data = Map<String, dynamic>.from(response.data ?? const {});
    return session.copyWith(
      accessToken: data['accessToken'] as String? ?? session.accessToken,
      refreshToken: data['refreshToken'] as String? ?? session.refreshToken,
    );
  }

  Future<NimbusMe> fetchMe(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'me',
      options: Options(headers: {'authorization': 'Bearer $accessToken'}),
    );
    return NimbusMe.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<void> redeemActivationCode({required NimbusAuthSession session, required String code}) async {
    await _dio.post<void>(
      'activation/redeem',
      data: {'code': code},
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
  }

  Future<NimbusDevicesList> fetchDevices(NimbusAuthSession session) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'devices',
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    return NimbusDevicesList.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<NimbusDeviceRemoveResult> removeDevice({required NimbusAuthSession session, required String deviceId}) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      'devices/$deviceId',
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    return NimbusDeviceRemoveResult.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  String readSelectedLocationCode() {
    final code = _preferences.getString(_selectedLocationKey);
    return code == null || code.isEmpty ? 'auto' : code;
  }

  Future<void> saveSelectedLocationCode(String code) async {
    await _preferences.setString(_selectedLocationKey, code.isEmpty ? 'auto' : code);
  }

  NimbusRulesPackage? readRulesPackage(String userId) {
    final raw = _preferences.getString('$_rulesPackageKeyPrefix$userId');
    if (raw == null || raw.isEmpty) return null;
    try {
      return NimbusRulesPackage.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRulesPackage(String userId, NimbusRulesPackage rulesPackage) async {
    await _preferences.setString('$_rulesPackageKeyPrefix$userId', rulesPackage.encode());
  }

  Future<NimbusRulesManifest> fetchRulesManifest({
    required NimbusAuthSession session,
    NimbusRulesManifest? localManifest,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'rules/manifest',
      queryParameters: {
        if (localManifest?.publicRulesVersion != null) 'publicRulesVersion': localManifest!.publicRulesVersion,
        if (localManifest?.userRulesVersion.isNotEmpty ?? false) 'userRulesVersion': localManifest!.userRulesVersion,
        if (localManifest?.configVersion.isNotEmpty ?? false) 'configVersion': localManifest!.configVersion,
      },
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    return NimbusRulesManifest.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<NimbusRulesPackage> fetchRulesPackage(NimbusAuthSession session) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'rules/package',
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    return NimbusRulesPackage.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<NimbusLocationsList> fetchLocations(NimbusAuthSession session) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'locations',
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    return NimbusLocationsList.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<NimbusRoutePreferencesList> fetchRoutePreferences(NimbusAuthSession session) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'route-preferences',
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    return NimbusRoutePreferencesList.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<NimbusRoutePreference> createRoutePreference({
    required NimbusAuthSession session,
    required String type,
    required String input,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'route-preferences',
      data: {'type': type, 'input': input},
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    final data = Map<String, dynamic>.from(response.data ?? const {});
    return NimbusRoutePreference.fromJson(Map<String, dynamic>.from(data['item'] as Map? ?? const {}));
  }

  Future<NimbusRoutePreference> updateRoutePreference({
    required NimbusAuthSession session,
    required String id,
    required String type,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'route-preferences/${Uri.encodeComponent(id)}',
      data: {'type': type},
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    final data = Map<String, dynamic>.from(response.data ?? const {});
    return NimbusRoutePreference.fromJson(Map<String, dynamic>.from(data['item'] as Map? ?? const {}));
  }

  Future<void> deleteRoutePreference({required NimbusAuthSession session, required String id}) async {
    await _dio.delete<void>(
      'route-preferences/${Uri.encodeComponent(id)}',
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
  }

  Future<NimbusIssueReport> submitIssueReport({
    required NimbusAuthSession session,
    required String description,
    required Map<String, Object?> diagnostics,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'issue-reports',
      data: {'description': description, 'diagnostics': diagnostics},
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    final data = Map<String, dynamic>.from(response.data ?? const {});
    return NimbusIssueReport.fromJson(Map<String, dynamic>.from(data['item'] as Map? ?? const {}));
  }

  Future<NimbusAppVersionCheck> checkAppVersion({required String platform, required String version}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'app-version/check',
      queryParameters: {'platform': platform, 'version': version},
    );
    return NimbusAppVersionCheck.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<NimbusAnnouncement?> fetchCurrentAnnouncement({required String platform, required String language}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'announcements/current',
      queryParameters: {'platform': platform, 'language': language},
    );
    final data = Map<String, dynamic>.from(response.data ?? const {});
    final item = data['item'];
    if (item is! Map) return null;
    final announcement = NimbusAnnouncement.fromJson(Map<String, dynamic>.from(item));
    return announcement.id.isEmpty || announcement.title.isEmpty || announcement.body.isEmpty ? null : announcement;
  }

  Future<NimbusConnectPlan> createConnectPlan({
    required NimbusAuthSession session,
    required String selectedLocation,
    required String appVersion,
    required NimbusRulesManifest rulesManifest,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'connect/plan',
      data: {
        'deviceId': session.device.deviceId,
        'selectedLocation': selectedLocation,
        'appVersion': appVersion,
        'rulesVersion': rulesManifest.publicRulesVersion,
        'publicRulesVersion': rulesManifest.publicRulesVersion,
        'userRulesVersion': rulesManifest.userRulesVersion,
        'configVersion': rulesManifest.configVersion,
      },
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    return NimbusConnectPlan.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<void> reportConnectResult({
    required NimbusAuthSession session,
    required NimbusConnectPlan plan,
    required String status,
    String? failureCode,
  }) async {
    await _dio.post<void>(
      'connect/result',
      data: {
        'sessionId': plan.sessionId,
        'planId': plan.planId,
        'status': status,
        if (failureCode != null) 'failureCode': failureCode,
      },
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
  }

  Future<NimbusConnectHeartbeat> sendConnectHeartbeat({
    required NimbusAuthSession session,
    required NimbusConnectPlan plan,
    required String status,
    required int uploadBytesDelta,
    required int downloadBytesDelta,
    required String appVersion,
    String? rulesVersion,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'connect/heartbeat',
      data: {
        'sessionId': plan.sessionId,
        'planId': plan.planId,
        'deviceId': session.device.deviceId,
        'status': status,
        'uploadBytesDelta': uploadBytesDelta,
        'downloadBytesDelta': downloadBytesDelta,
        'appVersion': appVersion,
        'rulesVersion': rulesVersion,
      },
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
    return NimbusConnectHeartbeat.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<void> reportConnectDisconnect({
    required NimbusAuthSession session,
    required NimbusConnectPlan plan,
    required String reason,
  }) async {
    await _dio.post<void>(
      'connect/disconnect',
      data: {'sessionId': plan.sessionId, 'planId': plan.planId, 'reason': reason},
      options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
    );
  }

  Future<void> logout(NimbusAuthSession session) async {
    try {
      await _dio.post<void>(
        'auth/logout',
        data: {'refreshToken': session.refreshToken},
        options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
      );
    } on DioException catch (e) {
      if (!isUnauthorized(e)) rethrow;
    } finally {
      await clearSession();
    }
  }

  bool isUnauthorized(Object error) {
    return error is DioException && error.response?.statusCode == 401;
  }

  String describeError(Object error, Translations t) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final mappedMessage = _describeApiCode(data['code'], t);
        if (mappedMessage != null) return mappedMessage;
        return t.nimbus.common.operationFailed;
      }
      if (error.type == DioExceptionType.connectionError) return t.nimbus.common.serverUnavailable;
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return t.nimbus.common.requestTimeout;
      }
      return t.nimbus.common.requestFailed;
    }
    return t.nimbus.common.operationFailed;
  }

  String? apiErrorCode(Object error) {
    if (error is! DioException) return null;
    final data = error.response?.data;
    if (data is! Map) return null;
    final code = data['code'];
    return code is String && code.isNotEmpty ? code : null;
  }

  String? _describeApiCode(Object? rawCode, Translations t) {
    if (rawCode is! String || rawCode.isEmpty) return null;
    return switch (rawCode) {
      'AUTH_INVALID_CREDENTIALS' => t.nimbus.apiError.invalidCredentials,
      'AUTH_CURRENT_PASSWORD_INVALID' => t.nimbus.changePassword.currentPasswordInvalid,
      'AUTH_PASSWORD_CHANGED' => t.nimbus.changePassword.passwordChangedElsewhere,
      'AUTH_PASSWORD_CHANGE_REQUIRED' => t.nimbus.apiError.passwordChangeRequired,
      'AUTH_PASSWORD_CHANGE_NOT_REQUIRED' => t.nimbus.apiError.passwordChangeNotRequired,
      'AUTH_PASSWORD_MUST_DIFFER' => t.nimbus.apiError.passwordMustDiffer,
      'AUTH_WEAK_PASSWORD' => t.nimbus.auth.weakPassword,
      'AUTH_REGISTRATION_DISABLED' => t.nimbus.apiError.registrationDisabled,
      'AUTH_USERNAME_TAKEN' => t.nimbus.apiError.usernameTaken,
      'RATE_LIMIT_USER_LOGIN_ACCOUNT' => t.nimbus.apiError.loginRateLimited,
      'RATE_LIMIT_USER_LOGIN_IP' => t.nimbus.apiError.networkLoginRateLimited,
      'ACCOUNT_DISABLED' => t.nimbus.apiError.accountDisabled,
      'DEVICE_LIMIT_REACHED' || 'DEVICE_NEW_LOGIN_DISABLED' => t.nimbus.apiError.deviceLimitReached,
      'ACTIVATION_CODE_INVALID' || 'ACTIVATION_CODE_NOT_FOUND' => t.nimbus.apiError.activationCodeInvalid,
      'ACTIVATION_CODE_USED' => t.nimbus.apiError.activationCodeUsed,
      'ACTIVATION_CODE_REVOKED' => t.nimbus.apiError.activationCodeRevoked,
      'PLAN_NOT_FOUND' || 'PLAN_DISABLED' => t.nimbus.apiError.planUnavailable,
      'NO_ACTIVE_SUBSCRIPTION' => t.nimbus.errors.noPlan,
      'SUBSCRIPTION_EXPIRED' => t.nimbus.apiError.subscriptionExpired,
      'TRAFFIC_EXCEEDED' => t.nimbus.errors.trafficExceeded,
      'NO_AVAILABLE_NODE' => t.nimbus.apiError.noAvailableLocation,
      'CONNECT_PLAN_EXPIRED' || 'CONNECT_SESSION_CLOSED' => t.nimbus.errors.sessionEnded,
      'ROUTE_PREFERENCE_LIMIT_REACHED' => t.nimbus.routePreferences.limitReached,
      'ROUTE_PREFERENCE_ALREADY_ACCELERATED' => t.nimbus.routePreferences.alreadyInCategory(
        category: t.nimbus.routePreferences.requiresConnection,
      ),
      'ROUTE_PREFERENCE_ALREADY_DIRECT' => t.nimbus.routePreferences.alreadyInCategory(
        category: t.nimbus.routePreferences.directConnection,
      ),
      'ROUTE_PREFERENCE_CONFLICT' => t.nimbus.apiError.routePreferenceConflict,
      'ROUTE_TARGET_INVALID' => t.nimbus.apiError.routeTargetInvalid,
      'ISSUE_REPORT_ALREADY_OPEN' => t.nimbus.apiError.issueReportAlreadyOpen,
      _ => null,
    };
  }

  Map<String, String> _devicePayload() {
    return {
      'deviceId': _deviceId,
      'platform': _platform,
      'deviceName': _deviceName,
      'appVersion': '${_appInfo.version}+${_appInfo.buildNumber}',
    };
  }

  String get _deviceId {
    final existing = _preferences.getString(_deviceIdKey);
    if (existing != null && existing.length >= 8) return existing;
    const uuid = Uuid();
    final created = uuid.v4();
    _preferences.setString(_deviceIdKey, created);
    return created;
  }

  String get _platform {
    if (kIsWeb) return 'unknown';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  String get _deviceName {
    if (kIsWeb) return 'Web';
    final hostname = Platform.localHostname.trim();
    if (hostname.isNotEmpty) return hostname;
    return switch (_platform) {
      'macos' => 'Mac',
      'windows' => 'Windows PC',
      'ios' => 'iPhone',
      'android' => 'Android',
      _ => 'Unknown device',
    };
  }
}

String _normalizeApiBaseUrl(String baseUrl) => baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
