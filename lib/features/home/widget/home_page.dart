import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_app_version_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_app_version_dialog.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(nimbusAuthControllerProvider);
    final versionState = ref.watch(nimbusAppVersionControllerProvider);
    final appTitle = ref.watch(translationsProvider).requireValue.common.appTitle;
    final hasActivePlan = authState.me?.subscription.hasActivePlan ?? false;

    useEffect(() {
      if (authState.isAuthenticated && authState.locations == null) {
        Future.microtask(() => ref.read(nimbusAuthControllerProvider.notifier).loadLocations());
      }
      return null;
    }, [authState.isAuthenticated]);

    Future<void> showActivationDialog() async {
      await showDialog<void>(context: context, builder: (_) => const _ActivationDialog());
    }

    Future<void> showNoPlanDialog() async {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('暂无可用套餐'),
          content: const Text('您当前尚无可用套餐，请先激活或者购买套餐后再连接。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('稍后')),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                showActivationDialog();
              },
              child: const Text('激活套餐'),
            ),
          ],
        ),
      );
    }

    Future<void> showVersionDialog(NimbusAppVersionCheck version) async {
      await showDialog<void>(
        context: context,
        builder: (_) => NimbusAppVersionDialog(version: version),
      );
    }

    Future<void> checkForUpdate({bool manual = false}) async {
      final result = await ref.read(nimbusAppVersionControllerProvider.notifier).check(force: manual);
      if (!context.mounted) return;
      final latestState = ref.read(nimbusAppVersionControllerProvider);
      if (result != null && (result.updateAvailable || result.forceUpdate)) {
        await showVersionDialog(result);
      } else if (manual) {
        final message = latestState.errorMessage ?? '已是最新版本';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }

    useEffect(() {
      if (authState.isAuthenticated) {
        Future.microtask(checkForUpdate);
      }
      return null;
    }, [authState.isAuthenticated]);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          children: [
            Image.asset('assets/images/app_icon.png', width: 24, height: 24),
            const Gap(8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: appTitle),
                  const TextSpan(text: " "),
                  const WidgetSpan(child: AppVersionLabel(), alignment: PlaceholderAlignment.middle),
                ],
              ),
            ),
          ],
        ),
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
                    if (hasActivePlan)
                      versionState.forceUpdate
                          ? _UpdateRequiredConnectionButton(
                              onTap: () {
                                final version = versionState.result;
                                if (version != null) showVersionDialog(version);
                              },
                            )
                          : const ConnectionButton()
                    else
                      _ActivationConnectionButton(onTap: showNoPlanDialog),
                    const Gap(16),
                    _HomeQuickControls(rulesVersion: authState.me?.rules.publicRulesVersion),
                    const Gap(8),
                    const ActiveProxyDelayIndicator(),
                    const Spacer(),
                    _NimbusStatusPanel(theme: theme, me: authState.me, onActivate: showActivationDialog),
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
  const _NimbusStatusPanel({required this.theme, required this.me, required this.onActivate});

  final ThemeData theme;
  final NimbusMe? me;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final subscription = me?.subscription;
    final quotaBytes = subscription?.quotaBytes;
    final usedBytes = subscription?.usedBytes ?? 0;
    final remainingBytes = subscription?.remainingBytes;
    final progress = quotaBytes == null || quotaBytes <= 0 ? 0.0 : (usedBytes / quotaBytes).clamp(0.0, 1.0);
    final expiresText = _formatDate(subscription?.expiresAt);
    final usedText = _formatPlanBytes(usedBytes);
    final remainingText = _formatPlanBytes(remainingBytes);
    final hasActivePlan = subscription?.hasActivePlan ?? false;

    if (!hasActivePlan) {
      return Column(
        children: [
          Text(
            subscription?.status == 'expired' ? '套餐已过期' : '当前暂无可用套餐',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Gap(4),
          Text(
            '请先激活或者购买套餐。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const Gap(10),
          FilledButton.tonalIcon(onPressed: onActivate, icon: const Icon(Icons.key_rounded), label: const Text('激活套餐')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '本月套餐使用情况',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text('到期 $expiresText', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
        ),
        const Gap(8),
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
              child: _StatusText(label: "已使用", value: usedText, color: muted),
            ),
            Expanded(
              child: _StatusText(label: "未使用", value: remainingText, color: muted, alignEnd: true),
            ),
          ],
        ),
      ],
    );
  }
}

class _HomeQuickControls extends HookConsumerWidget {
  const _HomeQuickControls({required this.rulesVersion});

  final String? rulesVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyMode = ref.watch(Preferences.nimbusProxyMode);
    final authState = ref.watch(nimbusAuthControllerProvider);
    final selectedLocation = _selectedLocation(authState);
    final rulesText = rulesVersion == null || rulesVersion!.isEmpty ? '--' : rulesVersion!;

    Widget proxyCard() => _HomeControlCard(
      icon: Icons.route_rounded,
      title: '代理模式',
      value: proxyMode.label,
      detail: '规则 $rulesText',
      onTap: () => _showProxyModeDialog(context),
    );

    Widget locationCard() => _LocationControlCard(selectedLocation: selectedLocation);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              SizedBox(height: 86, child: proxyCard()),
              const Gap(10),
              SizedBox(height: 86, child: locationCard()),
            ],
          );
        }

        return SizedBox(
          height: 86,
          child: Row(
            children: [
              Expanded(child: proxyCard()),
              const Gap(12),
              Expanded(child: locationCard()),
            ],
          ),
        );
      },
    );
  }
}

class _LocationControlCard extends HookConsumerWidget {
  const _LocationControlCard({required this.selectedLocation});

  final NimbusLocation selectedLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final locations = authState.locations?.items ?? [selectedLocation];

    return MenuAnchor(
      menuChildren: locations
          .map(
            (location) => MenuItemButton(
              leadingIcon: location.code == authState.selectedLocationCode
                  ? const Icon(Icons.check_rounded)
                  : const SizedBox(width: 24),
              onPressed: () => ref.read(nimbusAuthControllerProvider.notifier).selectLocation(location),
              child: Text(location.displayName),
            ),
          )
          .toList(),
      builder: (context, controller, child) => _HomeControlCard(
        icon: Icons.public_rounded,
        title: '节点选择',
        value: selectedLocation.displayName,
        detail: '按国家选择',
        onTap: () async {
          await ref.read(nimbusAuthControllerProvider.notifier).loadLocations();
          if (!context.mounted) return;
          controller.isOpen ? controller.close() : controller.open();
        },
      ),
    );
  }
}

class _HomeControlCard extends StatelessWidget {
  const _HomeControlCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.66),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const Gap(10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const Gap(2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Gap(2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showProxyModeDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final selected = ref.watch(Preferences.nimbusProxyMode);
        return AlertDialog(
          title: const Text('代理模式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: NimbusProxyMode.values
                .map(
                  (mode) => ListTile(
                    leading: Icon(
                      mode == selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: mode == selected ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(mode.label),
                    subtitle: Text(mode.description),
                    onTap: () async {
                      await ref.read(Preferences.nimbusProxyMode.notifier).update(mode);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                )
                .toList(),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
        );
      },
    ),
  );
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

class _UpdateRequiredConnectionButton extends StatelessWidget {
  const _UpdateRequiredConnectionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: '需要更新',
          child: SizedBox(
            width: 168,
            height: 168,
            child: Material(
              color: color,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Icon(Icons.system_update_alt_rounded, size: 56, color: theme.colorScheme.onError),
              ),
            ),
          ),
        ),
        const Gap(16),
        Text('需要更新', style: theme.textTheme.titleMedium),
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

NimbusLocation _selectedLocation(NimbusAuthState authState) {
  final locations = authState.locations?.items ?? const [NimbusLocation(code: 'auto', displayName: '自动')];
  return locations.firstWhere(
    (location) => location.code == authState.selectedLocationCode,
    orElse: () => const NimbusLocation(code: 'auto', displayName: '自动'),
  );
}

String _formatPlanBytes(int? bytes) {
  if (bytes == null) return '--';
  if (bytes <= 0) return '0 MB';
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) {
    final value = bytes / gb;
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} GB';
  }
  final value = (bytes / mb).clamp(0.1, double.infinity);
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} MB';
}

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
