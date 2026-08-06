const nimbusAuthRestoringPath = '/auth/restoring';
const nimbusAuthLoginPath = '/auth/login';
const nimbusHomePath = '/home';

String? resolveNimbusAuthRedirect({
  required bool isRestoring,
  required bool isAuthenticated,
  required String matchedLocation,
}) {
  final isRestoringRoute = matchedLocation == nimbusAuthRestoringPath;
  final isAuthRoute = matchedLocation.startsWith('/auth/');

  if (isRestoring) {
    return isRestoringRoute ? null : nimbusAuthRestoringPath;
  }
  if (isRestoringRoute) {
    return isAuthenticated ? nimbusHomePath : nimbusAuthLoginPath;
  }
  if (!isAuthenticated && !isAuthRoute) return nimbusAuthLoginPath;
  if (isAuthenticated && isAuthRoute) return nimbusHomePath;
  return null;
}
