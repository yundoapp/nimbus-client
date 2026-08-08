import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_input_validation.dart';

String? validateNimbusUsername(Translations t, String? value, {required bool allowLegacyUnderscore}) {
  final username = value?.trim() ?? '';
  final pattern = allowLegacyUnderscore ? RegExp(r'^[A-Za-z0-9_]{4,32}$') : RegExp(r'^[A-Za-z0-9]{4,32}$');
  if (!pattern.hasMatch(username)) return t.nimbus.auth.usernameInvalid;
  return null;
}

String? validateNimbusNewPassword(Translations t, String? value) {
  final password = value ?? '';
  if (password.length < 8) return t.nimbus.auth.passwordTooShort;
  if (!isNimbusPasswordWithinByteLimit(password)) return t.nimbus.auth.passwordTooLong;
  if (!RegExp('[A-Z]').hasMatch(password)) return t.nimbus.auth.passwordNeedsUppercase;
  if (!RegExp('[a-z]').hasMatch(password)) return t.nimbus.auth.passwordNeedsLowercase;
  if (!RegExp('[0-9]').hasMatch(password)) return t.nimbus.auth.passwordNeedsNumber;
  if (!RegExp(r'[!-/:-@\[-`{-~]').hasMatch(password)) return t.nimbus.auth.passwordNeedsSymbol;
  return null;
}
