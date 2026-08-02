import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:win32_registry/win32_registry.dart';

typedef NimbusDeviceIdReader = String? Function();
typedef NimbusDeviceIdWriter = void Function(String value);
typedef NimbusMachineIdFactory = String Function(String machineGuid);

class NimbusDeviceIdentity {
  NimbusDeviceIdentity({
    required SharedPreferences preferences,
    bool Function()? isWindows,
    NimbusDeviceIdReader? persistentIdReader,
    NimbusDeviceIdWriter? persistentIdWriter,
    NimbusDeviceIdReader? machineGuidReader,
    NimbusMachineIdFactory? machineIdFactory,
    String Function()? randomIdFactory,
  }) : _preferences = preferences,
       _isWindows = isWindows ?? (() => Platform.isWindows),
       _persistentIdReader = persistentIdReader ?? _readWindowsDeviceId,
       _persistentIdWriter = persistentIdWriter ?? _writeWindowsDeviceId,
       _machineGuidReader = machineGuidReader ?? _readWindowsMachineGuid,
       _machineIdFactory = machineIdFactory ?? _deriveWindowsDeviceId,
       _randomIdFactory = randomIdFactory ?? const Uuid().v4;

  static const preferencesKey = 'nimbus.auth.device_id';
  static const _registryPath = r'Software\Yundo\Client';
  static const _registryValueName = 'DeviceId';

  final SharedPreferences _preferences;
  final bool Function() _isWindows;
  final NimbusDeviceIdReader _persistentIdReader;
  final NimbusDeviceIdWriter _persistentIdWriter;
  final NimbusDeviceIdReader _machineGuidReader;
  final NimbusMachineIdFactory _machineIdFactory;
  final String Function() _randomIdFactory;

  String resolve() {
    if (!_isWindows()) {
      return _preferencesId ?? _createAndSaveRandomId();
    }

    final persistent = _validId(_persistentIdReader());
    if (persistent != null) {
      _preferences.setString(preferencesKey, persistent);
      return persistent;
    }

    final existing = _preferencesId;
    if (existing != null) {
      _persistWindowsId(existing);
      return existing;
    }

    final machineGuid = _machineGuidReader()?.trim();
    final created = machineGuid != null && machineGuid.isNotEmpty
        ? _machineIdFactory(machineGuid.toLowerCase())
        : _randomIdFactory();
    _preferences.setString(preferencesKey, created);
    _persistWindowsId(created);
    return created;
  }

  String? get _preferencesId => _validId(_preferences.getString(preferencesKey));

  String _createAndSaveRandomId() {
    final created = _randomIdFactory();
    _preferences.setString(preferencesKey, created);
    return created;
  }

  void _persistWindowsId(String value) {
    try {
      _persistentIdWriter(value);
    } catch (_) {
      // Machine-derived fallback still keeps the identity stable when HKCU is read-only.
    }
  }

  static String? _validId(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.length < 8 || normalized.length > 128) return null;
    return RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(normalized) ? normalized : null;
  }

  static String _deriveWindowsDeviceId(String machineGuid) {
    return const Uuid().v5(Namespace.url.value, 'app.yundo.client/windows/$machineGuid');
  }

  static String? _readWindowsDeviceId() {
    RegistryKey? key;
    try {
      key = Registry.openPath(RegistryHive.currentUser, path: _registryPath);
      return key.getStringValue(_registryValueName);
    } catch (_) {
      return null;
    } finally {
      key?.close();
    }
  }

  static void _writeWindowsDeviceId(String value) {
    final root = Registry.currentUser;
    try {
      final key = root.createKey(_registryPath);
      try {
        key.createValue(RegistryValue.string(_registryValueName, value));
      } finally {
        key.close();
      }
    } finally {
      root.close();
    }
  }

  static String? _readWindowsMachineGuid() {
    RegistryKey? key;
    try {
      key = Registry.openPath(RegistryHive.localMachine, path: r'Software\Microsoft\Cryptography');
      return key.getStringValue('MachineGuid');
    } catch (_) {
      return null;
    } finally {
      key?.close();
    }
  }
}
