import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/nimbus/common/widget/yundo_brand_logo.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusAuthRestoringPage extends ConsumerWidget {
  const NimbusAuthRestoringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final environment = ref.watch(environmentProvider);
    final appTitle = environment == Environment.dev ? t.common.devAppTitle : t.common.appTitle;

    return NimbusAuthLoadingPage(appTitle: appTitle, status: t.nimbus.auth.signingIn);
  }
}

class NimbusAuthLoadingPage extends StatelessWidget {
  const NimbusAuthLoadingPage({super.key, required this.appTitle, required this.status});

  final String appTitle;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 480 || constraints.maxWidth < 320;
            final logoExtent = compact ? 80.0 : 112.0;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: '$appTitle, $status',
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        YundoBrandLogo(size: logoExtent, imageKey: const Key('nimbusAuthRestoringLogo')),
                        const Gap(24),
                        Text(
                          appTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Gap(36),
                        SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(
                            key: const Key('nimbusAuthRestoringProgress'),
                            strokeWidth: 3,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Gap(14),
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
