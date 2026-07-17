#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
app_path="${repo_root}/build/macos/Build/Products/Release/Yundo.app"
expected_bundle_id="${YUNDO_EXPECTED_RELEASE_BUNDLE_ID:-app.yundo.client}"
identity="${YUNDO_DEVELOPER_ID_APPLICATION:-}"
notary_profile="${YUNDO_NOTARY_PROFILE:-}"
api_base_url="${NIMBUS_API_BASE_URL:-https://api.yundo.app/api/v1}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

fail() {
  echo "错误：$*" >&2
  exit 1
}

usage() {
  cat <<EOF
用法：$(basename "$0")

构建正式版 Yundo.app，并使用 Developer ID Application 完成 hardened runtime 签名。

必需环境变量：
  YUNDO_DEVELOPER_ID_APPLICATION  Developer ID Application identity 完整名称
  YUNDO_NOTARY_PROFILE            notarytool 钥匙串凭据配置名

可选环境变量：
  NIMBUS_API_BASE_URL             默认 https://api.yundo.app/api/v1
  FLUTTER_BIN                     Flutter 可执行文件路径
  DEVELOPER_DIR                   默认 /Applications/Xcode.app/Contents/Developer
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
(( $# == 0 )) || fail "不支持的位置参数，请运行 --help 查看用法"

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少必要命令：$1"
}

for command_name in codesign file git plutil rg security xcrun; do
  require_command "$command_name"
done
[[ -n "$identity" ]] || fail "未设置 YUNDO_DEVELOPER_ID_APPLICATION"
[[ -n "$notary_profile" ]] || fail "未设置 YUNDO_NOTARY_PROFILE"
[[ -d "$developer_dir" ]] || fail "找不到 Xcode Developer 目录：${developer_dir}"

identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
[[ "$identities" == *"\"${identity}\""* ]] || fail "钥匙串中没有指定的 Developer ID Application identity"
xcrun notarytool history --keychain-profile "$notary_profile" --output-format json >/dev/null \
  || fail "notarytool 凭据配置不可用，或当前无法连接 Apple 公证服务"

source_state="clean"
if [[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null || true)" ]]; then
  source_state="dirty"
fi
[[ "$source_state" == "clean" ]] || fail "只允许从 clean 工作区生成正式分发 App"

flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
[[ -n "$flutter_bin" && -x "$flutter_bin" ]] \
  || fail "找不到 Flutter；请将 flutter 加入 PATH，或通过 FLUTTER_BIN 指定可执行文件"

export DEVELOPER_DIR="$developer_dir"
cd "$repo_root"
"$flutter_bin" build macos --release \
  --target=lib/main_prod.dart \
  "--dart-define=NIMBUS_API_BASE_URL=${api_base_url}"

[[ -d "$app_path" ]] || fail "找不到 macOS Release 产物：${app_path}"
info_plist="${app_path}/Contents/Info.plist"
plist_buddy="/usr/libexec/PlistBuddy"
[[ -x "$plist_buddy" && -f "$info_plist" ]] || fail "Release App 缺少可读取的 Info.plist"
bundle_id="$($plist_buddy -c 'Print :CFBundleIdentifier' "$info_plist")"
[[ "$bundle_id" == "$expected_bundle_id" ]] || fail "正式版 Bundle ID 不正确：${bundle_id}"

helper_path="${app_path}/Contents/Library/HelperTools/YundoPrivilegedHelper"
login_item="${app_path}/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
[[ -x "$helper_path" ]] || fail "Release App 缺少特权辅助进程"

codesign --force --sign "$identity" --identifier "${bundle_id}.privileged-helper" \
  --options runtime --timestamp "$helper_path"
if [[ -d "$login_item" ]]; then
  codesign --force --deep --sign "$identity" --options runtime --timestamp \
    --preserve-metadata=identifier,entitlements,requirements "$login_item"
fi
codesign --force --deep --sign "$identity" --identifier "$bundle_id" \
  --entitlements "${repo_root}/macos/Runner/Release.entitlements" \
  --options runtime --timestamp "$app_path"

codesign --verify --deep --strict "$app_path"
"${script_dir}/check_macos_distribution_readiness.sh" \
  --strict --pre-notarization "$app_path"

cat <<EOF
macOS 正式分发 App 已构建并完成 Developer ID 签名。

App：${app_path}
Bundle ID：${bundle_id}
签名：${identity}
下一步：scripts/package_macos_distribution_dmg.sh
EOF
