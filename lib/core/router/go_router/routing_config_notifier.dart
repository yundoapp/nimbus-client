import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/custom_transition.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_auth_page.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'routing_config_notifier.g.dart';

final branchesScope = <String, FocusScopeNode>{
  'home': FocusScopeNode(),
  'settings': FocusScopeNode(),
  'about': FocusScopeNode(),
};

final loadingConfig = RoutingConfig(
  routes: <RouteBase>[GoRoute(path: '/home', builder: (context, state) => const _RoutingLoadingPage())],
);

String getNameOfBranch(bool isMobileBreakpoint, bool showProfilesAction, int index) =>
    (isMobileBreakpoint ? ['home', 'settings'] : ['home', 'settings', 'about'])[index];

int getIndexOfBranch(bool isMobileBreakpoint, bool showProfilesAction, String name) =>
    (isMobileBreakpoint ? ['home', 'settings'] : ['home', 'settings', 'about']).indexOf(name);

bool shouldShowProfilesAction() => false;

@Riverpod(keepAlive: true)
class RoutingConfigNotifier extends _$RoutingConfigNotifier {
  @override
  RoutingConfig build() {
    final isMobileBreakpoint = ref.watch(isMobileBreakpointProvider);
    if (isMobileBreakpoint == null) return loadingConfig;
    final authState = ref.watch(
      nimbusAuthControllerProvider.select(
        (state) => (isAuthenticated: state.isAuthenticated, isRestoring: state.isRestoring),
      ),
    );
    if (authState.isRestoring) return loadingConfig;

    return RoutingConfig(
      redirect: (_, state) {
        final isAuthRoute = state.matchedLocation.startsWith('/auth/');
        if (!authState.isAuthenticated && !isAuthRoute) return '/auth/login';
        if (authState.isAuthenticated && isAuthRoute) return '/home';
        return null;
      },
      routes: <RouteBase>[
        GoRoute(
          name: 'nimbusLogin',
          path: '/auth/login',
          builder: (_, _) => const NimbusAuthPage(initialMode: NimbusAuthMode.login),
        ),
        GoRoute(
          name: 'nimbusRegister',
          path: '/auth/register',
          builder: (_, _) => const NimbusAuthPage(initialMode: NimbusAuthMode.register),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => MyAdaptiveLayout(
            navigationShell: navigationShell,
            isMobileBreakpoint: isMobileBreakpoint,
            showProfilesAction: false,
          ),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'home',
                  path: '/home',
                  builder: (_, _) => FocusScope(node: branchesScope['home'], child: const HomePage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'settings',
                  path: '/settings',
                  builder: (context, _) => FocusScope(
                    node: branchesScope['settings'],
                    child: PopScope(
                      canPop: false,
                      onPopInvokedWithResult: (_, _) => context.goNamed('home'),
                      child: const SettingsPage(),
                    ),
                  ),
                  routes: <GoRoute>[
                    GoRoute(
                      name: 'general',
                      path: 'general',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.slide, state.pageKey, const GeneralPage()),
                    ),
                    GoRoute(
                      name: 'logs',
                      path: 'logs',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.slide, state.pageKey, const LogsPage()),
                    ),
                    if (isMobileBreakpoint)
                      GoRoute(
                        name: 'about',
                        path: 'about',
                        pageBuilder: (_, state) =>
                            customTransition(TransitionType.slide, state.pageKey, const AboutPage()),
                      ),
                  ],
                ),
              ],
            ),
            if (!isMobileBreakpoint)
              StatefulShellBranch(
                routes: <GoRoute>[
                  GoRoute(
                    name: 'about',
                    path: '/about',
                    builder: (_, _) => FocusScope(node: branchesScope['about'], child: const AboutPage()),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _RoutingLoadingPage extends StatelessWidget {
  const _RoutingLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
