import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_app_version_controller.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_app_version_dialog.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final appTitle = ref.watch(appDisplayNameProvider);
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final appVersion = ref.watch(nimbusAppVersionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.about.title)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/app_icon.png', width: 64, height: 64),
                  const Gap(16),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(appTitle, style: Theme.of(context).textTheme.titleLarge),
                        const Gap(4),
                        Text("${t.common.version} ${appInfo.presentVersion}"),
                        const Gap(4),
                        Text(t.pages.about.openSourceNotice, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              ListTile(
                title: Text(t.pages.about.checkForUpdate),
                trailing: appVersion.isChecking
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                    : const Icon(FluentIcons.arrow_sync_24_regular),
                onTap: appVersion.isChecking
                    ? null
                    : () async {
                        final result = await ref.read(nimbusAppVersionControllerProvider.notifier).check(force: true);
                        if (!context.mounted) return;
                        if (result == null) {
                          CustomToast.error(
                            ref.read(nimbusAppVersionControllerProvider).errorMessage ??
                                t.nimbus.common.operationFailed,
                          ).show(context);
                        } else if (result.updateAvailable) {
                          await showDialog<void>(
                            context: context,
                            barrierDismissible: !result.forceUpdate,
                            builder: (_) => NimbusAppVersionDialog(version: result),
                          );
                        } else {
                          CustomToast.success(t.pages.about.notAvailableMsg).show(context);
                        }
                      },
              ),
              const Divider(),
              ListTile(
                title: Text(t.pages.about.sourceCode),
                trailing: const Icon(FluentIcons.open_24_regular),
                onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.githubUrl)),
              ),
              ListTile(
                title: Text(t.pages.about.license),
                trailing: const Icon(FluentIcons.open_24_regular),
                onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.licenseUrl)),
              ),
              ListTile(
                title: Text(t.pages.about.termsAndConditions),
                trailing: const Icon(FluentIcons.open_24_regular),
                onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl)),
              ),
              ListTile(
                title: Text(t.pages.about.privacyPolicy),
                trailing: const Icon(FluentIcons.open_24_regular),
                onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.privacyPolicyUrl)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
