import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
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

    Future<void> loadPreferences() async {
      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;
      isLoading.value = true;
      errorMessage.value = null;
      try {
        preferences.value = await repository.fetchRoutePreferences(session);
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).restore();
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

      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;

      isSubmitting.value = true;
      errorMessage.value = null;
      try {
        await repository.createRoutePreference(session: session, type: selectedType.value, input: input);
        inputController.clear();
        await loadPreferences();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.nimbus.routePreferences.cloudSyncSaved)));
        }
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).restore();
        } else {
          errorMessage.value = repository.describeError(error, t);
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
        await loadPreferences();
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).restore();
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
    final reachedLimit = limit > 0 && items.length >= limit;

    return AlertDialog(
      title: Text(t.nimbus.routePreferences.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
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
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(t.nimbus.routePreferences.requiresConnection),
                ),
                ButtonSegment(
                  value: 'direct',
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  label: Text(t.nimbus.routePreferences.directConnection),
                ),
              ],
              selected: {selectedType.value},
              onSelectionChanged: isSubmitting.value ? null : (values) => selectedType.value = values.first,
            ),
            const Gap(12),
            _CloudSyncHint(message: t.nimbus.routePreferences.cloudSyncHint),
            const Gap(12),
            TextField(
              controller: inputController,
              enabled: !isSubmitting.value && !reachedLimit,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: t.nimbus.routePreferences.domainLabel,
                hintText: 'openai.com',
                prefixIcon: const Icon(Icons.language_rounded),
              ),
              onChanged: (_) => errorMessage.value = null,
              onSubmitted: (_) => reachedLimit || isSubmitting.value ? null : submit(),
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
                onPressed: reachedLimit || isSubmitting.value ? null : submit,
                icon: isSubmitting.value
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_rounded),
                label: Text(reachedLimit ? t.nimbus.routePreferences.limitReached : t.nimbus.routePreferences.add),
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
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _RoutePreferenceTile(
                    preference: items[index],
                    isLoading: isLoading.value || isSubmitting.value,
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
      leading: Icon(preference.requiresConnection ? Icons.check_circle_outline_rounded : Icons.remove_circle_outline),
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

String _preferenceLabel(Translations t, NimbusRoutePreference preference) => preference.requiresConnection
    ? t.nimbus.routePreferences.requiresConnection
    : t.nimbus.routePreferences.directConnection;

String _formatDateTime(DateTime? value) {
  if (value == null) return '--';
  return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)} ${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
