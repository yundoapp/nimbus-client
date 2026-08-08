import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_authenticated_read.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final nimbusRoutePreferencesProvider = FutureProvider.autoDispose<NimbusRoutePreferencesList?>((ref) {
  final authState = ref.watch(nimbusAuthControllerProvider);
  if (authState.isRestoring) return null;

  final session = authState.session;
  if (session == null) return null;

  final repository = ref.read(nimbusAuthRepositoryProvider);
  final authController = ref.read(nimbusAuthControllerProvider.notifier);
  return runNimbusAuthenticatedRead(
    session: session,
    request: repository.fetchRoutePreferences,
    isUnauthorized: repository.isUnauthorized,
    refreshAfterUnauthorized: authController.refreshAfterUnauthorized,
    currentSession: () => authController.currentSession,
  );
});
