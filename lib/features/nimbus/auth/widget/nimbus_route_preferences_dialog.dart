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
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusRoutePreferencesDialog extends HookConsumerWidget {
  const NimbusRoutePreferencesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(nimbusAuthControllerProvider);
    final repository = ref.watch(nimbusAuthRepositoryProvider);
    final inputController = useTextEditingController();
    final selectedType = useState<String>('accelerate');
    final preferences = useState<NimbusRoutePreferencesList?>(null);
    final isLoading = useState<bool>(false);
    final isSubmitting = useState<bool>(false);
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

      isSubmitting.value = true;
      errorMessage.value = null;
      try {
        await repository.deleteRoutePreference(session: session, id: preference.id);
        await ref.read(nimbusConnectionControllerProvider.notifier).reapplyIfConnected(userRulesOnly: true);
        await loadPreferences();
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).refreshAfterUnauthorized(session);
        } else {
          errorMessage.value = repository.describeError(error, t);
        }
      } finally {
        isSubmitting.value = false;
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

    return AlertDialog(
      title: Text(t.nimbus.routePreferences.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 520, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.nimbus.routePreferences.count(used: items.length, limit: limit == 0 ? '--' : limit)),
            const Gap(12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'accelerate',
                  icon: const Icon(Icons.cloud_outlined),
                  label: Text(t.nimbus.routePreferences.requiresConnection),
                ),
                ButtonSegment(
                  value: 'direct',
                  icon: const Icon(Icons.language_rounded),
                  label: Text(t.nimbus.routePreferences.directConnection),
                ),
              ],
              selected: {selectedType.value},
              onSelectionChanged: isSubmitting.value || connectionIsSwitching
                  ? null
                  : (values) => selectedType.value = values.first,
            ),
            const Gap(8),
            Text(
              selectedType.value == 'accelerate'
                  ? t.nimbus.routePreferences.requiresConnectionDescription
                  : t.nimbus.routePreferences.directConnectionDescription,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Gap(12),
            _CloudSyncHint(message: t.nimbus.routePreferences.cloudSyncHint),
            const Gap(12),
            TextField(
              controller: inputController,
              enabled: !isSubmitting.value && !connectionIsSwitching && formReady,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(nimbusDomainMaxLength)],
              decoration: InputDecoration(
                labelText: t.nimbus.routePreferences.domainLabel,
                hintText: 'openai.com',
                prefixIcon: const Icon(Icons.language_rounded),
              ),
              onChanged: (_) => errorMessage.value = null,
              onSubmitted: (_) => isSubmitting.value || connectionIsSwitching || !formReady ? null : submit(),
            ),
            if (errorMessage.value != null) ...[
              const Gap(10),
              Text(
                errorMessage.value!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Gap(12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: isSubmitting.value || connectionIsSwitching || !formReady ? null : submit,
                icon: isSubmitting.value
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_rounded),
                label: Text(t.nimbus.routePreferences.add),
              ),
            ),
            const Divider(height: 28),
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
                    isLoading: isLoading.value || isSubmitting.value || connectionIsSwitching,
                    onDelete: () => deletePreference(items[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.close))],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_done_rounded, size: 20, color: colorScheme.primary),
            const Gap(10),
            Expanded(
              child: Text(message, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePreferenceTile extends ConsumerWidget {
  const _RoutePreferenceTile({required this.preference, required this.isLoading, required this.onDelete});

  final NimbusRoutePreference preference;
  final bool isLoading;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(preference.requiresConnection ? Icons.cloud_outlined : Icons.language_rounded),
      title: Text(preference.value, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_preferenceLabel(t, preference)} · ${_formatDateTime(preference.createdAt)}'),
      trailing: IconButton(
        tooltip: t.nimbus.routePreferences.deleteTooltip,
        onPressed: isLoading ? null : onDelete,
        icon: const Icon(Icons.delete_outline_rounded),
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
