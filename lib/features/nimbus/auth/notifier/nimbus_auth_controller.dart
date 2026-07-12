import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final nimbusAuthControllerProvider = NotifierProvider<NimbusAuthController, NimbusAuthState>(NimbusAuthController.new);

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

class NimbusAuthController extends Notifier<NimbusAuthState> {
  NimbusAuthRepository get _repository => ref.read(nimbusAuthRepositoryProvider);
  Translations get _t => ref.read(translationsProvider).requireValue;

  String _describeError(Object error) => _repository.describeError(error, _t);

  @override
  NimbusAuthState build() {
    final selectedLocationCode = _repository.readSelectedLocationCode();
    Future.microtask(restore);
    return NimbusAuthState(isAuthenticated: false, selectedLocationCode: selectedLocationCode, isRestoring: true);
  }

  Future<void> restore() async {
    final session = await _repository.readSession();
    if (session == null) {
      state = const NimbusAuthState.unauthenticated();
      return;
    }

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
      if (!_repository.isUnauthorized(error)) {
        state = NimbusAuthState.authenticated(
          session: session,
          devices: state.devices,
          locations: state.locations,
          selectedLocationCode: state.selectedLocationCode,
          errorMessage: _describeError(error),
        );
        return;
      }

      try {
        final refreshedSession = await _repository.refresh(session);
        await _repository.saveSession(refreshedSession);
        final me = await _repository.fetchMe(refreshedSession.accessToken);
        state = NimbusAuthState.authenticated(
          session: refreshedSession,
          me: me,
          devices: state.devices,
          locations: state.locations,
          selectedLocationCode: state.selectedLocationCode,
        );
      } catch (_) {
        await _repository.clearSession();
        state = const NimbusAuthState.unauthenticated();
      }
    }
  }

  Future<bool> login({required String username, required String password}) async {
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

  Future<void> refreshMe() async {
    final session = state.session;
    if (session == null) return;
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
        await restore();
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
        await restore();
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

  Future<void> loadLocations() async {
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
        await restore();
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
        await restore();
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
        await restore();
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

  Future<void> _setAuthenticated(NimbusAuthSession session) async {
    await _repository.saveSession(session);
    NimbusMe? me;
    String? errorMessage;
    try {
      me = await _repository.fetchMe(session.accessToken);
    } catch (error) {
      errorMessage = _describeError(error);
    }
    state = NimbusAuthState.authenticated(
      session: session,
      me: me,
      devices: state.devices,
      locations: state.locations,
      selectedLocationCode: state.selectedLocationCode,
      errorMessage: errorMessage,
    );
  }
}
