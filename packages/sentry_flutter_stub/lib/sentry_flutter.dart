import 'dart:async';

import 'package:flutter/widgets.dart';

typedef BeforeSendCallback = FutureOr<SentryEvent?> Function(SentryEvent event, Hint hint);

enum SentryLevel { debug, info, warning, error, fatal }

abstract class Integration<T> {
  void call(Hub hub, T options);

  FutureOr<void> close();
}

class Hub {
  Future<void> captureEvent(SentryEvent event, {StackTrace? stackTrace, Hint? hint}) async {}

  Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint}) async {}
}

class SentryFlutter {
  static final Hub _hub = Hub();

  static Future<void> init(void Function(SentryOptions options) configureOptions) async {
    final options = SentryOptions();
    configureOptions(options);
    for (final integration in options.integrations) {
      integration(_hub, options);
    }
  }
}

class Sentry {
  static Future<void> captureException(Object exception, {StackTrace? stackTrace, Hint? hint}) async {}

  static Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint}) async {}

  static Future<void> close() async {}
}

class SentryOptions {
  String dsn = "";
  bool debug = false;
  bool enableNativeCrashHandling = false;
  bool enableNdkScopeSync = false;
  String serverName = "";
  bool attachThreads = false;
  double? tracesSampleRate;
  bool enableUserInteractionTracing = false;
  BeforeSendCallback? beforeSend;
  final SdkVersion sdk = SdkVersion();
  final List<Integration<SentryOptions>> integrations = [];

  void addIntegration(Integration<SentryOptions> integration) {
    integrations.add(integration);
  }
}

class SdkVersion {
  final List<String> integrationNames = [];

  void addIntegration(String name) {
    integrationNames.add(name);
  }
}

class SentryEvent {
  const SentryEvent({
    this.timestamp,
    this.logger,
    this.level,
    this.message,
    this.throwable,
    this.extra,
    this.user,
  });

  final DateTime? timestamp;
  final String? logger;
  final SentryLevel? level;
  final SentryMessage? message;
  final dynamic throwable;
  final Map<String, Object>? extra;
  final SentryUser? user;

  SentryEvent copyWith({
    DateTime? timestamp,
    String? logger,
    SentryLevel? level,
    SentryMessage? message,
    dynamic throwable,
    Map<String, Object>? extra,
    SentryUser? user,
  }) {
    return SentryEvent(
      timestamp: timestamp ?? this.timestamp,
      logger: logger ?? this.logger,
      level: level ?? this.level,
      message: message ?? this.message,
      throwable: throwable ?? this.throwable,
      extra: extra ?? this.extra,
      user: user ?? this.user,
    );
  }
}

class SentryMessage {
  const SentryMessage(this.formatted);

  final String formatted;
}

class SentryUser {
  const SentryUser({this.email, this.username, this.ipAddress});

  final String? email;
  final String? username;
  final String? ipAddress;
}

class Breadcrumb {
  const Breadcrumb({this.category, this.type, this.timestamp, this.level, this.message, this.data});

  final String? category;
  final String? type;
  final DateTime? timestamp;
  final SentryLevel? level;
  final String? message;
  final Map<String, dynamic>? data;
}

class Hint {
  const Hint([this.data = const {}]);

  factory Hint.withMap(Map<String, Object?> data) => Hint(data);

  final Map<String, Object?> data;
}

class TypeCheckHint {
  static const String record = "record";
}

class SentryUserInteractionWidget extends StatelessWidget {
  const SentryUserInteractionWidget({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
