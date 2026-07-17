import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('认证恢复中不渲染首页 shell', () {
    final container = ProviderContainer(
      overrides: [
        activeBreakpointNotifierProvider.overrideWith(_MobileBreakpointNotifier.new),
        nimbusAuthControllerProvider.overrideWith(_RestoringAuthController.new),
      ],
    );
    addTearDown(container.dispose);

    final config = container.read(routingConfigNotifierProvider);

    expect(config.routes, hasLength(1));
    expect(config.routes.single, isA<GoRoute>().having((route) => route.path, 'path', '/home'));
    expect(config.routes.whereType<StatefulShellRoute>(), isEmpty);
  });

  test('认证恢复结束后提供登录路由和首页 shell', () {
    final container = ProviderContainer(
      overrides: [
        activeBreakpointNotifierProvider.overrideWith(_MobileBreakpointNotifier.new),
        nimbusAuthControllerProvider.overrideWith(_UnauthenticatedAuthController.new),
      ],
    );
    addTearDown(container.dispose);

    final config = container.read(routingConfigNotifierProvider);
    final authRoutes = config.routes.whereType<GoRoute>().map((route) => route.name);

    expect(authRoutes, containsAll(['nimbusLogin', 'nimbusRegister']));
    expect(config.routes.whereType<StatefulShellRoute>(), hasLength(1));
  });
}

class _MobileBreakpointNotifier extends ActiveBreakpointNotifier {
  @override
  Breakpoints? build() => Breakpoints.mobile;
}

class _RestoringAuthController extends NimbusAuthController {
  @override
  NimbusAuthState build() => const NimbusAuthState(isAuthenticated: false, isRestoring: true);
}

class _UnauthenticatedAuthController extends NimbusAuthController {
  @override
  NimbusAuthState build() => const NimbusAuthState.unauthenticated();
}
