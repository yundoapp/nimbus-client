import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_app_version_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_app_version_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_issue_report_dialog.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_location_display.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _yundoLogoColor = Color(0xFF4F67AA);
const _homeDropdownItemHeight = 72.0;

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(nimbusAuthControllerProvider);
    final connectionState = ref.watch(nimbusConnectionControllerProvider);
    final versionState = ref.watch(nimbusAppVersionControllerProvider);
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final locale = ref.watch(localePreferencesProvider);
    final announcementRepository = ref.watch(nimbusAuthRepositoryProvider);
    final t = ref.watch(translationsProvider).requireValue;
    final username = authState.me?.user.username ?? authState.session?.user.username ?? '';
    final hasActivePlan = authState.me?.subscription.hasActivePlan ?? false;
    final announcementLanguage = locale.flutterLocale.toLanguageTag();
    final announcementPlatform = _platformForAnnouncement(appInfo.operatingSystem);
    final announcementFuture = useMemoized(
      () => announcementPlatform == null
          ? Future<NimbusAnnouncement?>.value()
          : announcementRepository.fetchCurrentAnnouncement(
              platform: announcementPlatform,
              language: announcementLanguage,
            ),
      [announcementRepository, announcementPlatform, announcementLanguage],
    );
    final announcement = useFuture(announcementFuture).data;
    final dismissedAnnouncementId = useState<String?>(null);

    useEffect(() {
      if (authState.isAuthenticated && authState.locations == null) {
        Future.microtask(() => ref.read(nimbusAuthControllerProvider.notifier).loadLocations());
      }
      return null;
    }, [authState.isAuthenticated]);

    Future<void> showActivationDialog() async {
      await showDialog<void>(context: context, builder: (_) => const _ActivationDialog());
    }

    Future<void> copyConnectionDiagnostic(NimbusConnectionDiagnostic diagnostic) async {
      await Clipboard.setData(ClipboardData(text: diagnostic.summary));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.nimbus.errors.diagnosticsCopied)));
    }

    Future<void> showIssueReport() async {
      await showDialog<void>(context: context, builder: (_) => const NimbusIssueReportDialog());
    }

    Future<void> showNoPlanDialog() async {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.nimbus.home.noPlanTitle),
          content: Text(t.nimbus.home.noPlanMessage),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.later)),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                showActivationDialog();
              },
              child: Text(t.nimbus.home.activatePlan),
            ),
          ],
        ),
      );
    }

    Future<void> refreshAccount() async {
      await ref.read(nimbusAuthControllerProvider.notifier).refreshMe();
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
        final message = latestState.errorMessage ?? t.nimbus.common.latestVersion;
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
          child: LayoutBuilder(
            builder: (context, viewport) {
              final sectionGap = viewport.maxHeight >= 800 ? 36.0 : 20.0;
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (username.isNotEmpty) ...[
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: _CurrentUserLabel(
                              username: username,
                              semanticsLabel: t.nimbus.home.currentAccount(username: username),
                              showUsername: true,
                            ),
                          ),
                          const Gap(24),
                        ],
                        if (announcement != null && dismissedAnnouncementId.value != announcement.id) ...[
                          _AnnouncementBanner(
                            announcement: announcement,
                            closeTooltip: t.common.close,
                            onClose: () => dismissedAnnouncementId.value = announcement.id,
                          ),
                          const Gap(12),
                        ],
                        Gap(sectionGap),
                        if (authState.me == null)
                          _HomePrimaryActionButton(
                            label: t.nimbus.home.retry,
                            icon: Icons.refresh_rounded,
                            isLoading: authState.isLoading,
                            onTap: refreshAccount,
                          )
                        else if (hasActivePlan)
                          versionState.forceUpdate
                              ? _UpdateRequiredConnectionButton(
                                  label: t.nimbus.home.updateRequired,
                                  onTap: () {
                                    final version = versionState.result;
                                    if (version != null) showVersionDialog(version);
                                  },
                                )
                              : const ConnectionButton()
                        else
                          _HomePrimaryActionButton(
                            label: t.nimbus.home.connect,
                            icon: Icons.rocket_launch_rounded,
                            onTap: showNoPlanDialog,
                          ),
                        const Gap(16),
                        if (connectionState.errorMessage != null) ...[
                          _ConnectionNoticeBanner(
                            message: connectionState.errorMessage!,
                            diagnostic: connectionState.diagnostic,
                            copyLabel: t.nimbus.errors.copyDiagnostics,
                            reportLabel: t.nimbus.settings.issueReport,
                            onCopy: connectionState.diagnostic == null
                                ? null
                                : () => copyConnectionDiagnostic(connectionState.diagnostic!),
                            onReport: showIssueReport,
                            onDismiss: () => ref.read(nimbusConnectionControllerProvider.notifier).clearNotice(),
                          ),
                          const Gap(12),
                        ],
                        _HomeQuickControls(rulesVersion: authState.me?.rules.publicRulesVersion),
                        Gap(sectionGap),
                        _NimbusStatusPanel(
                          theme: theme,
                          me: authState.me,
                          isLoading: authState.isLoading,
                          onActivate: showActivationDialog,
                          onRetry: refreshAccount,
                        ),
                        const Gap(16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ConnectionNoticeBanner extends StatelessWidget {
  const _ConnectionNoticeBanner({
    required this.message,
    required this.diagnostic,
    required this.copyLabel,
    required this.reportLabel,
    required this.onCopy,
    required this.onReport,
    required this.onDismiss,
  });

  final String message;
  final NimbusConnectionDiagnostic? diagnostic;
  final String copyLabel;
  final String reportLabel;
  final VoidCallback? onCopy;
  final VoidCallback onReport;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      key: const Key('home-connection-notice'),
      color: colors.errorContainer.withValues(alpha: theme.brightness == Brightness.dark ? 0.48 : 0.64),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.error.withValues(alpha: theme.brightness == Brightness.dark ? 0.32 : 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline_rounded, size: 21, color: colors.error),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.error,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (diagnostic != null) ...[
                    const Gap(6),
                    Text(
                      diagnostic!.code,
                      key: const Key('home-connection-diagnostic-code'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.error.withValues(alpha: 0.82),
                        fontFamily: 'monospace',
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Gap(2),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          key: const Key('home-copy-connection-diagnostic'),
                          onPressed: onCopy,
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: Text(copyLabel),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.error,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsetsDirectional.only(end: 10),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('home-report-connection-problem'),
                          onPressed: onReport,
                          icon: const Icon(Icons.outlined_flag_rounded, size: 16),
                          label: Text(reportLabel),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.error,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsetsDirectional.only(end: 10),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, size: 19, color: colors.error),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentUserLabel extends StatelessWidget {
  const _CurrentUserLabel({required this.username, required this.semanticsLabel, required this.showUsername});

  final String username;
  final String semanticsLabel;
  final bool showUsername;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticsLabel,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_circle_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
              if (showUsername) ...[
                const Gap(6),
                Flexible(
                  child: Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementBanner extends StatelessWidget {
  const _AnnouncementBanner({required this.announcement, required this.closeTooltip, required this.onClose});

  final NimbusAnnouncement announcement;
  final String closeTooltip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.secondaryContainer.withValues(alpha: theme.brightness == Brightness.dark ? 0.48 : 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.campaign_outlined, size: 20, color: colors.onSecondaryContainer),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    announcement.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(3),
                  Text(
                    announcement.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSecondaryContainer.withValues(alpha: 0.86),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onClose,
              tooltip: closeTooltip,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

String? _platformForAnnouncement(String operatingSystem) {
  return switch (operatingSystem) {
    'macos' => 'macos',
    'windows' => 'windows',
    'ios' => 'ios',
    'android' => 'android',
    _ => null,
  };
}

class _NimbusStatusPanel extends ConsumerWidget {
  const _NimbusStatusPanel({
    required this.theme,
    required this.me,
    required this.isLoading,
    required this.onActivate,
    required this.onRetry,
  });

  final ThemeData theme;
  final NimbusMe? me;
  final bool isLoading;
  final VoidCallback onActivate;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final muted = theme.colorScheme.onSurfaceVariant;
    if (me == null) {
      return _HomeStatusFrame(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final message = Row(
              children: [
                _StatusIcon(icon: Icons.cloud_off_rounded, theme: theme),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.nimbus.home.accountUnavailable,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Gap(4),
                      Text(
                        t.nimbus.common.requestFailed,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final retryButton = FilledButton.tonalIcon(
              key: const Key('home-account-retry'),
              onPressed: isLoading ? null : onRetry,
              icon: isLoading
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
              label: Text(t.nimbus.home.retry),
            );

            if (constraints.maxWidth < 430) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [message, const Gap(12), retryButton],
              );
            }

            return Row(
              children: [
                Expanded(child: message),
                const Gap(14),
                retryButton,
              ],
            );
          },
        ),
      );
    }

    final subscription = me?.subscription;
    final quotaBytes = subscription?.quotaBytes;
    final usedBytes = subscription?.usedBytes ?? 0;
    final remainingBytes = subscription?.remainingBytes;
    final progress = quotaBytes == null || quotaBytes <= 0 ? 0.0 : (usedBytes / quotaBytes).clamp(0.0, 1.0);
    final dateLocalizations = MaterialLocalizations.of(context);
    final planName = subscription?.planName?.trim();
    final planNameText = planName?.isNotEmpty == true ? planName! : t.nimbus.home.currentPlan;
    final quotaText = _formatPlanBytes(quotaBytes);
    final startedText = _formatDate(subscription?.startedAt, dateLocalizations);
    final expiresText = _formatDate(subscription?.expiresAt, dateLocalizations);
    final progressText = formatUsagePercent(progress);
    final usedText = _formatPlanBytes(usedBytes);
    final remainingText = _formatPlanBytes(remainingBytes);
    final hasActivePlan = subscription?.hasActivePlan ?? false;
    final sectionTitleStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );

    if (!hasActivePlan) {
      return _HomeStatusFrame(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final message = Row(
              children: [
                _StatusIcon(icon: Icons.key_rounded, theme: theme),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subscription?.status == 'expired' ? t.nimbus.home.planExpired : t.nimbus.home.noAvailablePlan,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Gap(4),
                      Text(
                        t.nimbus.home.activateHint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final activateButton = FilledButton.tonalIcon(
              onPressed: onActivate,
              icon: const Icon(Icons.key_rounded),
              label: Text(t.nimbus.home.activatePlan),
            );

            if (constraints.maxWidth < 430) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [message, const Gap(12), activateButton],
              );
            }

            return Row(
              children: [
                Expanded(child: message),
                const Gap(14),
                activateButton,
              ],
            );
          },
        ),
      );
    }

    return _HomeStatusFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.nimbus.home.cycleUsage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sectionTitleStyle,
                ),
              ),
              const Gap(12),
              Text(progressText, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
            ],
          ),
          const Gap(7),
          LinearProgressIndicator(
            value: progress,
            semanticsValue: progressText,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: _StatusText(label: t.nimbus.home.used, value: usedText, color: muted),
              ),
              Expanded(
                child: _StatusText(label: t.nimbus.home.unused, value: remainingText, color: muted, alignEnd: true),
              ),
            ],
          ),
          const Gap(14),
          Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.62)),
          const Gap(14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 320;
              final planMetric = _PlanMetric(label: t.nimbus.home.currentPlan, value: planNameText);
              final quotaMetric = _PlanMetric(
                label: t.nimbus.home.monthlyQuotaLabel,
                value: quotaText,
                alignEnd: isWide,
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [planMetric, const Gap(10), quotaMetric],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: planMetric),
                  const Gap(24),
                  Expanded(child: quotaMetric),
                ],
              );
            },
          ),
          const Gap(16),
          _PlanValidity(
            label: t.nimbus.home.validityLabel,
            start: startedText,
            end: expiresText,
            semanticsLabel: t.nimbus.home.validity(start: startedText, end: expiresText),
          ),
        ],
      ),
    );
  }
}

class _HomeStatusFrame extends StatelessWidget {
  const _HomeStatusFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: theme.brightness == Brightness.dark ? 0.78 : 0.92),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.62)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _PlanMetric extends StatelessWidget {
  const _PlanMetric({required this.label, required this.value, this.alignEnd = false});

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant, height: 1.15),
        ),
        const Gap(4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _PlanValidity extends StatelessWidget {
  const _PlanValidity({required this.label, required this.start, required this.end, required this.semanticsLabel});

  final String label;
  final String start;
  final String end;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dateStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurface,
      fontWeight: FontWeight.w600,
      height: 1.15,
    );

    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
    );
    final rangeWidget = Text(
      '$start – $end',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: dateStyle,
    );

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const Gap(4), rangeWidget],
            );
          }

          return Row(
            children: [
              labelWidget,
              const Gap(12),
              Expanded(child: rangeWidget),
            ],
          );
        },
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.icon, required this.theme});

  final IconData icon;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primaryContainer.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.36 : 0.72,
          ),
        ),
        child: Icon(icon, size: 20, color: theme.colorScheme.primary),
      ),
    );
  }
}

class _HomeQuickControls extends HookConsumerWidget {
  const _HomeQuickControls({required this.rulesVersion});

  final String? rulesVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final selectedLocation = _selectedLocation(authState);
    final rulesText = _formatRulesVersionForDisplay(rulesVersion);

    Widget proxyCard() => _ProxyModeControlCard(rulesVersion: rulesText);

    Widget locationCard() => _LocationControlCard(selectedLocation: selectedLocation);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              SizedBox(height: 72, child: proxyCard()),
              const Gap(10),
              SizedBox(height: 72, child: locationCard()),
            ],
          );
        }

        return SizedBox(
          height: 72,
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

class _ProxyModeControlCard extends HookConsumerWidget {
  const _ProxyModeControlCard({required this.rulesVersion});

  final String rulesVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final selectedMode = ref.watch(Preferences.nimbusProxyMode);
    final connection = ref.watch(nimbusOwnedConnectionStatusProvider).valueOrNull;
    final isSwitching = connection?.isSwitching ?? false;
    final isApplying = useState(false);
    final disabled = isApplying.value || isSwitching;

    Future<void> selectMode(NimbusProxyMode mode) async {
      if (disabled || mode == selectedMode) return;
      isApplying.value = true;
      try {
        await ref.read(Preferences.nimbusProxyMode.notifier).update(mode);
        await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected();
      } finally {
        if (context.mounted) isApplying.value = false;
      }
    }

    final menuChildren = <Widget>[];
    for (var index = 0; index < NimbusProxyMode.values.length; index++) {
      if (index > 0) menuChildren.add(_homeDropdownDivider(theme));
      final mode = NimbusProxyMode.values[index];
      final isSelected = mode == selectedMode;
      menuChildren.add(
        MenuItemButton(
          onPressed: disabled ? null : () => selectMode(mode),
          trailingIcon: isSelected
              ? Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary)
              : const SizedBox(width: 18),
          style: _homeDropdownItemStyle(theme, isSelected: isSelected, height: _homeDropdownItemHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mode.label(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                mode.description(t),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.25),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        child: MenuAnchor(
          crossAxisUnconstrained: false,
          useRootOverlay: true,
          alignmentOffset: const Offset(0, 6),
          style: _homeDropdownMenuStyle(theme, constraints.maxWidth),
          menuChildren: menuChildren,
          builder: (context, controller, child) => SizedBox(
            width: constraints.maxWidth,
            child: _HomeControlCard(
              icon: Icons.route_rounded,
              title: t.nimbus.home.connectionMode,
              value: selectedMode.label(t),
              detail: selectedMode == NimbusProxyMode.auto
                  ? t.nimbus.home.accessPolicyVersion(version: rulesVersion)
                  : t.nimbus.home.globalRoutingDetail,
              isExpanded: controller.isOpen,
              isLoading: disabled,
              onTap: disabled ? null : () => controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationControlCard extends HookConsumerWidget {
  const _LocationControlCard({required this.selectedLocation});

  final NimbusLocation selectedLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final t = ref.watch(translationsProvider).requireValue;
    final locale = ref.watch(localePreferencesProvider);
    final locations = authState.locations?.items ?? [selectedLocation];
    final connection = ref.watch(nimbusOwnedConnectionStatusProvider).valueOrNull;
    final isSwitching = connection?.isSwitching ?? false;
    final isLoadingLocations = useState(false);
    final theme = Theme.of(context);

    if (PlatformUtils.isMobile) {
      return _HomeControlCard(
        icon: Icons.public_rounded,
        leading: nimbusLocationFlag(selectedLocation),
        title: t.nimbus.home.locationTitle,
        value: nimbusLocationDisplayName(t, selectedLocation, locale.languageCode),
        detail: t.nimbus.home.locationDetail,
        isLoading: isLoadingLocations.value,
        onTap: isSwitching || isLoadingLocations.value
            ? null
            : () async {
                isLoadingLocations.value = true;
                try {
                  await ref.read(nimbusAuthControllerProvider.notifier).loadLocations();
                  if (!context.mounted) return;
                  await Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => const _NimbusLocationSelectionPage()));
                } finally {
                  if (context.mounted) isLoadingLocations.value = false;
                }
              },
      );
    }

    final menuChildren = <Widget>[];
    for (var index = 0; index < locations.length; index++) {
      if (index > 0) menuChildren.add(_homeDropdownDivider(theme));
      final location = locations[index];
      final isSelected = location.code == authState.selectedLocationCode;
      menuChildren.add(
        MenuItemButton(
          style: _homeDropdownItemStyle(theme, isSelected: isSelected, height: _homeDropdownItemHeight),
          trailingIcon: isSelected
              ? Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary)
              : const SizedBox(width: 18),
          onPressed: isSwitching
              ? null
              : () => ref.read(nimbusConnectionControllerProvider.notifier).selectLocation(location),
          child: Row(
            children: [
              nimbusLocationFlag(location),
              const Gap(10),
              Expanded(
                child: Text(
                  nimbusLocationDisplayName(t, location, locale.languageCode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        child: MenuAnchor(
          crossAxisUnconstrained: false,
          useRootOverlay: true,
          alignmentOffset: const Offset(0, 6),
          style: _homeDropdownMenuStyle(theme, constraints.maxWidth),
          menuChildren: menuChildren,
          builder: (context, controller, child) => SizedBox(
            width: constraints.maxWidth,
            child: _HomeControlCard(
              icon: Icons.public_rounded,
              leading: nimbusLocationFlag(selectedLocation),
              title: t.nimbus.home.locationTitle,
              value: nimbusLocationDisplayName(t, selectedLocation, locale.languageCode),
              detail: t.nimbus.home.locationDetail,
              isExpanded: controller.isOpen,
              isLoading: isLoadingLocations.value,
              onTap: isSwitching || isLoadingLocations.value
                  ? null
                  : () async {
                      isLoadingLocations.value = true;
                      try {
                        await ref.read(nimbusAuthControllerProvider.notifier).loadLocations();
                        if (!context.mounted) return;
                        controller.isOpen ? controller.close() : controller.open();
                      } finally {
                        if (context.mounted) isLoadingLocations.value = false;
                      }
                    },
            ),
          ),
        ),
      ),
    );
  }
}

MenuStyle _homeDropdownMenuStyle(ThemeData theme, double width) {
  final colors = theme.colorScheme;
  return MenuStyle(
    alignment: AlignmentDirectional.bottomStart,
    backgroundColor: WidgetStatePropertyAll(colors.surface),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(colors.shadow.withValues(alpha: 0.12)),
    elevation: const WidgetStatePropertyAll(2),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
    minimumSize: WidgetStatePropertyAll(Size(width, 0)),
    maximumSize: WidgetStatePropertyAll(Size(width, double.infinity)),
    side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant.withValues(alpha: 0.52))),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
  );
}

Widget _homeDropdownDivider(ThemeData theme) =>
    Divider(height: 1, indent: 10, endIndent: 10, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42));

ButtonStyle _homeDropdownItemStyle(ThemeData theme, {required bool isSelected, required double height}) {
  final colors = theme.colorScheme;
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.fromHeight(height)),
    maximumSize: WidgetStatePropertyAll(Size.fromHeight(height)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (isSelected) {
        final alpha = states.contains(WidgetState.hovered) ? 0.44 : 0.28;
        return colors.primaryContainer.withValues(alpha: alpha);
      }
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return colors.surfaceContainerHighest.withValues(alpha: 0.56);
      }
      return Colors.transparent;
    }),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)))),
  );
}

class _NimbusLocationSelectionPage extends HookConsumerWidget {
  const _NimbusLocationSelectionPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final t = ref.watch(translationsProvider).requireValue;
    final locale = ref.watch(localePreferencesProvider);
    final connection = ref.watch(nimbusOwnedConnectionStatusProvider).valueOrNull;
    final isSwitching = connection?.isSwitching ?? false;
    final locations = authState.locations?.items ?? const [NimbusLocation(code: 'auto', displayName: '')];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.nimbus.home.locationTitle)),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: locations.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final location = locations[index];
            final isSelected = location.code == authState.selectedLocationCode;
            return ListTile(
              enabled: !isSwitching,
              leading: nimbusLocationFlag(location),
              title: Text(nimbusLocationDisplayName(t, location, locale.languageCode)),
              trailing: isSelected ? Icon(Icons.check_rounded, color: theme.colorScheme.primary) : null,
              onTap: isSwitching
                  ? null
                  : () async {
                      await ref.read(nimbusConnectionControllerProvider.notifier).selectLocation(location);
                      if (context.mounted) Navigator.of(context).pop();
                    },
            );
          },
        ),
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
    this.leading,
    this.isExpanded,
    this.isLoading = false,
  });

  final IconData icon;
  final Widget? leading;
  final String title;
  final String value;
  final String detail;
  final VoidCallback? onTap;
  final bool? isExpanded;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: isExpanded == true
            ? theme.colorScheme.primary.withValues(alpha: 0.46)
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.46),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      expanded: isExpanded,
      label: '$title, $value, $detail',
      excludeSemantics: true,
      child: Tooltip(
        message: detail,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: isExpanded == true
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
              : theme.colorScheme.surface.withValues(alpha: 0.84),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  leading ??
                      Icon(
                        icon,
                        size: 22,
                        color: enabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.52),
                      ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const Gap(3),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Gap(8),
                  if (isLoading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                    )
                  else
                    AnimatedRotation(
                      turns: isExpanded == true ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        isExpanded == null ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                        size: 20,
                        color: isExpanded == true ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePrimaryActionButton extends StatelessWidget {
  const _HomePrimaryActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = _yundoLogoColor;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: label,
          child: SizedBox(
            width: 168,
            height: 168,
            child: Material(
              color: color,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isLoading ? null : onTap,
                child: isLoading
                    ? Center(
                        child: SizedBox.square(
                          dimension: 44,
                          child: CircularProgressIndicator(strokeWidth: 4, color: theme.colorScheme.onPrimary),
                        ),
                      )
                    : Icon(icon, size: 56, color: theme.colorScheme.onPrimary),
              ),
            ),
          ),
        ),
        const Gap(16),
        Text(label, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _UpdateRequiredConnectionButton extends StatelessWidget {
  const _UpdateRequiredConnectionButton({required this.label, required this.onTap});

  final String label;
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
          label: label,
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
        Text(label, style: theme.textTheme.titleMedium),
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
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;

    Future<void> submit() async {
      final code = controller.text.replaceAll(RegExp('[\\s-]'), '').toUpperCase();
      if (code.length != 16) {
        errorMessage.value = t.nimbus.activation.invalidCode;
        return;
      }
      final success = await ref.read(nimbusAuthControllerProvider.notifier).redeemActivationCode(code);
      if (!context.mounted) return;
      if (success) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(t.nimbus.activation.activated)));
      } else {
        errorMessage.value = ref.read(nimbusAuthControllerProvider).errorMessage ?? t.nimbus.activation.failed;
      }
    }

    return AlertDialog(
      title: Text(t.nimbus.activation.title),
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
              decoration: InputDecoration(
                labelText: t.nimbus.activation.codeLabel,
                hintText: 'ABCD-EFGH-JKMP-QRST',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                  letterSpacing: 0.4,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                prefixIcon: const Icon(Icons.key_rounded),
              ),
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
        TextButton(
          onPressed: authState.isLoading ? null : () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: authState.isLoading ? null : submit,
          child: authState.isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.nimbus.activation.submit),
        ),
      ],
    );
  }
}

NimbusLocation _selectedLocation(NimbusAuthState authState) {
  final locations = authState.locations?.items ?? const [NimbusLocation(code: 'auto', displayName: '')];
  return locations.firstWhere(
    (location) => location.code == authState.selectedLocationCode,
    orElse: () => const NimbusLocation(code: 'auto', displayName: ''),
  );
}

String _formatRulesVersionForDisplay(String? version) {
  final text = version?.trim() ?? '';
  if (text.isEmpty) return '--';
  return RegExp(r'^\d{4}\.').hasMatch(text) ? text.substring(2) : text;
}

extension on NimbusProxyMode {
  String label(Translations t) => switch (this) {
    NimbusProxyMode.auto => t.nimbus.proxyMode.auto,
    NimbusProxyMode.global => t.nimbus.proxyMode.global,
  };

  String description(Translations t) => switch (this) {
    NimbusProxyMode.auto => t.nimbus.proxyMode.autoDescription,
    NimbusProxyMode.global => t.nimbus.proxyMode.globalDescription,
  };
}

String _formatPlanBytes(int? bytes) {
  if (bytes == null) return '--';
  if (bytes <= 0) return '0 MB';
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) {
    final value = bytes / gb;
    return _formatPlanUnit(value, 'GB');
  }
  final value = (bytes / mb).clamp(0.1, double.infinity);
  return _formatPlanUnit(value, 'MB');
}

@visibleForTesting
String formatUsagePercent(num progress) {
  if (progress <= 0) return '0%';
  if (progress < 0.01) return '<1%';
  return '${(progress * 100).round()}%';
}

String _formatPlanUnit(double value, String unit) {
  final fixed = value.toStringAsFixed(value >= 100 ? 0 : 1);
  final compact = fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  return '$compact $unit';
}

String _formatDate(DateTime? value, MaterialLocalizations localizations) {
  if (value == null) return '--';
  return localizations.formatCompactDate(value.toLocal());
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
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
        const Gap(2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
