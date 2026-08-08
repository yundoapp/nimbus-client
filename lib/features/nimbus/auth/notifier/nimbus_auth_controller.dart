import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final nimbusAuthControllerProvider = NotifierProvider<NimbusAuthController, NimbusAuthState>(NimbusAuthController.new);

enum NimbusLoginResult { authenticated, passwordChangeRequired, failed }

class NimbusAuthState {
  const NimbusAuthState({
    required this.isAuthenticated,
    this.isLoading = false,
    this.isRestoring = false,
    this.session,
    this.me,
    this.devices,
    this.locations,
    this.selectedLocationCode = 'auto',
    this.errorMessage,
  });

  const NimbusAuthState.unauthenticated()
    : isAuthenticated = false,
      isLoading = false,
      isRestoring = false,
      session = null,
      me = null,
      devices = null,
      locations = null,
      selectedLocationCode = 'auto',
      errorMessage = null;

  const NimbusAuthState.authenticated({
    required NimbusAuthSession this.session,
    this.me,
    this.devices,
    this.locations,
    this.selectedLocationCode = 'auto',
    this.isLoading = false,
    this.isRestoring = false,
    this.errorMessage,
  }) : isAuthenticated = true;

  final bool isAuthenticated;
  final bool isLoading;
  final bool isRestoring;
  final NimbusAuthSession? session;
  final NimbusMe? me;
  final NimbusDevicesList? devices;
  final NimbusLocationsList? locations;
  final String selectedLocationCode;
  final String? errorMessage;
}

class NimbusAuthController extends Notifier<NimbusAuthState> with AppLogger {
  Future<NimbusAuthSession?>? _refreshInFlight;
  Future<void>? _refreshMeInFlight;
  Future<void>? _loadLocationsInFlight;

  NimbusAuthRepository get _repository => ref.read(nimbusAuthRepositoryProvider);
  Translations get _t => ref.read(translationsProvider).requireValue;
  NimbusAuthSession? get currentSession => state.session;

  String _describeError(Object error) => _repository.describeError(error, _t);

  @override
  NimbusAuthState build() {
    final selectedLocationCode = _repository.readSelectedLocationCode();
    Future.microtask(restore);
    return NimbusAuthState(isAuthenticated: false, selectedLocationCode: selectedLocationCode, isRestoring: true);
  }

  Future<void> restore() async {
    NimbusAuthSession? session;
    try {
      session = await _repository.readSession();
    } catch (error, stackTrace) {
      loggy.error('failed to read Nimbus authentication session', error, stackTrace);
      state = const NimbusAuthState.unauthenticated();
      return;
    }
    if (session == null) {
      state = const NimbusAuthState.unauthenticated();
      return;
    }

    try {
      final me = await _repository.fetchMe(session.accessToken);
      await _completeLegacyIntro();
      state = NimbusAuthState.authenticated(
        session: session,
        me: me,
        devices: state.devices,
        locations: state.locations,
        selectedLocationCode: state.selectedLocationCode,
      );
    } catch (error) {
      if (!_repository.isUnauthorized(error)) {
        await _completeLegacyIntro();
        state = NimbusAuthState.authenticated(
          session: session,
          devices: state.devices,
          locations: state.locations,
          selectedLocationCode: state.selectedLocationCode,
          errorMessage: _describeError(error),
        );
        return;
      }
      await _refreshSession(session);
    }
  }

  Future<NimbusLoginResult> login({required String username, required String password}) async {
    state = NimbusAuthState(
      isAuthenticated: state.isAuthenticated,
      session: state.session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      isLoading: true,
    );
    try {
      final session = await _repository.login(username: username, password: password);
      await _setAuthenticated(session);
      return NimbusLoginResult.authenticated;
    } catch (error) {
      if (_repository.apiErrorCode(error) == 'AUTH_PASSWORD_CHANGE_REQUIRED') {
        state = const NimbusAuthState.unauthenticated();
        return NimbusLoginResult.passwordChangeRequired;
      }
      state = NimbusAuthState(isAuthenticated: false, errorMessage: _describeError(error));
      return NimbusLoginResult.failed;
    }
  }

  Future<bool> completePasswordReset({
    required String username,
    required String temporaryPassword,
    required String newPassword,
  }) async {
    state = NimbusAuthState(
      isAuthenticated: state.isAuthenticated,
      session: state.session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      isLoading: true,
    );
    try {
      final session = await _repository.completePasswordReset(
        username: username,
        temporaryPassword: temporaryPassword,
        newPassword: newPassword,
      );
      await _setAuthenticated(session);
      return true;
    } catch (error) {
      state = NimbusAuthState(isAuthenticated: false, errorMessage: _describeError(error));
      return false;
    }
  }

  Future<bool> register({required String username, required String password, required bool acceptedTerms}) async {
    state = NimbusAuthState(
      isAuthenticated: state.isAuthenticated,
      session: state.session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      isLoading: true,
    );
    try {
      final session = await _repository.register(username: username, password: password, acceptedTerms: acceptedTerms);
      await _setAuthenticated(session);
      return true;
    } catch (error) {
      state = NimbusAuthState(isAuthenticated: false, errorMessage: _describeError(error));
      return false;
    }
  }

  Future<void> refreshMe() {
    final active = _refreshMeInFlight;
    if (active != null) return active;

    final session = state.session;
    if (session == null) return Future<void>.value();

    final future = _refreshMe(session);
    _refreshMeInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshMeInFlight, future)) _refreshMeInFlight = null;
    });
  }

  Future<void> _refreshMe(NimbusAuthSession session) async {
    state = NimbusAuthState.authenticated(
      session: session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      isLoading: true,
    );
    try {
      final me = await _repository.fetchMe(session.accessToken);
      state = NimbusAuthState.authenticated(
        session: session,
        me: me,
        devices: state.devices,
        locations: state.locations,
        selectedLocationCode: state.selectedLocationCode,
      );
    } catch (error) {
      if (_repository.isUnauthorized(error)) {
        await refreshAfterUnauthorized(session);
        return;
      }
      state = NimbusAuthState.authenticated(
        session: session,
        me: state.me,
        devices: state.devices,
        locations: state.locations,
        selectedLocationCode: state.selectedLocationCode,
        errorMessage: _describeError(error),
      );
    }
  }

  Future<void> loadDevices() async {
    final session = state.session;
    if (session == null) return;
    state = NimbusAuthState.authenticated(
      session: session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      isLoading: true,
    );
    try {
      final devices = await _repository.fetchDevices(session);
      state = NimbusAuthState.authenticated(
        session: session,
        me: state.me,
        devices: devices,
        locations: state.locations,
        selectedLocationCode: state.selectedLocationCode,
      );
    } catch (error) {
      if (_repository.isUnauthorized(error)) {
        await refreshAfterUnauthorized(session);
        return;
      }
      state = NimbusAuthState.authenticated(
        session: session,
        me: state.me,
        devices: state.devices,
        locations: state.locations,
        selectedLocationCode: state.selectedLocationCode,
        errorMessage: _describeError(error),
      );
    }
  }

  Future<void> loadLocations({bool force = false}) {
    if (!force && state.locations != null) return Future<void>.value();
    final active = _loadLocationsInFlight;
    if (active != null) return active;

    final future = _loadLocations();
    _loadLocationsInFlight = future;
    return future.whenComplete(() {
      if (identical(_loadLocationsInFlight, future)) _loadLocationsInFlight = null;
    });
  }

  Future<void> _loadLocations() async {
    final session = state.session;
    if (session == null) return;
    try {
      final locations = await _repository.fetchLocations(session);
      final hasSelected = locations.items.any((item) => item.code == state.selectedLocationCode);
      final selectedLocationCode = hasSelected ? state.selectedLocationCode : 'auto';
      if (!hasSelected) await _repository.saveSelectedLocationCode(selectedLocationCode);
      state = NimbusAuthState.authenticated(
        session: session,
        me: state.me,
        devices: state.devices,
        locations: locations,
        selectedLocationCode: selectedLocationCode,
      );
    } catch (error) {
      if (_repository.isUnauthorized(error)) {
        await refreshAfterUnauthorized(session);
        return;
      }
      state = NimbusAuthState.authenticated(
        session: session,
        me: state.me,
        devices: state.devices,
        locations: state.locations,
        selectedLocationCode: state.selectedLocationCode,
        errorMessage: _describeError(error),
      );
    }
  }

  Future<void> selectLocation(NimbusLocation location) async {
    await _repository.saveSelectedLocationCode(location.code);
    final session = state.session;
    if (session == null) {
      state = NimbusAuthState(isAuthenticated: false, selectedLocationCode: location.code);
      return;
    }
    state = NimbusAuthState.authenticated(
      session: session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: location.code,
    );
  }

  Future<bool> removeDevice(String deviceId) async {
    final session = state.session;
    if (session == null) return false;
    state = NimbusAuthState.authenticated(
      session: session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      isLoading: true,
    );
    try {
      final result = await _repository.removeDevice(session: session, deviceId: deviceId);
      if (result.deletedCurrentDevice) {
        await _repository.clearSession();
        state = const NimbusAuthState.unauthenticated();
      } else {
        final devices = await _repository.fetchDevices(session);
        state = NimbusAuthState.authenticated(
          session: session,
          me: state.me,
          devices: devices,
          locations: state.locations,
          selectedLocationCode: state.selectedLocationCode,
        );
      }
      return result.success;
    } catch (error) {
      if (_repository.isUnauthorized(error)) {
        await refreshAfterUnauthorized(session);
      } else {
        state = NimbusAuthState.authenticated(
          session: session,
          me: state.me,
          devices: state.devices,
          locations: state.locations,
          selectedLocationCode: state.selectedLocationCode,
          errorMessage: _describeError(error),
        );
      }
      return false;
    }
  }

  Future<bool> redeemActivationCode(String code) async {
    final session = state.session;
    if (session == null) {
      state = const NimbusAuthState.unauthenticated();
      return false;
    }
    state = NimbusAuthState.authenticated(
      session: session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      isLoading: true,
    );
    try {
      await _repository.redeemActivationCode(session: session, code: code);
      final me = await _repository.fetchMe(session.accessToken);
      state = NimbusAuthState.authenticated(
        session: session,
        me: me,
        devices: state.devices,
        locations: state.locations,
        selectedLocationCode: state.selectedLocationCode,
      );
      return true;
    } catch (error) {
      if (_repository.isUnauthorized(error)) {
        await refreshAfterUnauthorized(session);
      } else {
        state = NimbusAuthState.authenticated(
          session: session,
          me: state.me,
          devices: state.devices,
          locations: state.locations,
          selectedLocationCode: state.selectedLocationCode,
          errorMessage: _describeError(error),
        );
      }
      return false;
    }
  }

  Future<void> logout() async {
    final session = state.session;
    state = NimbusAuthState(
      isAuthenticated: state.isAuthenticated,
      session: state.session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      isLoading: true,
    );
    if (session != null) {
      await _repository.logout(session);
    } else {
      await _repository.clearSession();
    }
    state = const NimbusAuthState.unauthenticated();
  }

  void clearError() {
    state = NimbusAuthState(
      isAuthenticated: state.isAuthenticated,
      isLoading: state.isLoading,
      isRestoring: state.isRestoring,
      session: state.session,
      me: state.me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
    );
  }

  Future<bool> refreshAfterUnauthorized(NimbusAuthSession rejectedSession) async {
    final currentSession = state.session;
    if (!state.isAuthenticated || currentSession == null) return false;

    if (currentSession.accessToken != rejectedSession.accessToken) {
      return true;
    }

    await _refreshSession(currentSession);
    return state.isAuthenticated;
  }

  Future<NimbusAuthSession?> _refreshSession(NimbusAuthSession session) async {
    final active = _refreshInFlight;
    if (active != null) return active;

    final future = _performSessionRefresh(session);
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<NimbusAuthSession?> _performSessionRefresh(NimbusAuthSession session) async {
    NimbusAuthSession refreshedSession;
    try {
      refreshedSession = await _repository.refresh(session);
    } catch (error, stackTrace) {
      if (_repository.isUnauthorized(error)) {
        await _signOutAfterInvalidRefresh();
        return null;
      }
      loggy.warning('failed to refresh Nimbus authentication session', error, stackTrace);
      state = NimbusAuthState.authenticated(
        session: session,
        me: state.me,
        devices: state.devices,
        locations: state.locations,
        selectedLocationCode: state.selectedLocationCode,
        errorMessage: _describeError(error),
      );
      return null;
    }

    final persistenceError = await _persistSession(refreshedSession);
    NimbusMe? me = state.me;
    String? errorMessage = persistenceError;
    try {
      me = await _repository.fetchMe(refreshedSession.accessToken);
    } catch (error) {
      if (_repository.isUnauthorized(error)) {
        await _signOutAfterInvalidRefresh();
        return null;
      }
      errorMessage ??= _describeError(error);
    }

    state = NimbusAuthState.authenticated(
      session: refreshedSession,
      me: me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      errorMessage: errorMessage,
    );
    return refreshedSession;
  }

  Future<String?> _persistSession(NimbusAuthSession session) async {
    try {
      await _repository.saveSession(session);
      return null;
    } catch (error, stackTrace) {
      loggy.error('failed to persist Nimbus authentication session', error, stackTrace);
      return _t.nimbus.auth.sessionNotSaved;
    }
  }

  Future<void> _signOutAfterInvalidRefresh() async {
    try {
      await _repository.clearSession();
    } catch (error, stackTrace) {
      loggy.warning('failed to clear invalid Nimbus authentication session', error, stackTrace);
    }
    state = const NimbusAuthState.unauthenticated();
  }

  Future<void> _setAuthenticated(NimbusAuthSession session) async {
    NimbusMe? me;
    String? errorMessage = await _persistSession(session);
    try {
      me = await _repository.fetchMe(session.accessToken);
    } catch (error) {
      errorMessage ??= _describeError(error);
    }
    await _completeLegacyIntro();
    state = NimbusAuthState.authenticated(
      session: session,
      me: me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      errorMessage: errorMessage,
    );
  }

  Future<void> _completeLegacyIntro() async {
    if (!ref.read(Preferences.introCompleted)) {
      await ref.read(Preferences.introCompleted.notifier).update(true);
    }
  }
}
