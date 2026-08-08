import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/widget/shimmer_skeleton.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ActiveProxyDelayIndicator extends HookConsumerWidget with InfraLogger {
  const ActiveProxyDelayIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final activeProxy = ref.watch(activeProxyNotifierProvider);
    final isConnected = ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
    final coreRestartSignal = ref.watch(coreRestartSignalProvider);
    final theme = Theme.of(context);
    final activeProxyValue = activeProxy.valueOrNull;

    useEffect(() {
      if (!isConnected || activeProxyValue == null) return null;
      final timer = Timer(const Duration(milliseconds: 250), () async {
        try {
          await ref.read(activeProxyNotifierProvider.notifier).refreshActiveDelay();
        } catch (e) {
          loggy.warning("initial active outbound URL test failed", e);
        }
      });
      return timer.cancel;
    }, [isConnected, coreRestartSignal, activeProxyValue?.tag, activeProxyValue?.groupSelectedTagDisplay]);

    final delay = isConnected ? activeProxy.valueOrNull?.urlTestDelay ?? 0 : 0;
    final timeout = delay > 65000;
    final isTesting = isConnected && delay == 0 && activeProxy is! AsyncError;

    return Center(
      child: InkWell(
        onTap: () async {
          try {
            await ref.read(activeProxyNotifierProvider.notifier).refreshActiveDelay(userInitiated: true);
          } catch (e) {
            // Handle error here
            loggy.error("Error during URL test: $e");
          }
        },
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.wifi_1_24_regular),
                const Gap(8),
                SizedBox(
                  width: 72,
                  height: 24,
                  child: Center(
                    child: delay > 0
                        ? Text.rich(
                            semanticsLabel: timeout
                                ? t.pages.proxies.delay.timeout
                                : t.pages.proxies.delay.result(delay: delay),
                            TextSpan(
                              children: [
                                if (timeout)
                                  TextSpan(
                                    text: t.common.timeout,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.error,
                                    ),
                                  )
                                else ...[
                                  TextSpan(
                                    text: delay.toString(),
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const TextSpan(text: " ms"),
                                ],
                              ],
                            ),
                          )
                        : isTesting
                        ? Semantics(
                            label: t.pages.proxies.delay.testing,
                            child: const ShimmerSkeleton(width: 48, height: 18),
                          )
                        : Semantics(
                            label: t.common.unknown,
                            child: Text(
                              '-- ms',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
