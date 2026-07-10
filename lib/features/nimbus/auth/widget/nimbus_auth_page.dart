import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum NimbusAuthMode { login, register }

class NimbusAuthPage extends HookConsumerWidget {
  const NimbusAuthPage({super.key, required this.initialMode});

  final NimbusAuthMode initialMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = useState(initialMode);
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final usernameController = useTextEditingController();
    final passwordController = useTextEditingController();
    final confirmPasswordController = useTextEditingController();
    final acceptedTerms = useState(false);
    final obscurePassword = useState(true);
    final authState = ref.watch(nimbusAuthControllerProvider);
    final isRegister = mode.value == NimbusAuthMode.register;
    final t = ref.watch(translationsProvider).requireValue;
    final appTitle = t.common.appTitle;

    Future<void> submit() async {
      if (authState.isLoading) return;
      if (!formKey.currentState!.validate()) return;
      FocusScope.of(context).unfocus();

      final controller = ref.read(nimbusAuthControllerProvider.notifier);
      final success = isRegister
          ? await controller.register(
              username: usernameController.text.trim(),
              password: passwordController.text,
              acceptedTerms: acceptedTerms.value,
            )
          : await controller.login(username: usernameController.text.trim(), password: passwordController.text);

      if (success && context.mounted) context.go('/home');
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/images/app_icon.png', width: 56, height: 56),
                    const Gap(16),
                    Text(
                      isRegister
                          ? t.nimbus.auth.registerTitle(appTitle: appTitle)
                          : t.nimbus.auth.loginTitle(appTitle: appTitle),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Gap(6),
                    Text(
                      isRegister ? t.nimbus.auth.registerSubtitle : t.nimbus.auth.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const Gap(28),
                    TextFormField(
                      controller: usernameController,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]')),
                        LengthLimitingTextInputFormatter(32),
                      ],
                      decoration: InputDecoration(
                        labelText: t.nimbus.auth.username,
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) => _validateUsername(t, value),
                    ),
                    const Gap(14),
                    TextFormField(
                      controller: passwordController,
                      autofillHints: [if (isRegister) AutofillHints.newPassword else AutofillHints.password],
                      obscureText: obscurePassword.value,
                      textInputAction: isRegister ? TextInputAction.next : TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!isRegister) submit();
                      },
                      decoration: InputDecoration(
                        labelText: t.nimbus.auth.password,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: obscurePassword.value ? t.nimbus.auth.showPassword : t.nimbus.auth.hidePassword,
                          onPressed: () => obscurePassword.value = !obscurePassword.value,
                          icon: Icon(obscurePassword.value ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                        ),
                      ),
                      validator: (value) => isRegister ? _validateNewPassword(t, value) : _validatePassword(t, value),
                    ),
                    if (isRegister) ...[
                      const Gap(14),
                      TextFormField(
                        controller: confirmPasswordController,
                        autofillHints: const [AutofillHints.newPassword],
                        obscureText: obscurePassword.value,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: t.nimbus.auth.confirmPassword,
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                        ),
                        validator: (value) {
                          if (value != passwordController.text) return t.nimbus.auth.passwordsDoNotMatch;
                          return null;
                        },
                      ),
                      const Gap(8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: acceptedTerms.value,
                        onChanged: (value) => acceptedTerms.value = value ?? false,
                        title: Text(t.nimbus.auth.acceptTerms),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl));
                            },
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: Text(t.pages.about.termsAndConditions),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await UriUtils.tryLaunch(Uri.parse(Constants.privacyPolicyUrl));
                            },
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: Text(t.pages.about.privacyPolicy),
                          ),
                        ],
                      ),
                    ],
                    if (authState.errorMessage != null) ...[
                      const Gap(10),
                      Text(
                        authState.errorMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                    const Gap(18),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: authState.isLoading || (isRegister && !acceptedTerms.value) ? null : submit,
                      child: authState.isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(isRegister ? t.nimbus.auth.registerAndLogin : t.nimbus.auth.login),
                    ),
                    const Gap(10),
                    TextButton(
                      onPressed: authState.isLoading
                          ? null
                          : () {
                              mode.value = isRegister ? NimbusAuthMode.login : NimbusAuthMode.register;
                              formKey.currentState?.reset();
                            },
                      child: Text(isRegister ? t.nimbus.auth.goLogin : t.nimbus.auth.goRegister),
                    ),
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

String? _validateUsername(Translations t, String? value) {
  final username = value?.trim() ?? '';
  if (!RegExp(r'^[A-Za-z0-9_]{4,32}$').hasMatch(username)) {
    return t.nimbus.auth.usernameInvalid;
  }
  return null;
}

String? _validatePassword(Translations t, String? value) {
  if (value == null || value.isEmpty) return t.nimbus.auth.passwordRequired;
  return null;
}

String? _validateNewPassword(Translations t, String? value) {
  final password = value ?? '';
  if (password.length < 10) return t.nimbus.auth.passwordTooShort;
  if (!RegExp('[A-Za-z]').hasMatch(password)) return t.nimbus.auth.passwordNeedsLetter;
  if (!RegExp('[0-9]').hasMatch(password)) return t.nimbus.auth.passwordNeedsNumber;
  if (!RegExp('[^A-Za-z0-9]').hasMatch(password)) return t.nimbus.auth.passwordNeedsSymbol;
  return null;
}
