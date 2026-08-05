import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/gen/hiddify_core_generated_bindings.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_network_capability_probe.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_privileged_helper.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_tunnel_config.dart';
import 'package:hiddify/hiddifycore/core_port.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/utils/custom_loggers.dart';

import 'package:loggy/loggy.dart';

import 'package:path/path.dart' as p;

final _logger = Loggy('YundoCoreFFI');
typedef StopFunc = Pointer<Utf8> Function();
typedef StopFuncDart = Pointer<Utf8> Function();

class CoreInterfaceDesktop extends CoreInterface with InfraLogger {
  CoreInterfaceDesktop({MacOSNetworkCapabilityProbe? macOSNetworkCapabilityProbe})
    : _macOSNetworkCapabilityProbe = macOSNetworkCapabilityProbe ?? MacOSNetworkCapabilityProbe();

  static final HiddifyCoreNativeLibrary _box = _gen();
  static const _privilegedHelper = MacOSPrivilegedHelper();
  final MacOSNetworkCapabilityProbe _macOSNetworkCapabilityProbe;

  Directories? _directories;
  String? _preparedSourcePath;
  String? _preparedConfigPath;
  String? _preparedIpv4FallbackConfigPath;
  String? _preparedIpv4FallbackConfig;
  int? _preparedSocksPort;
  String? _tunnelConfig;
  ClientChannel? _clientChannel;

  static HiddifyCoreNativeLibrary _gen() {
    String fullPath = "";
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      fullPath = "YundoCore";
    }
    if (Platform.isWindows) {
      fullPath = p.join(fullPath, "YundoCore.dll");
    } else if (Platform.isMacOS) {
      fullPath = p.join(fullPath, "YundoCore.dylib");
    } else {
      fullPath = p.join(fullPath, "YundoCore.so");
    }

    _logger.debug('Yundo native core library path: "$fullPath"');
    final lib = DynamicLibrary.open(fullPath);
    // final stopFunc = lib.lookup<NativeFunction<StopFunc>>('stop').asFunction<StopFunc>();
    // final errPtr2 = stopFunc();
    // final err = errPtr2.cast<Utf8>().toDartString();

    return HiddifyCoreNativeLibrary(lib);
  }

  Future<bool> isMusl() async {
    try {
      final result = await Process.run('ldd', ['--version']);
      return result.stdout.toString().toLowerCase().contains('musl');
    } catch (_) {
      return false;
    }
  }

  int _port = legacyDesktopCorePort;

  int get port => _port;
  static String generateRandomPassword(int length) {
    const characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(length, (_) => characters[random.nextInt(characters.length)]).join();
  }

  static final String secret = generateRandomPassword(100);

  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    _port = resolveDesktopCorePort(directories.baseDir.path);
    _directories = directories;
    // App resume can re-run setup while a connection is waiting for the
    // macOS network probe. Do not delete that operation's temporary configs.
    // Generate a random password for the grpc service
    // final errPtr2 = _box.stop();
    // final err = errPtr2.cast<Utf8>().toDartString();
    // throw Exception('stop: $err');
    const channelOption = ChannelCredentials.insecure();
    final helloChannel = ClientChannel(
      '127.0.0.1',
      port: port,
      options: const ChannelOptions(credentials: channelOption),
    );
    final helloClient = HelloClient(helloChannel);

    try {
      await helloClient.sayHello(HelloRequest(name: "test"));
      loggy.info("core is already started!");
    } catch (e) {
      //core is not started yet

      final errPtr = _box.setup(
        directories.baseDir.path.toNativeUtf8().cast(),
        directories.workingDir.path.toNativeUtf8().cast(),
        directories.tempDir.path.toNativeUtf8().cast(),
        SetupMode.GRPC_NORMAL_INSECURE.value,
        "127.0.0.1:$port".toNativeUtf8().cast(),
        secret.toNativeUtf8().cast(),
        0,
        debug ? 1 : 0,
      );
      final err = errPtr.cast<Utf8>().toDartString();

      if (err.isNotEmpty) {
        return err;
      }
      final res = await helloClient.sayHello(HelloRequest(name: "test"));
      loggy.info(res.toString());
    } finally {
      await helloChannel.shutdown();
    }
    await _refreshCoreClients();

    return "";
  }

  Future<void> _refreshCoreClients() async {
    final previousChannel = _clientChannel;
    final channel = ClientChannel(
      'localhost',
      port: port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        // credentials: ChannelCredentials.secure(
        //   password: secret,
        //   onBadCertificate: (certificate, host) => true,
        // ),
      ),
    );
    _clientChannel = channel;
    bgClient = fgClient = CoreClient(channel);
    await previousChannel?.shutdown();
  }

  @override
  Future<void> refreshClients() => _refreshCoreClients();

  @override
  Future<CoreStates?> waitForCoreState({Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    CoreStates? latestState;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await bgClient.coreInfoListener(Empty()).first.timeout(const Duration(milliseconds: 800));
        latestState = response.coreState;
        if (latestState == CoreStates.STARTED) return latestState;
      } catch (error) {
        loggy.debug('waiting for restarted core status: $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return latestState;
  }

  @override
  Future<CoreStatus> setupBackground(String path, String name) async {
    if (!Platform.isMacOS) return const CoreStatus.started();
    return _prepareMacOSTunnel(path);
  }

  @override
  String backgroundConfigPath(String originalPath) {
    if (Platform.isMacOS && _preparedSourcePath == originalPath && _preparedConfigPath != null) {
      return _preparedConfigPath!;
    }
    return originalPath;
  }

  @override
  Future<void> discardPreparedConfig() async {
    final tempDir = _directories?.tempDir.path;
    final preparedPaths = <String?>{
      _preparedConfigPath,
      _preparedIpv4FallbackConfigPath,
      if (tempDir != null) p.join(tempDir, 'yundo-user-core.json'),
      if (tempDir != null) p.join(tempDir, 'yundo-user-core-ipv4-fallback.json'),
    };
    _preparedSourcePath = null;
    _preparedConfigPath = null;
    _preparedIpv4FallbackConfigPath = null;
    _preparedIpv4FallbackConfig = null;
    _preparedSocksPort = null;
    for (final preparedPath in preparedPaths.nonNulls) {
      final file = File(preparedPath);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<CoreStatus> prepareRestart(String path, String name) async {
    if (!Platform.isMacOS) return const CoreStatus.started();
    return _prepareMacOSTunnel(path);
  }

  Future<CoreStatus> _prepareMacOSTunnel(String path) async {
    final directories = _directories;
    if (directories == null) {
      return const CoreStatus.stopped(alert: CoreAlert.startService, message: 'core directories are not ready');
    }
    try {
      final fullConfig = await generateFullConfig(path);
      final source = jsonDecode(fullConfig) as Map<String, dynamic>;
      final directRuleSetPath = p.join(
        p.dirname(p.dirname(Platform.resolvedExecutable)),
        'Frameworks',
        'App.framework',
        'Resources',
        'flutter_assets',
        'assets',
        'rules',
        'geoip-cn.srs',
      );
      final prepared = splitMacOSTunnelConfig(
        source,
        appProcessName: p.basename(Platform.resolvedExecutable),
        macOSDirectRouteRuleSetPath: directRuleSetPath,
      );
      final preparedPath = p.join(directories.tempDir.path, 'yundo-user-core.json');
      await File(preparedPath).writeAsString(prepared.userCoreConfig, flush: true);
      final fallback = splitMacOSTunnelConfig(
        source,
        appProcessName: p.basename(Platform.resolvedExecutable),
        macOSNetworkMode: MacOSTunnelNetworkMode.ipv4Fallback,
        macOSDirectRouteRuleSetPath: directRuleSetPath,
      );
      final fallbackPath = p.join(directories.tempDir.path, 'yundo-user-core-ipv4-fallback.json');
      await File(fallbackPath).writeAsString(fallback.userCoreConfig, flush: true);
      _preparedSourcePath = path;
      _preparedConfigPath = preparedPath;
      _preparedIpv4FallbackConfigPath = fallbackPath;
      _preparedIpv4FallbackConfig = fallback.userCoreConfig;
      _preparedSocksPort = prepared.socksPort;
      _tunnelConfig = prepared.tunnelConfig;
      bgClient = fgClient;
      return const CoreStatus.started();
    } on FormatException catch (error) {
      return CoreStatus.stopped(alert: CoreAlert.emptyConfiguration, message: error.message);
    } on MacOSTunnelConfigException catch (error) {
      return CoreStatus.stopped(alert: CoreAlert.emptyConfiguration, message: error.message);
    } catch (error) {
      return CoreStatus.stopped(alert: CoreAlert.startService, message: error.toString());
    }
  }

  @override
  Future<TunnelActivationPreparation> prepareTunnelActivation() async {
    if (!Platform.isMacOS) return (fallbackConfigPath: null, errorMessage: null, usedIpv4Fallback: false);
    final socksPort = _preparedSocksPort;
    final fallbackPath = _preparedIpv4FallbackConfigPath;
    if (socksPort == null || fallbackPath == null) {
      return (
        fallbackConfigPath: null,
        errorMessage: 'macOS adaptive network config is not prepared',
        usedIpv4Fallback: false,
      );
    }
    final fallbackFile = File(fallbackPath);
    if (!await fallbackFile.exists()) {
      final fallbackConfig = _preparedIpv4FallbackConfig;
      if (fallbackConfig == null) {
        return (
          fallbackConfigPath: null,
          errorMessage: 'macOS IPv4 fallback config is unavailable',
          usedIpv4Fallback: false,
        );
      }
      await fallbackFile.writeAsString(fallbackConfig, flush: true);
      loggy.warning('restored missing macOS IPv4 fallback config before network activation');
    }
    final capabilities = await _macOSNetworkCapabilityProbe.probe(proxyPort: socksPort);
    loggy.info(
      'macOS accelerated network capabilities '
      '(ipv4=${capabilities.ipv4Available}, ipv6=${capabilities.ipv6Available})',
    );
    if (!capabilities.ipv4Available) {
      loggy.warning('macOS IPv4 probe was inconclusive; continuing with the IPv4 fallback config');
      return (fallbackConfigPath: fallbackPath, errorMessage: null, usedIpv4Fallback: true);
    }
    return (
      fallbackConfigPath: capabilities.ipv6Available ? null : fallbackPath,
      errorMessage: null,
      usedIpv4Fallback: !capabilities.ipv6Available,
    );
  }

  @override
  Future<CoreStatus> activateTunnel() async {
    if (!Platform.isMacOS) return const CoreStatus.started();
    final config = _tunnelConfig;
    if (config == null) {
      return const CoreStatus.stopped(alert: CoreAlert.startService, message: 'tunnel config is not ready');
    }
    try {
      await _privilegedHelper.startTunnel(config);
      return const CoreStatus.started();
    } on PlatformException catch (error) {
      final detail = error.message?.trim();
      loggy.warning(
        'macOS privileged helper is not available: ${error.code}'
        '${detail == null || detail.isEmpty ? '' : ': $detail'}',
      );
      return CoreStatus.stopped(alert: CoreAlert.requestVPNPermission, message: detail ?? error.code);
    } catch (error) {
      return CoreStatus.stopped(alert: CoreAlert.startService, message: error.toString());
    }
  }

  @override
  Future<bool> restart(String path, String name) async {
    return false;
  }

  @override
  Future<bool> stop() async {
    if (!Platform.isMacOS) return false;
    try {
      await _privilegedHelper.stopTunnel();
      return true;
    } catch (error) {
      loggy.warning('failed to stop macOS privileged helper: $error');
      return false;
    } finally {
      await discardPreparedConfig();
      _tunnelConfig = null;
    }
  }
}
