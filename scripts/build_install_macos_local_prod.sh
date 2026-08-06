#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
built_app="${repo_root}/build/macos/Build/Products/Release/Yundo.app"
installed_app="/Applications/Yundo.app"
expected_bundle_id="app.yundo.client"
expected_executable="${installed_app}/Contents/MacOS/Yundo"
api_base_url="${NIMBUS_PROD_API_BASE_URL:-https://api.yundo.app/api/v1}"
pubspec_build_number="$(awk -F+ '/^version: / { print $2; exit }' "${repo_root}/pubspec.yaml")"
build_number="${YUNDO_LOCAL_BUILD_NUMBER:-${pubspec_build_number}}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
lsregister_path="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() {
  echo "错误：$*" >&2
  exit 1
}

for command_name in awk codesign defaults ditto grep mktemp open osascript pgrep plutil rm security shasum strings touch; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "缺少 ${command_name}"
done
[[ "${build_number}" =~ ^[0-9]+$ ]] || fail "构建号必须是纯数字：${build_number}"
[[ -d "${developer_dir}" ]] || fail "找不到 Xcode Developer 目录：${developer_dir}"
[[ -x "${lsregister_path}" ]] || fail "找不到 LaunchServices 注册工具：${lsregister_path}"

flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
[[ -x "${flutter_bin}" ]] || fail "找不到 Flutter；请设置 FLUTTER_BIN"
export DEVELOPER_DIR="${developer_dir}"

was_running=false
was_accelerated=false
if pgrep -f "${expected_executable}" >/dev/null 2>&1; then
  was_running=true
  if defaults read "${expected_bundle_id}" flutter.started_by_user 2>/dev/null | grep -Eq '(^|[[:space:]])(1|true)([[:space:]]|$)'; then
    was_accelerated=true
  fi
fi

cd "${repo_root}"
YUNDO_API_BASE_URL="${api_base_url}" "${script_dir}/cache_yundo_rule_sets.sh"
GO_BIN="${GO_BIN:-$(command -v go || true)}" "${script_dir}/build_yundo_macos_core.sh"
"${flutter_bin}" build macos --release \
  --target=lib/main_prod.dart \
  "--build-number=${build_number}" \
  "--dart-define=NIMBUS_API_BASE_URL=${api_base_url}"

[[ -d "${built_app}" ]] || fail "找不到 macOS Release 产物：${built_app}"
bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${built_app}/Contents/Info.plist")"
executable_name="$(plutil -extract CFBundleExecutable raw -o - "${built_app}/Contents/Info.plist")"
[[ "${bundle_id}" == "${expected_bundle_id}" ]] \
  || fail "正式版 Bundle ID 不正确：${bundle_id}"
[[ "${executable_name}" == "Yundo" ]] \
  || fail "正式版可执行文件名称不正确：${executable_name}"
localized_name="$(plutil -extract CFBundleDisplayName raw -o - "${built_app}/Contents/Resources/zh-Hans.lproj/InfoPlist.strings")"
[[ "${localized_name}" == "云渡" ]] || fail "正式版简体中文系统名称不正确：${localized_name}"
[[ -f "${built_app}/Contents/Resources/AppIcon.icns" ]] || fail "正式版缺少 macOS AppIcon"

# 无论 Xcode 是否命中增量复制，都用本轮刚构建的 Core 覆盖 App 包，避免
# 旧构建目录残留的 dylib 与当前 Dart 代码混用。
source_core="${repo_root}/hiddify-core/bin/hiddify-core.dylib"
legacy_core="${built_app}/Contents/Frameworks/hiddify-core.dylib"
branded_core="${built_app}/Contents/Frameworks/YundoCore.dylib"
[[ -f "${source_core}" ]] || fail "本轮构建的 Yundo Core 不存在：${source_core}"
rm -f "${legacy_core}" "${branded_core}"
ditto "${source_core}" "${branded_core}"
[[ -f "${branded_core}" ]] || fail "构建产物缺少 Yundo Core"
strings "${branded_core}" | grep -F 'managed-route-rules' >/dev/null \
  || fail "App 包内 Yundo Core 缺少托管路由能力"
if find "${built_app}" -iname '*hiddify*' -print -quit | grep -q .; then
  fail "正式版构建产物仍包含 Hiddify 可见文件名"
fi

distribution_build="${YUNDO_DISTRIBUTION:-0}"
codesign_identity="${MACOS_CODESIGN_IDENTITY:-}"
if [[ -z "${codesign_identity}" ]]; then
  if [[ "${distribution_build}" == 1 ]]; then
    codesign_identity="$(security find-identity -v -p codesigning \
      | awk '/\"Developer ID Application:/ { print $2; exit }')"
  else
    codesign_identity="$(security find-identity -v -p codesigning \
      | awk '/\"Apple Development:/ { print $2; exit }')"
  fi
fi
[[ -n "${codesign_identity}" ]] \
  || fail "安装正式版需要有效的 macOS 签名身份"

app_entitlements="$(mktemp "${TMPDIR:-/tmp}/yundo-prod-entitlements.XXXXXX.plist")"
backup_root=""
backup_app=""
replacement_started=false
cleanup() {
  local status=$?
  trap - EXIT
  rm -f "${app_entitlements}"
  if (( status != 0 )) && [[ "${replacement_started}" == true ]]; then
    echo "正式版安装失败，正在恢复原有 /Applications/Yundo.app。" >&2
    rm -rf "${installed_app}"
    if [[ -n "${backup_app}" && -d "${backup_app}" ]]; then
      ditto "${backup_app}" "${installed_app}" || {
        echo "错误：原有 Yundo.app 自动恢复失败，备份仍位于 ${backup_app}" >&2
        exit 1
      }
    fi
  fi
  if (( status != 0 )) && [[ "${was_running}" == true && -d "${installed_app}" ]]; then
    open "${installed_app}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${backup_root}" && -d "${backup_root}" ]]; then
    rm -rf "${backup_root}"
  fi
  exit "${status}"
}
trap cleanup EXIT

helper_path="${built_app}/Contents/Library/HelperTools/YundoPrivilegedHelper"
[[ -x "${helper_path}" ]] || fail "构建产物缺少特权辅助进程：${helper_path}"
if [[ "${distribution_build}" == 1 ]]; then
  "${script_dir}/sign_macos_distribution_app.sh" "${built_app}" "${codesign_identity}"
else
  codesign -d --entitlements :- "${built_app}" >"${app_entitlements}" 2>/dev/null \
    || fail "无法读取正式版 App entitlement"
  plutil -lint "${app_entitlements}" >/dev/null \
    || fail "正式版 App entitlement 格式无效"
  codesign --force --sign "${codesign_identity}" "${branded_core}"
  codesign --force --sign "${codesign_identity}" \
    --identifier "${expected_bundle_id}.privileged-helper" \
    "${helper_path}"
  login_item="${built_app}/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
  if [[ -d "${login_item}" ]]; then
    codesign --force --sign "${codesign_identity}" \
      --preserve-metadata=identifier,entitlements,requirements,runtime "${login_item}"
  fi
  codesign --force --sign "${codesign_identity}" \
    --identifier "${expected_bundle_id}" \
    --entitlements "${app_entitlements}" "${built_app}"
fi
codesign --verify --deep --strict "${built_app}"

if [[ "${was_running}" == true ]]; then
  osascript -e "tell application id \"${expected_bundle_id}\" to quit" >/dev/null 2>&1 || true
  for _ in {1..80}; do
    pgrep -f "${expected_executable}" >/dev/null 2>&1 || break
    sleep 0.25
  done
fi
pgrep -f "${expected_executable}" >/dev/null 2>&1 \
  && fail "Yundo 正式版未能通过正常退出流程停止，未执行覆盖安装"

[[ "${installed_app}" == "/Applications/Yundo.app" ]] \
  || fail "拒绝覆盖非预期安装路径：${installed_app}"
backup_root="$(mktemp -d "${TMPDIR:-/tmp}/yundo-prod-install-backup.XXXXXX")"
backup_app="${backup_root}/Yundo.app"
if [[ -d "${installed_app}" ]]; then
  ditto "${installed_app}" "${backup_app}"
fi

replacement_started=true
rm -rf "${installed_app}"
ditto "${built_app}" "${installed_app}"
[[ -x "${expected_executable}" ]] || fail "安装后找不到正式版可执行文件：${expected_executable}"

installed_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${installed_app}/Contents/Info.plist")"
[[ "${installed_bundle_id}" == "${expected_bundle_id}" ]] \
  || fail "安装后的正式版 Bundle ID 不正确：${installed_bundle_id}"
codesign --verify --deep --strict "${installed_app}"
"${lsregister_path}" -f "${installed_app}"
touch "${installed_app}"

built_hash="$(shasum -a 256 "${built_app}/Contents/MacOS/${executable_name}" | awk '{print $1}')"
installed_hash="$(shasum -a 256 "${expected_executable}" | awk '{print $1}')"
[[ "${built_hash}" == "${installed_hash}" ]] \
  || fail "安装后的正式版 App 与构建产物不一致"

if [[ "${was_running}" == true ]]; then
  open "${installed_app}"
  for _ in {1..40}; do
    pgrep -f "${expected_executable}" >/dev/null 2>&1 && break
    sleep 0.25
  done
  pgrep -f "${expected_executable}" >/dev/null 2>&1 \
    || fail "正式版覆盖安装后未能启动"
  if [[ "${was_accelerated}" == true ]]; then
    for _ in {1..120}; do
      if defaults read "${expected_bundle_id}" flutter.started_by_user 2>/dev/null \
        | grep -Eq '(^|[[:space:]])(1|true)([[:space:]]|$)'; then
        break
      fi
      sleep 0.5
    done
    defaults read "${expected_bundle_id}" flutter.started_by_user 2>/dev/null \
      | grep -Eq '(^|[[:space:]])(1|true)([[:space:]]|$)' \
      || fail "正式版覆盖安装后未恢复原有加速状态"
  fi
fi

rm -rf "${backup_root}"
backup_root=""
echo "Yundo 正式版已完成构建、签名、备份式覆盖安装和校验。"
echo "构建产物：${built_app}"
echo "安装位置：${installed_app}"
echo "Bundle ID：${installed_bundle_id}"
echo "本机构建号：${build_number}"
echo "可执行文件 SHA-256：${installed_hash}"
echo "覆盖前运行状态：${was_running}，加速状态：${was_accelerated}"
echo "覆盖后按原状态恢复正式版运行。"
