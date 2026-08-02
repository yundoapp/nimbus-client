import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/animated_text.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _yundoLogoColor = Color(0xFF4F67AA);

// TODO: rewrite
class ConnectionButton extends HookConsumerWidget {
  const ConnectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final connectionStatus = ref.watch(nimbusOwnedConnectionStatusProvider);
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull;
    // final animationController = useAnimationController(
    //   duration: const Duration(seconds: 1),
    // )..repeat(reverse: true); // Ensure the animation loops indefinitely

    //   // Listen to the animation's value
    //   final animationValue = useAnimation(Tween<double>(begin: 0.8, end: 1).animate(animationController));

    //   // useEffect(() {
    //   //   if (true) {
    //   // Start repeating animation
    //   //   } else {
    //   //     animationController.stop(); // Stop animation if connected, disconnected, or error
    //   //   }

    //   //   // Cleanup when widget is disposed
    //   //   return animationController.dispose;
    //   // }, [connectionStatus.value]);

    //   // ref.listen(
    //   //   connectionNotifierProvider,
    //   //   (_, next) {
    //   //     if (next case AsyncError(:final error)) {
    //   //       CustomAlertDialog.fromErr(t.presentError(error)).show(context);
    //   //     }
    //   //     if (next case AsyncData(value: Disconnected(:final connectionFailure?))) {
    //   //       CustomAlertDialog.fromErr(t.presentError(connectionFailure)).show(context);
    //   //     }
    //   //   },
    //   // );

    //   // return CircleDesignWidget(
    //   //   onTap: switch (connectionStatus) {
    //   //     // AsyncData(value: Disconnected()) || AsyncError() => () async {
    //   //     //     if (await showExperimentalNotice()) {
    //   //     //       return await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    //   //     //     }
    //   //     //   },
    //   //     // AsyncData(value: Connected()) => () async {
    //   //     //     if (requiresReconnect == true && await showExperimentalNotice()) {
    //   //     //       return await ref.read(connectionNotifierProvider.notifier).reconnect(await ref.read(activeProfileProvider.future));
    //   //     //     }
    //   //     //     return await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    //   //     //   },
    //   //     _ => () {},
    //   //   },
    //   //   // enabled: switch (connectionStatus) {
    //   //   //   AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,
    //   //   //   _ => false,
    //   //   // },
    //   //   // label: switch (connectionStatus) {
    //   //   //   AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
    //   //   //   AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => t.connection.connecting,
    //   //   //   AsyncData(value: final status) => status.present(t),
    //   //   //   _ => "",
    //   //   // },
    //   //   color: switch (connectionStatus) {
    //   //     AsyncData(value: Connected()) when requiresReconnect == true => Colors.teal,
    //   //     AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => Color.fromARGB(255, 157, 139, 1),
    //   //     AsyncData(value: Connected()) => Colors.green.shade900,
    //   //     AsyncData(value: _) => Colors.indigo.shade700, // Color(0xFF3446A5), //buttonTheme.idleColor!,
    //   //     _ => Colors.red,
    //   //   },

    //   //   animated: true ||
    //   //       switch (connectionStatus) {
    //   //         AsyncData(value: Connected()) when requiresReconnect == true => false,
    //   //         AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => false,
    //   //         AsyncData(value: Connected()) => true,
    //   //         AsyncData(value: _) => true,
    //   //         _ => false,
    //   //       },
    //   //   animationValue: animationValue,
    //   // );
    // }
    // var secureLabel =
    //     (ref.watch(ConfigOptions.enableWarp) && ref.watch(ConfigOptions.warpDetourMode) == WarpDetourMode.warpOverProxy)
    //     ? t.connection.secure
    //     : "";
    const secureLabel = '';
    return _ConnectionButton(
      onTap: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => () async {
          return await ref.read(nimbusConnectionControllerProvider.notifier).reconnect();
        },
        AsyncData(value: Disconnected()) || AsyncError() => () async {
          if (await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
            return await ref.read(nimbusConnectionControllerProvider.notifier).connect(userInitiated: true);
          }
        },
        AsyncData(value: Connected()) => () async {
          if (requiresReconnect == true &&
              await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
            return await ref.read(nimbusConnectionControllerProvider.notifier).reconnect();
          }
          return await ref.read(nimbusConnectionControllerProvider.notifier).disconnect(userInitiated: true);
        },
        _ => () {},
      },
      enabled: switch (connectionStatus) {
        AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,
        _ => false,
      },
      label: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
        AsyncData(value: final status) => status.present(t),
        _ => "",
      },
      semanticsLabel: switch (connectionStatus.valueOrNull) {
        Connected() => t.connection.disconnect,
        Connecting() => t.connection.connecting,
        Disconnecting() => t.connection.disconnecting,
        _ => t.connection.connect,
      },
      buttonColor: _yundoLogoColor,
      status: connectionStatus.valueOrNull,
      secureLabel: secureLabel,
    );
  }
}

class _ConnectionButton extends StatelessWidget {
  const _ConnectionButton({
    required this.onTap,
    required this.enabled,
    required this.label,
    required this.semanticsLabel,
    required this.buttonColor,
    required this.status,
    required this.secureLabel,
  });

  final VoidCallback onTap;
  final bool enabled;
  final String label;
  final String semanticsLabel;
  final Color buttonColor;
  final String secureLabel;
  final ConnectionStatus? status;

  @override
  Widget build(BuildContext context) {
    final isConnected = status is Connected;
    final isConnecting = status is Connecting;
    final isDisconnecting = status is Disconnecting;
    final isSwitching = isConnecting || isDisconnecting;
    final transitionColor = isDisconnecting
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.primary;

    Widget connectionIcon = const Icon(Icons.rocket_launch_rounded, size: 60, color: Colors.white);
    if (isConnected) {
      connectionIcon = connectionIcon
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scaleXY(begin: 0.97, end: 1.04, duration: const Duration(milliseconds: 1600), curve: Curves.easeInOut);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // CircleDesignWidget(newButtonColor: newButtonColor, onTap: onTap, animated: animated),
        Semantics(
          button: true,
          enabled: enabled,
          label: semanticsLabel,
          child: SizedBox(
            width: 148,
            height: 148,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (isConnected)
                  Transform.scale(
                    scale: 1.055,
                    child: Container(
                      width: 148,
                      height: 148,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: buttonColor.withValues(alpha: 0.32), width: 1.5),
                      ),
                    ),
                  ),
                if (isConnected)
                  Container(
                        width: 148,
                        height: 148,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: buttonColor.withValues(alpha: 0.62), width: 2),
                        ),
                      )
                      .animate(onPlay: (controller) => controller.repeat())
                      .scaleXY(
                        begin: 0.96,
                        end: 1.16,
                        duration: const Duration(milliseconds: 2200),
                        curve: Curves.easeOutCubic,
                      )
                      .fade(begin: 0.55, end: 0, duration: const Duration(milliseconds: 2200), curve: Curves.easeOut),
                if (isSwitching)
                  Transform.scale(
                    scale: 1.08,
                    child: SizedBox(
                      key: const ValueKey('home_connection_progress'),
                      width: 148,
                      height: 148,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        strokeCap: StrokeCap.round,
                        color: transitionColor.withValues(alpha: 0.9),
                        backgroundColor: transitionColor.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: isConnected ? 22 : 16,
                        spreadRadius: isConnected ? 2 : 0,
                        color: buttonColor.withValues(alpha: isConnected ? 0.46 : 0.32),
                      ),
                    ],
                  ),
                  width: 148,
                  height: 148,
                  child: Material(
                    key: const ValueKey("home_connection_button"),
                    shape: const CircleBorder(),
                    color: buttonColor,
                    child: InkWell(
                      focusColor: Colors.white.withValues(alpha: 0.16),
                      hoverColor: Colors.white.withValues(alpha: 0.08),
                      splashColor: Colors.white.withValues(alpha: 0.18),
                      onTap: enabled ? onTap : null,
                      child: Center(child: connectionIcon),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Gap(16),
        ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedText(label, style: Theme.of(context).textTheme.titleMedium),
              if (secureLabel.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // const Gap(8),
                    Icon(FontAwesomeIcons.shieldHalved, size: 16, color: Theme.of(context).colorScheme.secondary),
                    const Gap(4),
                    Text(
                      secureLabel,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.secondary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
