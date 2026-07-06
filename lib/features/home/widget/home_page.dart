import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(nimbusAuthControllerProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          children: [
            Assets.images.logo.svg(height: 24),
            const Gap(8),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: "Nimbus"),
                  TextSpan(text: " "),
                  WidgetSpan(child: AppVersionLabel(), alignment: PlaceholderAlignment.middle),
                ],
              ),
            ),
          ],
        ),
        actions: [
          MenuAnchor(
            menuChildren: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(authState.session?.user.username ?? '已登录', style: theme.textTheme.labelLarge),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.logout_rounded),
                onPressed: () async {
                  await ref.read(nimbusAuthControllerProvider.notifier).logout();
                  if (context.mounted) context.go('/auth/login');
                },
                child: const Text('退出登录'),
              ),
            ],
            builder: (context, controller, child) => IconButton(
              tooltip: '账号',
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ),
          const Gap(8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'),
            fit: BoxFit.cover,
            opacity: 0.09,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(Colors.white.withValues(alpha: .15), BlendMode.srcIn) //
                : ColorFilter.mode(
                    Colors.grey.withValues(alpha: 1),
                    BlendMode.srcATop,
                  ), // Apply white tint in dark mode
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    const Spacer(),
                    Text(
                      "自动",
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Gap(18),
                    const ConnectionButton(),
                    const Gap(6),
                    const ActiveProxyDelayIndicator(),
                    const Spacer(),
                    _NimbusStatusPanel(theme: theme, me: authState.me),
                    const Gap(16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NimbusStatusPanel extends StatelessWidget {
  const _NimbusStatusPanel({required this.theme, required this.me});

  final ThemeData theme;
  final NimbusMe? me;

  @override
  Widget build(BuildContext context) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final subscription = me?.subscription;
    final quotaBytes = subscription?.quotaBytes;
    final usedBytes = subscription?.usedBytes ?? 0;
    final remainingBytes = subscription?.remainingBytes;
    final progress = quotaBytes == null || quotaBytes <= 0 ? 0.0 : (usedBytes / quotaBytes).clamp(0.0, 1.0);
    final planName = switch (subscription?.status) {
      'active' => subscription?.planName ?? '已开通',
      'expired' => '套餐已过期',
      _ => '暂无可用套餐',
    };
    final remainingText = remainingBytes == null ? '--' : _formatBytes(remainingBytes);
    final rulesVersion = me?.rules.publicRulesVersion ?? '--';

    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: _StatusText(label: "套餐", value: planName, color: muted),
            ),
            Expanded(
              child: _StatusText(label: "剩余流量", value: remainingText, color: muted, alignEnd: true),
            ),
          ],
        ),
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: _StatusText(label: "位置", value: "自动", color: muted),
            ),
            Expanded(
              child: _StatusText(label: "规则", value: rulesVersion, color: muted, alignEnd: true),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final fractionDigits = unitIndex <= 1 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.label, required this.value, required this.color, this.alignEnd = false});

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        const Gap(2),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          version,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
