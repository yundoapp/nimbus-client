import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/nimbus_auth_redirect.dart';

void main() {
  group('resolveNimbusAuthRedirect', () {
    test('shows the restoring page before exposing authentication forms', () {
      expect(
        resolveNimbusAuthRedirect(isRestoring: true, isAuthenticated: false, matchedLocation: '/home'),
        nimbusAuthRestoringPath,
      );
      expect(
        resolveNimbusAuthRedirect(isRestoring: true, isAuthenticated: false, matchedLocation: '/auth/login'),
        nimbusAuthRestoringPath,
      );
      expect(
        resolveNimbusAuthRedirect(isRestoring: true, isAuthenticated: false, matchedLocation: nimbusAuthRestoringPath),
        isNull,
      );
    });

    test('leaves restoring for home after automatic sign-in succeeds', () {
      expect(
        resolveNimbusAuthRedirect(isRestoring: false, isAuthenticated: true, matchedLocation: nimbusAuthRestoringPath),
        nimbusHomePath,
      );
    });

    test('leaves restoring for login when no valid session exists', () {
      expect(
        resolveNimbusAuthRedirect(isRestoring: false, isAuthenticated: false, matchedLocation: nimbusAuthRestoringPath),
        nimbusAuthLoginPath,
      );
    });

    test('keeps the existing authenticated and unauthenticated boundaries', () {
      expect(
        resolveNimbusAuthRedirect(isRestoring: false, isAuthenticated: false, matchedLocation: '/settings'),
        nimbusAuthLoginPath,
      );
      expect(
        resolveNimbusAuthRedirect(isRestoring: false, isAuthenticated: true, matchedLocation: '/auth/register'),
        nimbusHomePath,
      );
      expect(
        resolveNimbusAuthRedirect(isRestoring: false, isAuthenticated: false, matchedLocation: '/auth/login'),
        isNull,
      );
      expect(resolveNimbusAuthRedirect(isRestoring: false, isAuthenticated: true, matchedLocation: '/home'), isNull);
    });
  });
}
