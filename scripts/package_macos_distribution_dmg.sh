#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source_app="${1:-${repo_root}/build/macos/Build/Products/Release/Yundo.app}"
output_dir="${2:-${repo_root}/build/distribution}"
expected_display_name="${YUNDO_EXPECTED_RELEASE_DISPLAY_NAME:-Yundo}"
expected_bundle_id="${YUNDO_EXPECTED_RELEASE_BUNDLE_ID:-app.yundo.client}"
identity="${YUNDO_DEVELOPER_ID_APPLICATION:-}"
notary_profile="${YUNDO_NOTARY_PROFILE:-}"
plist_buddy="/usr/libexec/PlistBuddy"

fail() {
  echo "错误：$*" >&2
  exit 1
}

usage() {
  cat <<EOF
用法：$(basename "$0") [Yundo.app 路径] [输出目录]

公证并 staple 已完成 Developer ID 签名的 Yundo.app，生成、公证并校验 DMG，
同时输出 SHA-256 和可追踪 manifest。本脚本不会上传 GitHub Release 或发布下载链接。

必需环境变量：
  YUNDO_DEVELOPER_ID_APPLICATION  Developer ID Application identity 完整名称
  YUNDO_NOTARY_PROFILE            notarytool 钥匙串凭据配置名
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
(( $# <= 2 )) || fail "参数过多，请运行 --help 查看用法"

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少必要命令：$1"
}

submit_for_notarization() {
  local target_path="$1"
  local result_path="$2"
  local status
  local submission_id

  xcrun notarytool submit "$target_path" --keychain-profile "$notary_profile" \
    --wait --output-format json >"$result_path"
  status="$(plutil -extract status raw -o - "$result_path" 2>/dev/null || true)"
  submission_id="$(plutil -extract id raw -o - "$result_path" 2>/dev/null || true)"
  [[ "$status" == "Accepted" ]] \
    || fail "Apple 公证未通过：${target_path}（状态：${status:-unknown}，提交：${submission_id:-unknown}）"
  [[ -n "$submission_id" ]] || fail "Apple 公证响应缺少提交 ID：${target_path}"
  printf '%s\n' "$submission_id"
}

for command_name in codesign ditto git hdiutil ln mkdir mktemp plutil security shasum spctl xcrun; do
  require_command "$command_name"
done
[[ -x "$plist_buddy" ]] || fail "缺少必要命令：${plist_buddy}"
[[ -n "$identity" ]] || fail "未设置 YUNDO_DEVELOPER_ID_APPLICATION"
[[ -n "$notary_profile" ]] || fail "未设置 YUNDO_NOTARY_PROFILE"
[[ -d "$source_app" ]] || fail "找不到 App：${source_app}"

source_state="clean"
if [[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null || true)" ]]; then
  source_state="dirty"
fi
[[ "$source_state" == "clean" ]] || fail "只允许从 clean 工作区生成正式 DMG"

identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
[[ "$identities" == *"\"${identity}\""* ]] || fail "钥匙串中没有指定的 Developer ID Application identity"
xcrun notarytool history --keychain-profile "$notary_profile" --output-format json >/dev/null \
  || fail "notarytool 凭据配置不可用，或当前无法连接 Apple 公证服务"

info_plist="${source_app}/Contents/Info.plist"
[[ -f "$info_plist" ]] || fail "App 缺少 Info.plist"
display_name="$($plist_buddy -c 'Print :CFBundleDisplayName' "$info_plist")"
bundle_id="$($plist_buddy -c 'Print :CFBundleIdentifier' "$info_plist")"
version="$($plist_buddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
build_number="$($plist_buddy -c 'Print :CFBundleVersion' "$info_plist")"
[[ "$display_name" == "$expected_display_name" ]] || fail "正式版显示名不正确：${display_name}"
[[ "$bundle_id" == "$expected_bundle_id" ]] || fail "正式版 Bundle ID 不正确：${bundle_id}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版本号格式不正确：${version}"
[[ "$build_number" =~ ^[0-9]+$ ]] || fail "构建号格式不正确：${build_number}"
(( build_number >= 10000 )) || fail "构建号不能小于 10000"

"${script_dir}/check_macos_distribution_readiness.sh" \
  --strict --pre-notarization "$source_app"

source_commit="$(git -C "$repo_root" rev-parse --short HEAD)"
source_commit_full="$(git -C "$repo_root" rev-parse HEAD)"
timestamp="${YUNDO_PACKAGE_TIMESTAMP:-$(date '+%Y%m%d%H%M%S')}"
[[ "$timestamp" =~ ^[0-9]{14}$ ]] || fail "YUNDO_PACKAGE_TIMESTAMP 必须使用 YYYYMMDDHHMMSS 格式"

artifact_name="yundo-macos-${version}+${build_number}-${timestamp}.dmg"
artifact_path="${output_dir}/${artifact_name}"
checksum_path="${artifact_path}.sha256"
manifest_path="${artifact_path}.manifest.txt"
mkdir -p "$output_dir"
[[ ! -e "$artifact_path" ]] || fail "产物已存在：${artifact_path}"

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/yundo-distribution.XXXXXX")"
mounted=""
cleanup() {
  if [[ -n "$mounted" ]]; then
    hdiutil detach "$mounted" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$staging_root"
}
trap cleanup EXIT

notary_zip="${staging_root}/Yundo-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$source_app" "$notary_zip"
app_notary_id="$(submit_for_notarization "$notary_zip" "${staging_root}/app-notary.json")"
xcrun stapler staple "$source_app"
xcrun stapler validate "$source_app"
"${script_dir}/check_macos_distribution_readiness.sh" --strict "$source_app"

dmg_source="${staging_root}/dmg"
mkdir -p "$dmg_source"
ditto "$source_app" "${dmg_source}/${expected_display_name}.app"
ln -s /Applications "${dmg_source}/Applications"
hdiutil create -quiet -volname "$expected_display_name" -srcfolder "$dmg_source" \
  -format UDZO -imagekey zlib-level=9 "$artifact_path"
codesign --force --sign "$identity" --timestamp "$artifact_path"
dmg_notary_id="$(submit_for_notarization "$artifact_path" "${staging_root}/dmg-notary.json")"
xcrun stapler staple "$artifact_path"
xcrun stapler validate "$artifact_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$artifact_path"

mount_point="${staging_root}/mounted"
mkdir -p "$mount_point"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_point" "$artifact_path"
mounted="$mount_point"
mounted_app="${mount_point}/${expected_display_name}.app"
codesign --verify --deep --strict "$mounted_app"
"${script_dir}/check_macos_distribution_readiness.sh" --strict "$mounted_app"
hdiutil detach "$mount_point" -quiet
mounted=""

(
  cd "$output_dir"
  shasum -a 256 "$artifact_name" >"${artifact_name}.sha256"
)
sha256="$(awk '{print $1}' "$checksum_path")"

cat >"$manifest_path" <<EOF
artifact=${artifact_name}
sha256=${sha256}
display_name=${display_name}
bundle_id=${bundle_id}
version=${version}
build_number=${build_number}
signature=developer-id
notarization=accepted
app_notary_submission=${app_notary_id}
dmg_notary_submission=${dmg_notary_id}
app_stapling=passed
dmg_stapling=passed
gatekeeper=passed
source_commit=${source_commit}
source_commit_full=${source_commit_full}
source_state=${source_state}
created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

cat <<EOF
macOS 正式分发 DMG 已生成并完成公证验收。

产物：${artifact_path}
校验：${checksum_path}
清单：${manifest_path}
Bundle：${bundle_id} ${version}+${build_number}
源码：${source_commit} (${source_state})
EOF
