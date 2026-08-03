#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
built_app="${repo_root}/build/macos/Build/Products/Debug/Yundo Dev.app"
installed_app="/Applications/Yundo Dev.app"
expected_bundle_id="app.yundo.client.rebuild.dev"
expected_executable="${installed_app}/Contents/MacOS/Yundo Dev"
api_base_url="${NIMBUS_API_BASE_URL:-http://127.0.0.1:4000/api/v1}"
build_number="${YUNDO_LOCAL_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
lsregister_path="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() {
  echo "错误：$*" >&2
  exit 1
}

for command_name in awk codesign ditto mktemp open osascript pgrep plutil rm security shasum touch; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "缺少 ${command_name}"
done
[[ -d "${developer_dir}" ]] || fail "找不到 Xcode Developer 目录：${developer_dir}"
[[ -x "${lsregister_path}" ]] || fail "找不到 LaunchServices 注册工具：${lsregister_path}"

flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
[[ -x "${flutter_bin}" ]] || fail "找不到 Flutter；请设置 FLUTTER_BIN"
export DEVELOPER_DIR="${developer_dir}"

quit_existing_app() {
  pgrep -f "${expected_executable}" >/dev/null 2>&1 || return 0
  osascript -e "tell application id \"${expected_bundle_id}\" to quit" >/dev/null 2>&1 || true
  for _ in {1..80}; do
    pgrep -f "${expected_executable}" >/dev/null 2>&1 || return 0
    sleep 0.25
  done
  fail "Yundo Dev 未能通过正常退出流程退出，未执行覆盖安装"
}

restore_existing_app() {
  local backup_app="$1"
  rm -rf "${installed_app}"
  if [[ -d "${backup_app}" ]]; then
    ditto "${backup_app}" "${installed_app}"
  fi
}

cd "${repo_root}"
"${flutter_bin}" build macos --debug \
  "--build-number=${build_number}" \
  "--dart-define=NIMBUS_API_BASE_URL=${api_base_url}"

[[ -d "${built_app}" ]] || fail "找不到 macOS Debug 产物：${built_app}"
bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${built_app}/Contents/Info.plist")"
[[ "${bundle_id}" == "${expected_bundle_id}" ]] || fail "Bundle ID 不正确：${bundle_id}"
localized_name="$(plutil -extract CFBundleDisplayName raw -o - "${built_app}/Contents/Resources/zh-Hans.lproj/InfoPlist.strings")"
[[ "${localized_name}" == "云渡开发版" ]] || fail "开发版简体中文系统名称不正确：${localized_name}"
[[ -f "${built_app}/Contents/Resources/AppIcon.icns" ]] || fail "开发版缺少 macOS AppIcon"
# Xcode 的 Copy Files 阶段按上游 Core 源文件 basename 输出；在最终 App
# 包边界重命名，避免用户在进程/文件管理器里看到上游产品名。
legacy_core="${built_app}/Contents/Frameworks/hiddify-core.dylib"
branded_core="${built_app}/Contents/Frameworks/YundoCore.dylib"
if [[ -f "${legacy_core}" && ! -e "${branded_core}" ]]; then
  mv "${legacy_core}" "${branded_core}"
elif [[ -f "${legacy_core}" && -f "${branded_core}" ]]; then
  rm -f "${legacy_core}"
fi
[[ -f "${branded_core}" ]] \
  || fail "构建产物缺少 Yundo Core"
if find "${built_app}" -iname '*hiddify*' -print -quit | grep -q .; then
  fail "构建产物仍包含 Hiddify 可见文件名"
fi
# Flutter 构建会复制嵌套登录启动组件；按包层级重签，保证最终 App 可启动。
codesign_identity="${MACOS_CODESIGN_IDENTITY:-}"
if [[ -z "${codesign_identity}" ]]; then
  codesign_identity="$(security find-identity -v -p codesigning \
    | awk '/\"Apple Development:/ { print $2; exit }')"
fi
[[ -n "${codesign_identity}" ]] \
  || fail "安装开发版需要有效的 Apple Development 签名身份"

app_entitlements="$(mktemp "${TMPDIR:-/tmp}/yundo-dev-entitlements.XXXXXX.plist")"
trap 'rm -f "${app_entitlements}"' EXIT
codesign -d --entitlements :- "${built_app}" >"${app_entitlements}" 2>/dev/null \
  || fail "无法读取开发版 App entitlement"
plutil -lint "${app_entitlements}" >/dev/null \
  || fail "开发版 App entitlement 格式无效"

core_path="${built_app}/Contents/Frameworks/YundoCore.dylib"
[[ -f "${core_path}" ]] || fail "构建产物缺少 Yundo Core：${core_path}"
codesign --force --sign "${codesign_identity}" "${core_path}"
login_item="${built_app}/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
if [[ -d "${login_item}" ]]; then
  codesign --force --sign "${codesign_identity}" \
    --preserve-metadata=identifier,entitlements,requirements,runtime "${login_item}"
fi
codesign --force --sign "${codesign_identity}" \
  --identifier "${expected_bundle_id}" \
  --entitlements "${app_entitlements}" "${built_app}"
codesign --verify --deep --strict "${built_app}"

FLUTTER_BIN="${flutter_bin}" \
  DEVELOPER_DIR="${developer_dir}" \
  MACOS_CODESIGN_IDENTITY="${codesign_identity}" \
  YUNDO_LOCAL_BUILD_NUMBER="${build_number}" \
  "${script_dir}/build_install_macos_local_prod.sh"

quit_existing_app
backup_root="$(mktemp -d "${TMPDIR:-/tmp}/yundo-dev-backup.XXXXXX")"
backup_app="${backup_root}/Yundo Dev.app"
if [[ -d "${installed_app}" ]]; then
  ditto "${installed_app}" "${backup_app}"
fi

if ! rm -rf "${installed_app}" || ! ditto "${built_app}" "${installed_app}"; then
  restore_existing_app "${backup_app}"
  fail "覆盖安装失败，已尝试恢复原有 Yundo Dev.app"
fi

installed_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${installed_app}/Contents/Info.plist")"
[[ "${installed_bundle_id}" == "${expected_bundle_id}" ]] || fail "安装后的 Bundle ID 不正确：${installed_bundle_id}"
"${lsregister_path}" -f "${installed_app}"
touch "${installed_app}"

open "${installed_app}"
for _ in {1..40}; do
  pgrep -f "${expected_executable}" >/dev/null 2>&1 && break
  sleep 0.25
done
pgrep -f "${expected_executable}" >/dev/null 2>&1 \
  || fail "Yundo Dev 构建完成后未能启动"

rm -rf "${backup_root}"
echo "Yundo Dev 与 Yundo 正式版均已完成构建、签名、Bundle ID 校验和覆盖安装。"
echo "构建产物：${built_app}"
echo "Yundo Dev 已启动：${installed_app}"
echo "正式版保持未启动，避免两个版本同时接管网络。"
