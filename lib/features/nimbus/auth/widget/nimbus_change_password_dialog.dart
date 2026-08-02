import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_input_validation.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NimbusChangePasswordDialog extends HookConsumerWidget {
  const NimbusChangePasswordDialog({super.key, this.asPage = false});

  final bool asPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final currentPasswordController = useTextEditingController();
    final newPasswordController = useTextEditingController();
    final confirmPasswordController = useTextEditingController();
    final obscureCurrentPassword = useState(true);
    final obscureNewPassword = useState(true);
    final isSubmitting = useState(false);
    final errorMessage = useState<String?>(null);
    final authState = ref.watch(nimbusAuthControllerProvider);
    final repository = ref.watch(nimbusAuthRepositoryProvider);
    final t = ref.watch(translationsProvider).requireValue;

    void clearError() => errorMessage.value = null;

    Future<void> submit() async {
      if (isSubmitting.value || !formKey.currentState!.validate()) return;
      final session = ref.read(nimbusAuthControllerProvider).session;
      if (session == null) return;

      FocusScope.of(context).unfocus();
      isSubmitting.value = true;
      errorMessage.value = null;
      try {
        await repository.changePassword(
          session: session,
          currentPassword: currentPasswordController.text,
          newPassword: newPasswordController.text,
        );
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(t.nimbus.changePassword.success)));
      } catch (error) {
        if (repository.isUnauthorized(error)) {
          final stillAuthenticated = await ref
              .read(nimbusAuthControllerProvider.notifier)
              .refreshAfterUnauthorized(session);
          if (!stillAuthenticated && context.mounted) {
            Navigator.of(context).pop();
            context.go('/auth/login');
          }
        } else {
          errorMessage.value = repository.describeError(error, t);
        }
      } finally {
        isSubmitting.value = false;
      }
    }

    if (!authState.isAuthenticated) {
      Future.microtask(() {
        if (context.mounted) {
          Navigator.of(context).pop();
          context.go('/auth/login');
        }
      });
    }

    final content = Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.nimbus.changePassword.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Gap(16),
          TextFormField(
            controller: currentPasswordController,
            enabled: !isSubmitting.value,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            obscureText: obscureCurrentPassword.value,
            inputFormatters: _passwordInputFormatters,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: t.nimbus.changePassword.currentPassword,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: obscureCurrentPassword.value ? t.nimbus.auth.showPassword : t.nimbus.auth.hidePassword,
                onPressed: () => obscureCurrentPassword.value = !obscureCurrentPassword.value,
                icon: Icon(obscureCurrentPassword.value ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              ),
            ),
            validator: (value) => _validateCurrentPassword(t, value),
            onChanged: (_) => clearError(),
          ),
          const Gap(14),
          TextFormField(
            controller: newPasswordController,
            enabled: !isSubmitting.value,
            autofillHints: const [AutofillHints.newPassword],
            obscureText: obscureNewPassword.value,
            inputFormatters: _passwordInputFormatters,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: t.nimbus.changePassword.newPassword,
              prefixIcon: const Icon(Icons.password_rounded),
              suffixIcon: IconButton(
                tooltip: obscureNewPassword.value ? t.nimbus.auth.showPassword : t.nimbus.auth.hidePassword,
                onPressed: () => obscureNewPassword.value = !obscureNewPassword.value,
                icon: Icon(obscureNewPassword.value ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              ),
            ),
            validator: (value) {
              final validation = _validateNewPassword(t, value);
              if (validation != null) return validation;
              if (value == currentPasswordController.text) {
                return t.nimbus.changePassword.passwordMustDiffer;
              }
              return null;
            },
            onChanged: (_) => clearError(),
          ),
          const Gap(14),
          TextFormField(
            controller: confirmPasswordController,
            enabled: !isSubmitting.value,
            autofillHints: const [AutofillHints.newPassword],
            obscureText: obscureNewPassword.value,
            inputFormatters: _passwordInputFormatters,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: t.nimbus.changePassword.confirmNewPassword,
              prefixIcon: const Icon(Icons.lock_reset_rounded),
            ),
            validator: (value) {
              if (value != newPasswordController.text) return t.nimbus.auth.passwordsDoNotMatch;
              return null;
            },
            onChanged: (_) => clearError(),
          ),
          if (errorMessage.value != null) ...[
            const Gap(10),
            Text(
              errorMessage.value!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );

    final cancelButton = TextButton(
      onPressed: isSubmitting.value ? null : () => Navigator.of(context).pop(),
      child: Text(t.common.cancel),
    );
    final submitButton = FilledButton.icon(
      onPressed: isSubmitting.value ? null : submit,
      icon: isSubmitting.value
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.check_rounded),
      label: Text(t.nimbus.changePassword.submit),
    );

    if (asPage) {
      return Scaffold(
        appBar: AppBar(title: Text(t.nimbus.changePassword.title)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: content),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(child: cancelButton),
              const Gap(12),
              Expanded(child: submitButton),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(t.nimbus.changePassword.title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: content),
      actions: [cancelButton, submitButton],
    );
  }
}

class NimbusChangePasswordPage extends StatelessWidget {
  const NimbusChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context) => const NimbusChangePasswordDialog(asPage: true);
}

final _passwordInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u001F\u007F]')),
  LengthLimitingTextInputFormatter(72),
];

String? _validateCurrentPassword(Translations t, String? value) {
  if (value == null || value.isEmpty) return t.nimbus.auth.passwordRequired;
  if (!isNimbusPasswordWithinByteLimit(value)) return t.nimbus.auth.passwordTooLong;
  return null;
}

String? _validateNewPassword(Translations t, String? value) {
  final password = value ?? '';
  if (password.length < 10) return t.nimbus.auth.passwordTooShort;
  if (!isNimbusPasswordWithinByteLimit(password)) return t.nimbus.auth.passwordTooLong;
  if (!RegExp('[A-Za-z]').hasMatch(password)) return t.nimbus.auth.passwordNeedsLetter;
  if (!RegExp('[0-9]').hasMatch(password)) return t.nimbus.auth.passwordNeedsNumber;
  if (!RegExp('[^A-Za-z0-9]').hasMatch(password)) return t.nimbus.auth.passwordNeedsSymbol;
  return null;
}
