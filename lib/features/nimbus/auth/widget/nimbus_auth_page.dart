import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/nimbus/auth/notifier/nimbus_auth_controller.dart';
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
    final acceptedTerms = useState(true);
    final obscurePassword = useState(true);
    final authState = ref.watch(nimbusAuthControllerProvider);
    final isRegister = mode.value == NimbusAuthMode.register;

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
                    Icon(Icons.cloud_done_rounded, size: 44, color: theme.colorScheme.primary),
                    const Gap(16),
                    Text(
                      isRegister ? '注册 Nimbus' : '登录 Nimbus',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Gap(6),
                    Text(
                      isRegister ? '创建账号后再使用激活码开通套餐' : '登录后即可查看套餐、流量和设备',
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
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: _validateUsername,
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
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: obscurePassword.value ? '显示密码' : '隐藏密码',
                          onPressed: () => obscurePassword.value = !obscurePassword.value,
                          icon: Icon(obscurePassword.value ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                        ),
                      ),
                      validator: (value) => isRegister ? _validateNewPassword(value) : _validatePassword(value),
                    ),
                    if (isRegister) ...[
                      const Gap(14),
                      TextFormField(
                        controller: confirmPasswordController,
                        autofillHints: const [AutofillHints.newPassword],
                        obscureText: obscurePassword.value,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        decoration: const InputDecoration(
                          labelText: '确认密码',
                          prefixIcon: Icon(Icons.lock_reset_rounded),
                        ),
                        validator: (value) {
                          if (value != passwordController.text) return '两次输入的密码不一致';
                          return null;
                        },
                      ),
                      const Gap(8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: acceptedTerms.value,
                        onChanged: (value) => acceptedTerms.value = value ?? false,
                        title: const Text('我确认已了解使用说明'),
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
                      onPressed: authState.isLoading ? null : submit,
                      child: authState.isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(isRegister ? '注册并登录' : '登录'),
                    ),
                    const Gap(10),
                    TextButton(
                      onPressed: authState.isLoading
                          ? null
                          : () {
                              mode.value = isRegister ? NimbusAuthMode.login : NimbusAuthMode.register;
                              formKey.currentState?.reset();
                            },
                      child: Text(isRegister ? '已有账号，去登录' : '没有账号，去注册'),
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

String? _validateUsername(String? value) {
  final username = value?.trim() ?? '';
  if (!RegExp(r'^[A-Za-z0-9_]{4,32}$').hasMatch(username)) {
    return '用户名需为 4-32 位字母、数字或下划线';
  }
  return null;
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) return '请输入密码';
  return null;
}

String? _validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.length < 10) return '密码至少 10 位';
  if (!RegExp('[A-Za-z]').hasMatch(password)) return '密码需要包含字母';
  if (!RegExp('[0-9]').hasMatch(password)) return '密码需要包含数字';
  if (!RegExp('[^A-Za-z0-9]').hasMatch(password)) return '密码需要包含特殊字符';
  return null;
}
