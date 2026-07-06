import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final nimbusAppVersionControllerProvider = NotifierProvider<NimbusAppVersionController, NimbusAppVersionState>(
  NimbusAppVersionController.new,
);

class NimbusAppVersionState {
  const NimbusAppVersionState({this.isChecking = false, this.hasChecked = false, this.result, this.errorMessage});

  final bool isChecking;
  final bool hasChecked;
  final NimbusAppVersionCheck? result;
  final String? errorMessage;

  bool get forceUpdate => result?.forceUpdate ?? false;
  bool get updateAvailable => result?.updateAvailable ?? false;
}

class NimbusAppVersionController extends Notifier<NimbusAppVersionState> {
  NimbusAuthRepository get _repository => ref.read(nimbusAuthRepositoryProvider);

  @override
  NimbusAppVersionState build() => const NimbusAppVersionState();

  Future<NimbusAppVersionCheck?> check({bool force = false}) async {
    if (state.isChecking) return state.result;
    if (state.hasChecked && !force) return state.result;

    state = NimbusAppVersionState(isChecking: true, hasChecked: state.hasChecked, result: state.result);
    try {
      final appInfo = ref.read(appInfoProvider).requireValue;
      final result = await _repository.checkAppVersion(
        platform: _platformForApi(appInfo.operatingSystem),
        version: appInfo.version,
      );
      state = NimbusAppVersionState(hasChecked: true, result: result);
      return result;
    } catch (error) {
      state = NimbusAppVersionState(
        hasChecked: true,
        result: state.result,
        errorMessage: _repository.describeError(error),
      );
      return state.result;
    }
  }

  String _platformForApi(String operatingSystem) {
    return switch (operatingSystem) {
      'macos' => 'macos',
      'windows' => 'windows',
      'ios' => 'ios',
      'android' => 'android',
      _ => 'macos',
    };
  }
}
