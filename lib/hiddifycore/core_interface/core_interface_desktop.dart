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
import 'package:hiddify/hiddifycore/core_interface/macos_privileged_helper.dart';
import 'package:hiddify/hiddifycore/core_interface/macos_tunnel_config.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/utils/custom_loggers.dart';

import 'package:loggy/loggy.dart';

import 'package:path/path.dart' as p;

final _logger = Loggy('HiddifyCoreFFI');
typedef StopFunc = Pointer<Utf8> Function();
typedef StopFuncDart = Pointer<Utf8> Function();

class CoreInterfaceDesktop extends CoreInterface with InfraLogger {
  static final HiddifyCoreNativeLibrary _box = _gen();
  static const _privilegedHelper = MacOSPrivilegedHelper();

  Directories? _directories;
  String? _preparedSourcePath;
  String? _preparedConfigPath;
  String? _tunnelConfig;

  static HiddifyCoreNativeLibrary _gen() {
    String fullPath = "";
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      fullPath = "hiddify-core";
    }
    if (Platform.isWindows) {
      fullPath = p.join(fullPath, "hiddify-core.dll");
    } else if (Platform.isMacOS) {
      fullPath = p.join(fullPath, "hiddify-core.dylib");
    } else {
      fullPath = p.join(fullPath, "hiddify-core.so");
    }

    _logger.debug('hiddify-core native libs path: "$fullPath"');
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

  final port = 17078;
  static String generateRandomPassword(int length) {
    const characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(length, (_) => characters[random.nextInt(characters.length)]).join();
  }

  static final String secret = generateRandomPassword(100);

  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    _directories = directories;
    await discardPreparedConfig();
    // Generate a random password for the grpc service
    // final errPtr2 = _box.stop();
    // final err = errPtr2.cast<Utf8>().toDartString();
    // throw Exception('stop: $err');
    const channelOption = ChannelCredentials.insecure();
    final helloClient = HelloClient(
      ClientChannel(
        '127.0.0.1',
        port: port,
        options: const ChannelOptions(credentials: channelOption),
      ),
    );

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
    }
    bgClient = fgClient = CoreClient(
      ClientChannel(
        'localhost',
        port: port,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
          // credentials: ChannelCredentials.secure(
          //   password: secret,
          //   onBadCertificate: (certificate, host) => true,
          // ),
        ),
      ),
    );

    return "";
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
    final preparedPath =
        _preparedConfigPath ??
        (_directories == null ? null : p.join(_directories!.tempDir.path, 'yundo-user-core.json'));
    _preparedSourcePath = null;
    _preparedConfigPath = null;
    if (preparedPath == null) return;
    final file = File(preparedPath);
    if (await file.exists()) {
      await file.delete();
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
      final source = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final prepared = splitMacOSTunnelConfig(source, appProcessName: p.basename(Platform.resolvedExecutable));
      final preparedPath = p.join(directories.tempDir.path, 'yundo-user-core.json');
      await File(preparedPath).writeAsString(prepared.userCoreConfig, flush: true);
      _preparedSourcePath = path;
      _preparedConfigPath = preparedPath;
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
      loggy.warning('macOS privileged helper is not available: ${error.code}');
      return CoreStatus.stopped(alert: CoreAlert.requestSystemPrivilege, message: error.code);
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
