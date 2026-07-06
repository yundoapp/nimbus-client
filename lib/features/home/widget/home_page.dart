import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_devices_dialog.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(nimbusAuthControllerProvider);
    final stats = ref.watch(statsNotifierProvider).asData?.value;
    final hasActivePlan = authState.me?.subscription.hasActivePlan ?? false;
    final uplinkSpeed = _formatSpeed(stats?.uplink.toInt() ?? 0);
    final downlinkSpeed = _formatSpeed(stats?.downlink.toInt() ?? 0);

    Future<void> showActivationDialog() async {
      await showDialog<void>(context: context, builder: (_) => const _ActivationDialog());
    }

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
                leadingIcon: const Icon(Icons.devices_rounded),
                onPressed: () {
                  showDialog<void>(context: context, builder: (_) => const NimbusDevicesDialog());
                },
                child: const Text('设备管理'),
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
                    if (hasActivePlan)
                      const ConnectionButton()
                    else
                      _ActivationConnectionButton(onTap: showActivationDialog),
                    const Gap(6),
                    const ActiveProxyDelayIndicator(),
                    const Spacer(),
                    _NimbusStatusPanel(
                      theme: theme,
                      me: authState.me,
                      uplinkSpeed: uplinkSpeed,
                      downlinkSpeed: downlinkSpeed,
                      onActivate: showActivationDialog,
                    ),
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
  const _NimbusStatusPanel({
    required this.theme,
    required this.me,
    required this.uplinkSpeed,
    required this.downlinkSpeed,
    required this.onActivate,
  });

  final ThemeData theme;
  final NimbusMe? me;
  final String uplinkSpeed;
  final String downlinkSpeed;
  final VoidCallback onActivate;

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
    final expiresText = _formatDate(subscription?.expiresAt);
    final usedText = _formatBytes(usedBytes);
    final remainingText = remainingBytes == null ? '--' : _formatBytes(remainingBytes);
    final totalText = quotaBytes == null ? '--' : _formatBytes(quotaBytes);
    final rulesVersion = me?.rules.publicRulesVersion ?? '--';
    final hasActivePlan = subscription?.hasActivePlan ?? false;

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
              child: _StatusText(label: "到期", value: expiresText, color: muted, alignEnd: true),
            ),
          ],
        ),
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: _StatusText(label: "已用", value: usedText, color: muted),
            ),
            Expanded(
              child: _StatusText(label: "剩余", value: remainingText, color: muted, alignEnd: true),
            ),
          ],
        ),
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: _StatusText(label: "总量", value: totalText, color: muted),
            ),
            Expanded(
              child: _StatusText(label: "规则", value: rulesVersion, color: muted, alignEnd: true),
            ),
          ],
        ),
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: _StatusText(label: "上传", value: uplinkSpeed, color: muted),
            ),
            Expanded(
              child: _StatusText(label: "下载", value: downlinkSpeed, color: muted, alignEnd: true),
            ),
          ],
        ),
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: _StatusText(label: "位置", value: "自动", color: muted),
            ),
            if (!hasActivePlan)
              FilledButton.tonalIcon(
                onPressed: onActivate,
                icon: const Icon(Icons.key_rounded),
                label: const Text('激活'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ActivationConnectionButton extends StatelessWidget {
  const _ActivationConnectionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: '启用',
          child: SizedBox(
            width: 168,
            height: 168,
            child: Material(
              color: color,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Icon(Icons.power_settings_new_rounded, size: 56, color: theme.colorScheme.onPrimary),
              ),
            ),
          ),
        ),
        const Gap(16),
        Text('启用', style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _ActivationDialog extends HookConsumerWidget {
  const _ActivationDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final errorMessage = useState<String?>(null);
    final authState = ref.watch(nimbusAuthControllerProvider);

    Future<void> submit() async {
      final code = controller.text.replaceAll(RegExp('[\\s-]'), '').toUpperCase();
      if (code.length != 16) {
        errorMessage.value = '请输入 16 位激活码';
        return;
      }
      final success = await ref.read(nimbusAuthControllerProvider.notifier).redeemActivationCode(code);
      if (!context.mounted) return;
      if (success) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('套餐已激活')));
      } else {
        errorMessage.value = ref.read(nimbusAuthControllerProvider).errorMessage ?? '激活失败，请稍后重试';
      }
    }

    return AlertDialog(
      title: const Text('激活套餐'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 -]')),
                LengthLimitingTextInputFormatter(19),
              ],
              decoration: const InputDecoration(labelText: '激活码', prefixIcon: Icon(Icons.key_rounded)),
              onChanged: (_) => errorMessage.value = null,
              onSubmitted: (_) => submit(),
            ),
            if (errorMessage.value != null) ...[
              const Gap(10),
              Text(
                errorMessage.value!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: authState.isLoading ? null : () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: authState.isLoading ? null : submit,
          child: authState.isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('激活'),
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

String _formatSpeed(int bytesPerSecond) => '${_formatBytes(bytesPerSecond)}/s';

String _formatDate(DateTime? value) {
  if (value == null) return '--';
  return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

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
