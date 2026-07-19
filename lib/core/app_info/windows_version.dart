import 'dart:io';

const _windowsCurrentVersionKey = r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion';

Future<String> resolveOperatingSystemVersion() async {
  final fallback = Platform.operatingSystemVersion;
  if (!Platform.isWindows) return fallback;

  try {
    final result = await Process.run('reg.exe', const ['query', _windowsCurrentVersionKey]);
    if (result.exitCode != 0) return fallback;
    final values = parseWindowsCurrentVersionRegistry(result.stdout.toString());
    return formatWindowsVersion(values, fallback: fallback);
  } catch (_) {
    return fallback;
  }
}

Map<String, String> parseWindowsCurrentVersionRegistry(String output) {
  const supportedNames = {'ProductName', 'DisplayVersion', 'CurrentBuildNumber', 'CurrentBuild', 'UBR'};
  final values = <String, String>{};
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'^\s*([^\s]+)\s+REG_[A-Z0-9_]+\s+(.+?)\s*$').firstMatch(line);
    if (match == null || !supportedNames.contains(match.group(1))) continue;
    values[match.group(1)!] = match.group(2)!;
  }
  return values;
}

String formatWindowsVersion(Map<String, String> values, {required String fallback}) {
  final build = int.tryParse(values['CurrentBuildNumber'] ?? values['CurrentBuild'] ?? '');
  if (build == null) return fallback;

  var productName = values['ProductName']?.trim() ?? '';
  if (build >= 22000) {
    productName = productName.replaceFirst(RegExp(r'Windows\s+10', caseSensitive: false), 'Windows 11');
    if (!productName.toLowerCase().contains('windows 11')) productName = 'Windows 11';
  } else if (productName.isEmpty) {
    productName = 'Windows 10';
  }

  final displayVersion = values['DisplayVersion']?.trim();
  final rawUbr = values['UBR']?.trim();
  final ubr = rawUbr == null
      ? null
      : rawUbr.toLowerCase().startsWith('0x')
      ? int.tryParse(rawUbr.substring(2), radix: 16)
      : int.tryParse(rawUbr);
  final fullBuild = ubr == null ? '$build' : '$build.$ubr';
  return [
    productName,
    if (displayVersion != null && displayVersion.isNotEmpty) displayVersion,
    '(Build $fullBuild)',
  ].join(' ');
}
