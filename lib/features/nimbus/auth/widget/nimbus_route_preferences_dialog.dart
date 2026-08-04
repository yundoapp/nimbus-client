import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_input_validation.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_route_preference_logic.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_connection_controller.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_route_preferences_provider.dart';
import 'package:hiddify/features/nimbus/auth/widget/nimbus_access_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusRoutePreferencesDialog extends HookConsumerWidget {
  const NimbusRoutePreferencesDialog({super.key, this.asPage = false});

  final bool asPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final repository = ref.watch(nimbusAuthRepositoryProvider);
    final inputController = useTextEditingController();
    final selectedType = useState<String>('accelerate');
    final preferences = useState<NimbusRoutePreferencesList?>(null);
    final isLoading = useState<bool>(false);
    final isSubmitting = useState<bool>(false);
    final deletingPreferenceId = useState<String?>(null);
    final errorMessage = useState<String?>(null);
    final t = ref.watch(translationsProvider).requireValue;
    final connection = ref.watch(connectionNotifierProvider).valueOrNull;
    final connectionIsSwitching = connection?.isSwitching ?? false;

    Future<void> loadPreferences() async {
      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;
      isLoading.value = true;
      errorMessage.value = null;
      try {
        preferences.value = await repository.fetchRoutePreferences(session);
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
        } else {
          errorMessage.value = repository.describeError(error, t);
        }
      } finally {
        isLoading.value = false;
      }
    }

    Future<void> submit() async {
      final input = inputController.text.trim();
      if (input.isEmpty) {
        errorMessage.value = t.nimbus.routePreferences.domainRequired;
        return;
      }
      final domain = normalizeNimbusDomain(input);
      if (domain == null) {
        errorMessage.value = t.nimbus.routePreferences.domainInvalid;
        return;
      }

      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;

      final currentPreferences = preferences.value;
      if (currentPreferences == null) return;
      final resolution = resolveNimbusRoutePreference(
        items: currentPreferences.items,
        limit: currentPreferences.limit,
        domain: domain,
        requestedType: selectedType.value,
      );
      if (resolution.decision == NimbusRoutePreferenceDecision.duplicate) {
        errorMessage.value = t.nimbus.routePreferences.alreadyInCategory(
          category: _preferenceTypeLabel(t, selectedType.value),
        );
        return;
      }
      if (resolution.decision == NimbusRoutePreferenceDecision.limitReached) {
        errorMessage.value = t.nimbus.routePreferences.limitReached;
        return;
      }

      final existing = resolution.existing;
      if (resolution.decision == NimbusRoutePreferenceDecision.switchType && existing != null) {
        final confirmed = await _confirmSwitch(context, t, existing, selectedType.value);
        if (!confirmed || !context.mounted) return;
      }

      isSubmitting.value = true;
      errorMessage.value = null;
      try {
        if (existing == null) {
          await repository.createRoutePreference(session: session, type: selectedType.value, input: domain);
        } else {
          await repository.updateRoutePreference(session: session, id: existing.id, type: selectedType.value);
        }
        ref.invalidate(nimbusRoutePreferencesProvider);
        await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected(userRulesOnly: true);
        await loadPreferences();
        inputController.clear();
        if (context.mounted) {
          final message = existing == null
              ? t.nimbus.routePreferences.cloudSyncSaved
              : t.nimbus.routePreferences.switchSaved;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
        } else {
          final message = repository.describeError(error, t);
          final code = repository.apiErrorCode(error);
          if (code == 'ROUTE_PREFERENCE_ALREADY_ACCELERATED' ||
              code == 'ROUTE_PREFERENCE_ALREADY_DIRECT' ||
              code == 'ROUTE_PREFERENCE_CONFLICT') {
            await loadPreferences();
          }
          errorMessage.value = message;
        }
      } finally {
        isSubmitting.value = false;
      }
    }

    Future<void> deletePreference(NimbusRoutePreference preference) async {
      final confirmed = await _confirmDelete(context, t, preference);
      if (!confirmed) return;

      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;

      deletingPreferenceId.value = preference.id;
      errorMessage.value = null;
      try {
        await repository.deleteRoutePreference(session: session, id: preference.id);
        ref.invalidate(nimbusRoutePreferencesProvider);
        await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected(userRulesOnly: true);
        await loadPreferences();
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
        } else {
          errorMessage.value = repository.describeError(error, t);
        }
      } finally {
        deletingPreferenceId.value = null;
      }
    }

    useEffect(() {
      Future.microtask(loadPreferences);
      return null;
    }, [authState.session?.accessToken]);

    if (!authState.isAuthenticated) {
      Future.microtask(() {
        if (context.mounted) {
          Navigator.of(context).pop();
          context.go('/auth/login');
        }
      });
    }

    final items = preferences.value?.items ?? const <NimbusRoutePreference>[];
    final limit = preferences.value?.limit ?? 0;
    final formReady = preferences.value != null;
    final mutationInProgress = isSubmitting.value || deletingPreferenceId.value != null;
    final theme = Theme.of(context);
    final secondaryTextStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final estimatedFormWidth = MediaQuery.sizeOf(context).width - (asPage ? 32 : 128);
    final compactForm = estimatedFormWidth < 460;
    final dialogContentWidth = (MediaQuery.sizeOf(context).width - 128).clamp(280.0, 520.0);

    final content = Column(
      mainAxisSize: asPage ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(
          builder: (context) {
            final compact = compactForm;
            final input = TextField(
              controller: inputController,
              enabled: !mutationInProgress && !connectionIsSwitching && formReady,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(nimbusDomainMaxLength)],
              decoration: compact
                  ? InputDecoration(
                      isDense: true,
                      labelText: t.nimbus.routePreferences.domainLabel,
                      hintText: 'openai.com',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    )
                  : const InputDecoration(isDense: true, hintText: 'openai.com'),
              onChanged: (_) => errorMessage.value = null,
              onSubmitted: (_) => mutationInProgress || connectionIsSwitching || !formReady ? null : submit(),
            );
            final addButton = compact
                ? SizedBox.square(
                    dimension: 56,
                    child: Tooltip(
                      message: t.nimbus.routePreferences.add,
                      child: IconButton.filled(
                        onPressed: mutationInProgress || connectionIsSwitching || !formReady ? null : submit,
                        icon: isSubmitting.value
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_rounded),
                      ),
                    ),
                  )
                : SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: mutationInProgress || connectionIsSwitching || !formReady ? null : submit,
                      icon: isSubmitting.value
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_rounded),
                      label: Text(t.nimbus.routePreferences.add),
                    ),
                  );
            final typeOptions = Row(
              children: [
                Expanded(
                  child: _RoutePreferenceTypeRadio(
                    value: 'accelerate',
                    label: t.nimbus.routePreferences.requiresConnection,
                    icon: nimbusRouteAccessIcon(requiresConnection: true),
                    color: theme.colorScheme.primary,
                    enabled: !mutationInProgress && !connectionIsSwitching,
                  ),
                ),
                Expanded(
                  child: _RoutePreferenceTypeRadio(
                    value: 'direct',
                    label: t.nimbus.routePreferences.directConnection,
                    icon: Icons.language_rounded,
                    color: theme.colorScheme.tertiary,
                    enabled: !mutationInProgress && !connectionIsSwitching,
                  ),
                ),
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: compact
                      ? [Expanded(child: SizedBox(height: 56, child: input)), const Gap(8), addButton]
                      : [
                          SizedBox(
                            width: 88,
                            child: Text(t.nimbus.routePreferences.domainLabel, style: theme.textTheme.labelLarge),
                          ),
                          const Gap(8),
                          Expanded(child: input),
                          const Gap(8),
                          addButton,
                        ],
                ),
                if (errorMessage.value != null) ...[
                  const Gap(8),
                  Padding(
                    padding: EdgeInsetsDirectional.only(start: compact ? 0 : 96),
                    child: Text(
                      errorMessage.value!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
                Gap(compact ? 10 : 8),
                RadioGroup<String>(
                  groupValue: selectedType.value,
                  onChanged: (value) {
                    if (!mutationInProgress && !connectionIsSwitching && value != null) {
                      selectedType.value = value;
                    }
                  },
                  child: compact
                      ? typeOptions
                      : Row(
                          children: [
                            SizedBox(
                              width: 88,
                              child: Text(t.nimbus.routePreferences.accessMethod, style: theme.textTheme.labelLarge),
                            ),
                            const Gap(8),
                            Expanded(child: typeOptions),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
        const Gap(4),
        _CloudSyncHint(message: t.nimbus.routePreferences.cloudSyncHint),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(child: Text(t.nimbus.routePreferences.addedWebsites, style: theme.textTheme.titleSmall)),
            Text(
              t.nimbus.routePreferences.count(used: items.length, limit: limit == 0 ? '--' : limit),
              style: secondaryTextStyle,
            ),
          ],
        ),
        const Gap(4),
        if (isLoading.value && preferences.value == null)
          const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text(t.nimbus.routePreferences.empty)),
          )
        else
          Flexible(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _RoutePreferenceTile(
                preference: items[index],
                isDisabled: isLoading.value || mutationInProgress || connectionIsSwitching,
                isDeleting: deletingPreferenceId.value == items[index].id,
                onDelete: () => deletePreference(items[index]),
              ),
            ),
          ),
      ],
    );

    if (asPage) {
      return Scaffold(
        appBar: AppBar(title: Text(t.nimbus.routePreferences.title)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: content),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(t.nimbus.routePreferences.title),
      content: SizedBox(
        width: dialogContentWidth,
        child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 560), child: content),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.close))],
    );
  }
}

class NimbusRoutePreferencesPage extends StatelessWidget {
  const NimbusRoutePreferencesPage({super.key});

  @override
  Widget build(BuildContext context) => const NimbusRoutePreferencesDialog(asPage: true);
}

class _RoutePreferenceTypeRadio extends StatelessWidget {
  const _RoutePreferenceTypeRadio({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      value: value,
      enabled: enabled,
      dense: true,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Icon(icon, size: 18, color: enabled ? color : Theme.of(context).disabledColor),
          const Gap(6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(label, maxLines: 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudSyncHint extends StatelessWidget {
  const _CloudSyncHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cloud_done_rounded, size: 18, color: colorScheme.primary),
        const Gap(8),
        Expanded(
          child: Text(message, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _RoutePreferenceTile extends ConsumerWidget {
  const _RoutePreferenceTile({
    required this.preference,
    required this.isDisabled,
    required this.isDeleting,
    required this.onDelete,
  });

  final NimbusRoutePreference preference;
  final bool isDisabled;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final colorScheme = Theme.of(context).colorScheme;
    final preferenceColor = preference.requiresConnection ? colorScheme.primary : colorScheme.tertiary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(nimbusRouteAccessIcon(requiresConnection: preference.requiresConnection), color: preferenceColor),
      title: Text(preference.value, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_preferenceLabel(t, preference)} · ${_formatDateTime(preference.createdAt)}'),
      trailing: IconButton(
        tooltip: t.nimbus.routePreferences.deleteTooltip,
        onPressed: isDisabled ? null : onDelete,
        icon: isDeleting
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.delete_outline_rounded),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, Translations t, NimbusRoutePreference preference) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.nimbus.routePreferences.deleteTitle),
          content: Text(t.nimbus.routePreferences.deleteConfirm(value: preference.value)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.common.cancel)),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(t.common.delete)),
          ],
        ),
      ) ??
      false;
}

Future<bool> _confirmSwitch(
  BuildContext context,
  Translations t,
  NimbusRoutePreference preference,
  String requestedType,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.nimbus.routePreferences.switchTitle),
          content: Text(
            t.nimbus.routePreferences.switchConfirm(
              domain: preference.value,
              from: _preferenceTypeLabel(t, preference.type),
              to: _preferenceTypeLabel(t, requestedType),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.common.cancel)),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.nimbus.routePreferences.switchAction),
            ),
          ],
        ),
      ) ??
      false;
}

String _preferenceLabel(Translations t, NimbusRoutePreference preference) => preference.requiresConnection
    ? t.nimbus.routePreferences.requiresConnection
    : t.nimbus.routePreferences.directConnection;

String _preferenceTypeLabel(Translations t, String type) =>
    type == 'accelerate' ? t.nimbus.routePreferences.requiresConnection : t.nimbus.routePreferences.directConnection;

String _formatDateTime(DateTime? value) {
  if (value == null) return '--';
  return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)} ${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class NimbusRoutePreferenceEditorDialog extends HookConsumerWidget {
  const NimbusRoutePreferenceEditorDialog({super.key, this.preference});

  final NimbusRoutePreference? preference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final repository = ref.watch(nimbusAuthRepositoryProvider);
    final inputController = useTextEditingController(text: preference?.value ?? '');
    final selectedTargetType = useState(preference?.targetType ?? 'domain');
    final selectedAction = useState(preference?.type ?? 'accelerate');
    final error = useState<String?>(null);
    final isSubmitting = useState(false);
    final isDeleting = useState(false);
    final connection = ref.watch(connectionNotifierProvider).valueOrNull;
    final disabled = isSubmitting.value || isDeleting.value || (connection?.isSwitching ?? false);
    final editing = preference != null;

    Future<void> save() async {
      final normalized = normalizeNimbusRuleTarget(inputController.text, selectedTargetType.value);
      if (normalized == null) {
        error.value = t.nimbus.routePreferences.targetInvalid;
        return;
      }
      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;
      isSubmitting.value = true;
      error.value = null;
      try {
        if (preference == null) {
          await repository.createRoutePreference(
            session: session,
            type: selectedAction.value,
            targetType: selectedTargetType.value,
            input: normalized,
          );
        } else {
          await repository.updateRoutePreference(
            session: session,
            id: preference!.id,
            type: selectedAction.value,
            targetType: selectedTargetType.value,
            input: normalized,
          );
        }
        ref.invalidate(nimbusRoutePreferencesProvider);
        await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected(userRulesOnly: true);
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (exception) {
        if (repository.isUnauthorized(exception)) {
          await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
        } else {
          error.value = repository.describeError(exception, t);
        }
      } finally {
        if (context.mounted) isSubmitting.value = false;
      }
    }

    Future<void> delete() async {
      final current = preference;
      if (current == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.nimbus.routePreferences.deleteTitle),
          content: Text(t.nimbus.routePreferences.deleteConfirm(value: current.value)),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(t.common.cancel)),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(t.common.delete)),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;
      isDeleting.value = true;
      error.value = null;
      try {
        await repository.deleteRoutePreference(session: session, id: current.id);
        ref.invalidate(nimbusRoutePreferencesProvider);
        await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected(userRulesOnly: true);
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (exception) {
        if (repository.isUnauthorized(exception)) {
          await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
        } else {
          error.value = repository.describeError(exception, t);
        }
      } finally {
        if (context.mounted) isDeleting.value = false;
      }
    }

    final targetTypes = <String, String>{
      'domain': t.nimbus.routePreferences.domainType,
      'ip': t.nimbus.routePreferences.ipType,
      'cidr': t.nimbus.routePreferences.cidrType,
    };

    return AlertDialog(
      title: Text(editing ? t.nimbus.rules.editRule : t.nimbus.rules.addRule),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: selectedTargetType.value,
                decoration: InputDecoration(labelText: t.nimbus.routePreferences.targetType),
                items: [
                  for (final entry in targetTypes.entries)
                    DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: disabled ? null : (value) => value == null ? null : selectedTargetType.value = value,
              ),
              const Gap(12),
              TextField(
                controller: inputController,
                enabled: !disabled,
                autofocus: !editing,
                keyboardType: selectedTargetType.value == 'domain' ? TextInputType.url : TextInputType.text,
                inputFormatters: [LengthLimitingTextInputFormatter(nimbusDomainMaxLength)],
                decoration: InputDecoration(
                  labelText: t.nimbus.routePreferences.targetValue,
                  hintText: t.nimbus.routePreferences.targetHint,
                  errorText: error.value,
                ),
                onChanged: (_) => error.value = null,
                onSubmitted: (_) => save(),
              ),
              const Gap(16),
              Text(t.nimbus.routePreferences.accessMethod, style: Theme.of(context).textTheme.labelLarge),
              RadioGroup<String>(
                groupValue: selectedAction.value,
                onChanged: (value) {
                  if (!disabled && value != null) selectedAction.value = value;
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'accelerate',
                      title: Row(
                        children: [
                          Icon(
                            nimbusRouteAccessIcon(requiresConnection: true),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const Gap(8),
                          Text(t.nimbus.routePreferences.requiresConnection),
                        ],
                      ),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'direct',
                      title: Row(
                        children: [
                          Icon(
                            nimbusRouteAccessIcon(requiresConnection: false),
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                          const Gap(8),
                          Text(t.nimbus.routePreferences.directConnection),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isSubmitting.value || isDeleting.value) ...[
                const Gap(4),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton.icon(
            onPressed: disabled ? null : delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(t.common.delete),
          ),
        const Spacer(),
        TextButton(onPressed: disabled ? null : () => Navigator.of(context).pop(), child: Text(t.common.cancel)),
        FilledButton.icon(
          onPressed: disabled ? null : save,
          icon: isSubmitting.value
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: Text(t.common.save),
        ),
      ],
    );
  }
}
