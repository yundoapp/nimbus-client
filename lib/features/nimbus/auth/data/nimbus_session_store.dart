import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class NimbusSessionStore {
  Future<void> delete();

  Future<String?> read();

  Future<void> write(String value);
}

class PreferencesNimbusSessionStore implements NimbusSessionStore {
  const PreferencesNimbusSessionStore(this.preferences, this.key);

  final SharedPreferences preferences;
  final String key;

  @override
  Future<void> delete() => preferences.remove(key);

  @override
  Future<String?> read() async => preferences.getString(key);

  @override
  Future<void> write(String value) => preferences.setString(key, value);
}

class MacOSKeychainNimbusSessionStore implements NimbusSessionStore {
  const MacOSKeychainNimbusSessionStore({MethodChannel channel = const MethodChannel('yundo_macos_secure_session')})
    : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> delete() => _channel.invokeMethod<void>('delete');

  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');

  @override
  Future<void> write(String value) => _channel.invokeMethod<void>('write', {'value': value});
}
