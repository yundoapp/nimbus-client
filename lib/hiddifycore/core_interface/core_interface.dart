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
