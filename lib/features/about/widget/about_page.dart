import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _AboutSurface(
    asDialog: false,
    onClose: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed('settings');
      }
    },
  );
}

class NimbusAboutDialog extends HookConsumerWidget {
  const NimbusAboutDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _AboutSurface(asDialog: true, onClose: () => Navigator.of(context).pop());
}

class _AboutSurface extends HookConsumerWidget {
  const _AboutSurface({required this.asDialog, required this.onClose});

  final bool asDialog;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final appUpdate = ref.watch(appUpdateNotifierProvider);
    final environment = ref.watch(environmentProvider);
    final appTitle = environment == Environment.dev ? t.common.devAppTitle : t.common.appTitle;

    ref.listen(appUpdateNotifierProvider, (_, next) async {
      if (!context.mounted) return;
      switch (next) {
        case AppUpdateStateAvailable(:final versionInfo) || AppUpdateStateIgnored(:final versionInfo):
          return await ref
              .read(dialogNotifierProvider.notifier)
              .showNewVersion(currentVersion: appInfo.presentVersion, newVersion: versionInfo, canIgnore: false);
        case AppUpdateStateError(:final error):
          return CustomToast.error(t.presentShortError(error)).show(context);
        case AppUpdateStateNotAvailable():
          return CustomToast.success(t.pages.about.notAvailableMsg).show(context);
      }
    });

    final conditionalTiles = [
      if (appInfo.release.allowCustomUpdateChecker)
        ListTile(
          title: Text(t.pages.about.checkForUpdate),
          trailing: switch (appUpdate) {
            AppUpdateStateChecking() => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
            _ => const Icon(FluentIcons.arrow_sync_24_regular),
          },
          onTap: () async {
            await ref.read(appUpdateNotifierProvider.notifier).check();
          },
        ),
      if (PlatformUtils.isDesktop)
        ListTile(
          title: Text(t.pages.about.openWorkingDir),
          trailing: const Icon(FluentIcons.open_folder_24_regular),
          onTap: () async {
            final path = ref.watch(appDirectoriesProvider).requireValue.workingDir.uri;
            await UriUtils.tryLaunch(path);
          },
        ),
    ];

    final overflowMenu = PopupMenuButton(
      icon: Icon(AdaptiveIcon(context).more),
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            child: Text(t.common.addToClipboard),
            onTap: () {
              Clipboard.setData(ClipboardData(text: appInfo.format()));
            },
          ),
        ];
      },
    );

    final content = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Assets.images.appIcon.image(
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                const Gap(16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appTitle, style: Theme.of(context).textTheme.titleLarge),
                    const Gap(4),
                    Text("${t.common.version} ${appInfo.presentVersion}"),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            ...conditionalTiles,
            if (conditionalTiles.isNotEmpty) const Divider(),
            ListTile(
              title: Text(t.pages.about.sourceCode),
              trailing: const Icon(FluentIcons.open_24_regular),
              onTap: () async {
                await UriUtils.tryLaunch(Uri.parse(Constants.githubUrl));
              },
            ),
            ListTile(
              title: Text(t.pages.about.telegramChannel),
              trailing: const Icon(FluentIcons.open_24_regular),
              onTap: () async {
                await UriUtils.tryLaunch(Uri.parse(Constants.telegramChannelUrl));
              },
            ),
            ListTile(
              title: Text(t.pages.about.termsAndConditions),
              trailing: const Icon(FluentIcons.open_24_regular),
              onTap: () async {
                await UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl));
              },
            ),
            ListTile(
              title: Text(t.pages.about.privacyPolicy),
              trailing: const Icon(FluentIcons.open_24_regular),
              onTap: () async {
                await UriUtils.tryLaunch(Uri.parse(Constants.privacyPolicyUrl));
              },
            ),
          ]),
        ),
      ],
    );

    if (!asDialog) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: onClose),
          title: Text(t.pages.about.title),
          actions: [overflowMenu, const Gap(8)],
        ),
        body: content,
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text(t.pages.about.title, style: Theme.of(context).textTheme.headlineSmall)),
                  overflowMenu,
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                ],
              ),
            ),
            Flexible(child: content),
          ],
        ),
      ),
    );
  }
}
