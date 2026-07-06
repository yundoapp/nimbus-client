import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const nimbusApiBaseUrl = String.fromEnvironment('NIMBUS_API_BASE_URL', defaultValue: 'http://localhost:4000/api/v1');

final nimbusAuthRepositoryProvider = Provider<NimbusAuthRepository>((ref) {
  return NimbusAuthRepository(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    appInfo: ref.watch(appInfoProvider).requireValue,
  );
});

class NimbusAuthRepository {
  NimbusAuthRepository({required SharedPreferences preferences, required AppInfoEntity appInfo, Dio? dio})
    : _preferences = preferences,
      _appInfo = appInfo,
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

  final SharedPreferences _preferences;
  final AppInfoEntity _appInfo;
  final Dio _dio;

  NimbusAuthSession? readSession() {
    final raw = _preferences.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return NimbusAuthSession.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(NimbusAuthSession session) async {
    await _preferences.setString(_sessionKey, session.encode());
  }

  Future<void> clearSession() async {
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
    return NimbusRoutePreference.fromJson(Map<String, dynamic>.from(response.data ?? const {}));
  }

  Future<void> deleteRoutePreference({required NimbusAuthSession session, required String id}) async {
    await _dio.delete<void>(
      'route-preferences/${Uri.encodeComponent(id)}',
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

  String describeError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (error.type == DioExceptionType.connectionError) return '无法连接服务器，请稍后重试';
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return '连接超时，请稍后重试';
      }
      return error.message ?? '请求失败，请稍后重试';
    }
    return '操作失败，请稍后重试';
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
