import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
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
          errorMessage.value = repository.describeError(error);
        }
      } finally {
        isLoading.value = false;
      }
    }

    Future<void> submit() async {
      final input = inputController.text.trim();
      if (input.isEmpty) {
        errorMessage.value = '请输入域名';
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
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          await ref.read(nimbusAuthControllerProvider.notifier).restore();
        } else {
          errorMessage.value = repository.describeError(error);
        }
      } finally {
        isSubmitting.value = false;
      }
    }

    Future<void> deletePreference(NimbusRoutePreference preference) async {
      final confirmed = await _confirmDelete(context, preference);
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
          errorMessage.value = repository.describeError(error);
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
      title: const Text('访问偏好'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${items.length}/${limit == 0 ? '--' : limit} 条偏好'),
            const Gap(12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'accelerate', icon: Icon(Icons.check_circle_outline_rounded), label: Text('需要连接')),
                ButtonSegment(value: 'direct', icon: Icon(Icons.remove_circle_outline_rounded), label: Text('不需要连接')),
              ],
              selected: {selectedType.value},
              onSelectionChanged: isSubmitting.value ? null : (values) => selectedType.value = values.first,
            ),
            const Gap(12),
            TextField(
              controller: inputController,
              enabled: !isSubmitting.value && !reachedLimit,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '域名',
                hintText: 'openai.com',
                prefixIcon: Icon(Icons.language_rounded),
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
                label: Text(reachedLimit ? '已达上限' : '添加'),
              ),
            ),
            const Divider(height: 28),
            if (isLoading.value && preferences.value == null)
              const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('暂无访问偏好')),
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
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
    );
  }
}

class _RoutePreferenceTile extends StatelessWidget {
  const _RoutePreferenceTile({required this.preference, required this.isLoading, required this.onDelete});

  final NimbusRoutePreference preference;
  final bool isLoading;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(preference.requiresConnection ? Icons.check_circle_outline_rounded : Icons.remove_circle_outline),
      title: Text(preference.value, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_preferenceLabel(preference)} · ${_formatDateTime(preference.createdAt)}'),
      trailing: IconButton(
        tooltip: '删除',
        onPressed: isLoading ? null : onDelete,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, NimbusRoutePreference preference) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除访问偏好'),
          content: Text('确定删除“${preference.value}”吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
          ],
        ),
      ) ??
      false;
}

String _preferenceLabel(NimbusRoutePreference preference) => preference.requiresConnection ? '需要连接' : '不需要连接';

String _formatDateTime(DateTime? value) {
  if (value == null) return '--';
  return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)} ${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
