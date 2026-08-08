import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/singbox/model/core_status.dart';

typedef TunnelActivationPreparation = ({String? fallbackConfigPath, String? errorMessage, bool usedIpv4Fallback});

class CoreInterface {
  late CoreClient fgClient;
  late CoreClient bgClient;

  Future<String> setup(Directories directories, bool debug, int mode) async {
    return "";
  }

  Future<CoreStatus> setupBackground(String path, String name) async {
    return const CoreStarted();
  }

  String backgroundConfigPath(String originalPath) => originalPath;

  /// Returns the effective config owned by the platform tunnel layer. On
  /// macOS this is the privileged Helper config; other platforms keep routing
  /// in the main Core config and return null.
  String? preparedRoutingConfig() => null;

  Future<List<String>> ruleSetDiagnosticMessages() async => const [];

  Future<String> generateFullConfig(String path) async {
    final response = await fgClient.generateConfig(GenerateConfigRequest(path: path));
    if (response.configContent.trim().isEmpty) {
      throw StateError('core returned an empty full configuration');
    }
    return response.configContent;
  }

  Future<void> discardPreparedConfig() async {}

  Future<CoreStatus> prepareRestart(String path, String name) async {
    return const CoreStarted();
  }

  Future<CoreStatus> activateTunnel() async {
    return const CoreStarted();
  }

  Future<TunnelActivationPreparation> prepareTunnelActivation() async {
    return (fallbackConfigPath: null, errorMessage: null, usedIpv4Fallback: false);
  }

  /// Rebinds the local gRPC client after the native core has been restarted.
  /// Desktop core restarts can terminate active HTTP/2 streams by design.
  Future<void> refreshClients() async {}

  /// Reconciles a user core that is still running while the application-level
  /// connection state is stopped. Returns an error detail when cleanup cannot
  /// be verified and a new core must not be started.
  Future<String?> reconcileBeforeStart() async => null;

  /// Returns the latest core state, or null on platforms without a desktop
  /// gRPC status stream.
  Future<CoreStates?> waitForCoreState({Duration timeout = const Duration(seconds: 5)}) async => null;

  /// Confirms that the native core has actually reached its stopped state.
  /// Platforms without a persistent desktop status channel are stopped by
  /// their platform service and therefore return true by default.
  Future<bool> waitForCoreStopped({Duration timeout = const Duration(seconds: 5)}) async => true;

  Future<bool> restart(String path, String name) async {
    return false;
  }

  Future<bool> stop() async {
    return false;
  }

  Future<bool> isBgClientAvailable() async {
    return true;
  }

  bool isSingleChannel() {
    // return true;
    return fgClient == bgClient;
  }

  Future<bool> resetTunnel() async {
    return false;
  }

  Future<bool> isActiveFg() async {
    return true;
  }

  Future<bool> isActiveBg() async {
    return true;
  }

  bool isInitialized() {
    try {
      final client = bgClient;
      return client == bgClient;
    } catch (_) {
      return false;
    }
  }
}
