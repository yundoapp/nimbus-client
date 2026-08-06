#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
channel="${YUNDO_CHANNEL:-prod}"
pubspec_version="$(awk -F'[:+ ]+' '/^version: / { print $2; exit }' "${repo_root}/pubspec.yaml")"
pubspec_build_number="$(awk -F+ '/^version: / { print $2; exit }' "${repo_root}/pubspec.yaml")"
build_number="${YUNDO_BUILD_NUMBER:-${pubspec_build_number}}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
codesign_identity="${MACOS_CODESIGN_IDENTITY:-}"
output_dir="${YUNDO_OUTPUT_DIR:-${repo_root}/out}"

fail() {
  echo "错误：$*" >&2
  exit 1
}

case "${channel}" in
  dev)
    configuration="Debug"
    flutter_mode="--debug"
    target="lib/main.dart"
    app_name="Yundo Dev"
    bundle_id="app.yundo.client.rebuild.dev"
    api_base_url="${NIMBUS_API_BASE_URL:-http://127.0.0.1:4000/api/v1}"
    ;;
  prod)
    configuration="Release"
    flutter_mode="--release"
    target="lib/main_prod.dart"
    app_name="Yundo"
    bundle_id="app.yundo.client"
    api_base_url="${NIMBUS_PROD_API_BASE_URL:-https://api.yundo.app/api/v1}"
    ;;
  *)
    fail "YUNDO_CHANNEL 只能是 dev 或 prod：${channel}"
    ;;
esac

[[ "${build_number}" =~ ^[0-9]+$ ]] || fail "构建号必须是纯数字：${build_number}"
[[ -d "${developer_dir}" ]] || fail "找不到 Xcode Developer 目录：${developer_dir}"
[[ -x "${flutter_bin}" ]] || fail "找不到 Flutter；请设置 FLUTTER_BIN"
[[ -n "${codesign_identity}" ]] || fail "远程 macOS 构建需要 MACOS_CODESIGN_IDENTITY"

export DEVELOPER_DIR="${developer_dir}"
cd "${repo_root}"
mkdir -p "${output_dir}"

YUNDO_API_BASE_URL="${api_base_url}" "${script_dir}/cache_yundo_rule_sets.sh"
GO_BIN="${GO_BIN:-$(command -v go || true)}" "${script_dir}/build_yundo_macos_core.sh"
"${flutter_bin}" build macos "${flutter_mode}" \
  --target="${target}" \
  --build-number="${build_number}" \
  --dart-define="NIMBUS_API_BASE_URL=${api_base_url}"

built_app="${repo_root}/build/macos/Build/Products/${configuration}/${app_name}.app"
[[ -d "${built_app}" ]] || fail "找不到 macOS 产物：${built_app}"

actual_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${built_app}/Contents/Info.plist")"
[[ "${actual_bundle_id}" == "${bundle_id}" ]] || fail "Bundle ID 不正确：${actual_bundle_id}"
localized_name="$(plutil -extract CFBundleDisplayName raw -o - "${built_app}/Contents/Resources/zh-Hans.lproj/InfoPlist.strings")"
expected_localized_name="云渡"
[[ "${channel}" == "dev" ]] && expected_localized_name="云渡开发版"
[[ "${localized_name}" == "${expected_localized_name}" ]] \
  || fail "中文系统名称不正确：${localized_name}"
[[ -f "${built_app}/Contents/Resources/AppIcon.icns" ]] || fail "App 缺少 macOS AppIcon"

# Core 由本仓库的固定补丁重新构建后再放入 App，避免 CI 复用旧的 dylib。
source_core="${repo_root}/hiddify-core/bin/hiddify-core.dylib"
branded_core="${built_app}/Contents/Frameworks/YundoCore.dylib"
legacy_core="${built_app}/Contents/Frameworks/hiddify-core.dylib"
[[ -f "${source_core}" ]] || fail "本轮构建的 Yundo Core 不存在：${source_core}"
rm -f "${legacy_core}" "${branded_core}"
ditto "${source_core}" "${branded_core}"
strings "${branded_core}" | grep -F 'managed-route-rules' >/dev/null \
  || fail "App 包内 Yundo Core 缺少托管路由能力"

if find "${built_app}" -iname '*hiddify*' -print -quit | grep -q .; then
  fail "构建产物仍包含 Hiddify 可见文件名"
fi

if [[ "${channel}" == prod ]]; then
  "${script_dir}/sign_macos_distribution_app.sh" "${built_app}" "${codesign_identity}"
else
  app_entitlements="$(mktemp "${TMPDIR:-/tmp}/yundo-macos-entitlements.XXXXXX.plist")"
  trap 'rm -f "${app_entitlements}"' EXIT
  codesign -d --entitlements :- "${built_app}" >"${app_entitlements}" 2>/dev/null \
    || fail "无法读取 macOS App entitlement；请确认远端已导入 Apple 证书"
  plutil -lint "${app_entitlements}" >/dev/null || fail "macOS App entitlement 格式无效"
  codesign --force --sign "${codesign_identity}" "${branded_core}"
  login_item="${built_app}/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
  if [[ -d "${login_item}" ]]; then
    codesign --force --sign "${codesign_identity}" \
      --preserve-metadata=identifier,entitlements,requirements,runtime "${login_item}"
  fi
  codesign --force --sign "${codesign_identity}" \
    --identifier "${bundle_id}" \
    --entitlements "${app_entitlements}" "${built_app}"
fi
codesign --verify --deep --strict "${built_app}"

artifact="${output_dir}/Yundo-macOS-${pubspec_version}-build${build_number}-${channel}-signed.zip"
rm -f "${artifact}"
ditto -c -k --sequesterRsrc --keepParent "${built_app}" "${artifact}"
shasum -a 256 "${artifact}"
echo "macOS 远程签名产物：${artifact}"
