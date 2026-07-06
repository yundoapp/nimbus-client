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
    this.errorMessage,
  });

  const NimbusAuthState.unauthenticated()
    : isAuthenticated = false,
      isLoading = false,
      isRestoring = false,
      session = null,
      me = null,
      errorMessage = null;

  const NimbusAuthState.authenticated({
    required NimbusAuthSession this.session,
    this.me,
    this.isLoading = false,
    this.isRestoring = false,
    this.errorMessage,
  }) : isAuthenticated = true;

  final bool isAuthenticated;
  final bool isLoading;
  final bool isRestoring;
  final NimbusAuthSession? session;
  final NimbusMe? me;
  final String? errorMessage;
}

class NimbusAuthController extends Notifier<NimbusAuthState> {
  NimbusAuthRepository get _repository => ref.read(nimbusAuthRepositoryProvider);

  @override
  NimbusAuthState build() {
    final session = _repository.readSession();
    if (session == null) return const NimbusAuthState.unauthenticated();
    Future.microtask(restore);
    return NimbusAuthState.authenticated(session: session, isRestoring: true);
  }

  Future<void> restore() async {
    final session = _repository.readSession();
    if (session == null) {
      state = const NimbusAuthState.unauthenticated();
      return;
    }

    try {
      final me = await _repository.fetchMe(session.accessToken);
      state = NimbusAuthState.authenticated(session: session, me: me);
    } catch (error) {
      if (!_repository.isUnauthorized(error)) {
        state = NimbusAuthState.authenticated(session: session, errorMessage: _repository.describeError(error));
        return;
      }

      try {
        final refreshedSession = await _repository.refresh(session);
        await _repository.saveSession(refreshedSession);
        final me = await _repository.fetchMe(refreshedSession.accessToken);
        state = NimbusAuthState.authenticated(session: refreshedSession, me: me);
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
      isLoading: true,
    );
    try {
      final session = await _repository.login(username: username, password: password);
      await _setAuthenticated(session);
      return true;
    } catch (error) {
      state = NimbusAuthState(isAuthenticated: false, errorMessage: _repository.describeError(error));
      return false;
    }
  }

  Future<bool> register({required String username, required String password, required bool acceptedTerms}) async {
    state = NimbusAuthState(
      isAuthenticated: state.isAuthenticated,
      session: state.session,
      me: state.me,
      isLoading: true,
    );
    try {
      final session = await _repository.register(username: username, password: password, acceptedTerms: acceptedTerms);
      await _setAuthenticated(session);
      return true;
    } catch (error) {
      state = NimbusAuthState(isAuthenticated: false, errorMessage: _repository.describeError(error));
      return false;
    }
  }

  Future<void> refreshMe() async {
    final session = state.session;
    if (session == null) return;
    try {
      final me = await _repository.fetchMe(session.accessToken);
      state = NimbusAuthState.authenticated(session: session, me: me);
    } catch (error) {
      if (_repository.isUnauthorized(error)) {
        await restore();
        return;
      }
      state = NimbusAuthState.authenticated(
        session: session,
        me: state.me,
        errorMessage: _repository.describeError(error),
      );
    }
  }

  Future<void> logout() async {
    final session = state.session;
    state = NimbusAuthState(
      isAuthenticated: state.isAuthenticated,
      session: state.session,
      me: state.me,
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
      errorMessage = _repository.describeError(error);
    }
    state = NimbusAuthState.authenticated(session: session, me: me, errorMessage: errorMessage);
  }
}
