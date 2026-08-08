import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';

Future<T> runNimbusAuthenticatedRead<T>({
  required NimbusAuthSession session,
  required Future<T> Function(NimbusAuthSession session) request,
  required bool Function(Object error) isUnauthorized,
  required Future<bool> Function(NimbusAuthSession rejectedSession) refreshAfterUnauthorized,
  required NimbusAuthSession? Function() currentSession,
}) async {
  try {
    return await request(session);
  } catch (error) {
    if (!isUnauthorized(error)) rethrow;

    await refreshAfterUnauthorized(session);
    final refreshedSession = currentSession();
    if (refreshedSession == null || refreshedSession.accessToken == session.accessToken) rethrow;
    return request(refreshedSession);
  }
}
