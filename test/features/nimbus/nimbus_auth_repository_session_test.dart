import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('桌面默认存储会保留登录会话', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = NimbusAuthRepository(
      preferences: preferences,
      appInfo: const AppInfoEntity(
        name: 'Yundo',
        version: '1.0.1',
        buildNumber: '10006',
        release: Release.general,
        operatingSystem: 'windows',
        operatingSystemVersion: 'test',
        environment: Environment.prod,
      ),
    );

    await repository.saveSession(_session);

    final restored = await repository.readSession();
    expect(restored?.user.username, 'tester');
    expect(restored?.accessToken, 'test-access-token');
    expect(preferences.getString('nimbus.auth.session'), isNotNull);
  });
}

const _session = NimbusAuthSession(
  accessToken: 'test-access-token',
  refreshToken: 'test-refresh-token',
  user: NimbusUser(id: 'user-id', username: 'tester', status: 'active'),
  device: NimbusDevice(id: 'device-ref', deviceId: 'device-id', platform: 'windows', deviceName: 'Test PC'),
);
