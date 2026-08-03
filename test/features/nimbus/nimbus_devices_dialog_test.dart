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
}
