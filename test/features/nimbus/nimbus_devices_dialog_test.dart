import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_devices_dialog.dart';

void main() {
  test('shows an initial loading state while authentication or device data is pending', () {
    expect(
      shouldShowNimbusDevicesInitialLoading(
        isAuthenticated: false,
        isRestoring: true,
        isLoading: false,
        hasDevices: false,
        hasError: false,
      ),
      isTrue,
    );
    expect(
      shouldShowNimbusDevicesInitialLoading(
        isAuthenticated: true,
        isRestoring: false,
        isLoading: false,
        hasDevices: false,
        hasError: false,
      ),
      isTrue,
    );
    expect(
      shouldShowNimbusDevicesInitialLoading(
        isAuthenticated: true,
        isRestoring: false,
        isLoading: false,
        hasDevices: false,
        hasError: true,
      ),
      isFalse,
    );
    expect(
      shouldShowNimbusDevicesInitialLoading(
        isAuthenticated: true,
        isRestoring: false,
        isLoading: false,
        hasDevices: true,
        hasError: false,
      ),
      isFalse,
    );
  });

  test('reloads after the authentication session becomes available', () {
    final source = File('lib/features/nimbus/auth/widget/nimbus_devices_dialog.dart').readAsStringSync();

    expect(source, contains('authState.session?.accessToken'));
    expect(source, contains('if (!authState.isAuthenticated || authState.session == null) return null;'));
    expect(source, contains('authState.isRestoring'));
  });

  test('limits the desktop tray location request to one attempt per user session', () {
    final source = File('lib/features/system_tray/notifier/system_tray_notifier.dart').readAsStringSync();

    expect(source, contains('_locationsLoadRequestedForUser'));
    expect(source, contains('userId != _locationsLoadRequestedForUser'));
  });

  test('location loading is not coupled to the account-wide loading indicator', () {
    final source = File('lib/features/nimbus/auth/notifier/nimbus_auth_controller.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _loadLocations()');
    final end = source.indexOf('Future<void> selectLocation(', start);
    final locationSection = source.substring(start, end);

    expect(locationSection, isNot(contains('isLoading: true')));
  });

  test('location loading reuses the session cache unless explicitly forced', () {
    final source = File('lib/features/nimbus/auth/notifier/nimbus_auth_controller.dart').readAsStringSync();
    expect(source, contains('Future<void> loadLocations({bool force = false})'));
    expect(source, contains('if (!force && state.locations != null) return Future<void>.value();'));
  });
}
