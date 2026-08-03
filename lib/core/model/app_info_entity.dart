import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/model/environment.dart';

part 'app_info_entity.freezed.dart';

@freezed
class AppInfoEntity with _$AppInfoEntity {
  const AppInfoEntity._();

  const factory AppInfoEntity({
    required String name,
    required String version,
    required String buildNumber,
    required Release release,
    required String operatingSystem,
    required String operatingSystemVersion,
    required Environment environment,
  }) = _AppInfoEntity;

  String get userAgent => "HiddifyNext/$version ($operatingSystem) like ClashMeta v2ray sing-box";

  String get versionWithBuild => buildNumber.isEmpty ? version : "$version+$buildNumber";

  String get presentVersion =>
      environment == Environment.prod ? versionWithBuild : "$versionWithBuild ${environment.name}";

  /// formats app info for sharing
  String format() =>
      '''
$name v$versionWithBuild [${environment.name}]
${release.name} release
$operatingSystem [$operatingSystemVersion]''';
}
