#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
pubspec_version="$(awk -F'[:+ ]+' '/^version: / { print $2; exit }' "${repo_root}/pubspec.yaml")"
pubspec_build_number="$(awk -F+ '/^version: / { print $2; exit }' "${repo_root}/pubspec.yaml")"
build_number="${YUNDO_BUILD_NUMBER:-${pubspec_build_number}}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
team_id="${APPLE_TEAM_ID:-W684N2R45F}"
bundle_id="${IOS_BUNDLE_IDENTIFIER:-app.yundo.client}"
signing_identity="${IOS_CODESIGN_IDENTITY:-Apple Distribution}"
auth_key_path="${APPSTORE_AUTH_KEY_PATH:-}"
auth_key_id="${APPSTORE_API_KEY_ID:-}"
auth_issuer_id="${APPSTORE_ISSUER_ID:-}"
output_dir="${YUNDO_OUTPUT_DIR:-${repo_root}/out}"
archive_path="${repo_root}/build/ios/archive/Yundo.xcarchive"
export_path="${repo_root}/build/ios/export"

fail() {
  echo "错误：$*" >&2
  exit 1
}

[[ "${build_number}" =~ ^[0-9]+$ ]] || fail "构建号必须是纯数字：${build_number}"
[[ -d "${developer_dir}" ]] || fail "找不到 Xcode Developer 目录：${developer_dir}"
[[ -x "${flutter_bin}" ]] || fail "找不到 Flutter；请设置 FLUTTER_BIN"
[[ -n "${auth_key_path}" && -f "${auth_key_path}" ]] \
  || fail "远程 iOS 构建需要 APPSTORE_AUTH_KEY_PATH 指向 .p8 文件"
[[ -n "${auth_key_id}" ]] || fail "缺少 APPSTORE_API_KEY_ID"
[[ -n "${auth_issuer_id}" ]] || fail "缺少 APPSTORE_ISSUER_ID"

export DEVELOPER_DIR="${developer_dir}"
cd "${repo_root}"
mkdir -p "${output_dir}"
rm -rf "${archive_path}" "${export_path}"

# 先让 Flutter 生成框架和 Pods，再由 xcodebuild 负责真正的设备归档与签名。
make ios-prepare
"${flutter_bin}" build ios --release --no-codesign \
  --target=lib/main_prod.dart \
  --build-number="${build_number}"

xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath "${archive_path}" \
  BASE_BUNDLE_IDENTIFIER="${bundle_id}" \
  DEVELOPMENT_TEAM="${team_id}" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="${signing_identity}" \
  FLUTTER_BUILD_NUMBER="${build_number}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${auth_key_path}" \
  -authenticationKeyID "${auth_key_id}" \
  -authenticationKeyIssuerID "${auth_issuer_id}" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist ios/exportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${auth_key_path}" \
  -authenticationKeyID "${auth_key_id}" \
  -authenticationKeyIssuerID "${auth_issuer_id}"

ipa="${export_path}/Runner.ipa"
[[ -f "${ipa}" ]] || fail "xcodebuild 未生成 Runner.ipa"
artifact="${output_dir}/Yundo-iOS-${pubspec_version}-build${build_number}-signed.ipa"
cp "${ipa}" "${artifact}"

inspect_dir="$(mktemp -d "${TMPDIR:-/tmp}/yundo-ios-inspect.XXXXXX")"
trap 'rm -rf "${inspect_dir}"' EXIT
ditto -x -k "${artifact}" "${inspect_dir}"
app_path="$(find "${inspect_dir}/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "${app_path}" ]] || fail "IPA 内缺少主 App"
actual_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${app_path}/Info.plist")"
[[ "${actual_bundle_id}" == "${bundle_id}" ]] || fail "IPA Bundle ID 不正确：${actual_bundle_id}"
packet_bundle_id="${bundle_id}.PacketTunnel"
packet_path="$(find "${app_path}/PlugIns" -maxdepth 1 -type d -name '*.appex' -print -quit)"
[[ -n "${packet_path}" ]] || fail "IPA 内缺少 Packet Tunnel 扩展"
actual_packet_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${packet_path}/Info.plist")"
[[ "${actual_packet_bundle_id}" == "${packet_bundle_id}" ]] \
  || fail "Packet Tunnel Bundle ID 不正确：${actual_packet_bundle_id}"
codesign --verify --deep --strict "${app_path}"
shasum -a 256 "${artifact}"
echo "iOS 远程签名产物：${artifact}"
