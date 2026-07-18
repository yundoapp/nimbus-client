#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
built_app="${repo_root}/build/macos/Build/Products/Release/Yundo.app"
installed_app="/Applications/Yundo.app"
expected_bundle_id="app.yundo.client"
api_base_url="${NIMBUS_PROD_API_BASE_URL:-https://api.yundo.app/api/v1}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

fail() {
  echo "错误：$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少必要命令：$1"
}

for command_name in awk codesign ditto mktemp osascript pgrep pkill plutil rm security shasum; do
  require_command "$command_name"
done

flutter_bin="${FLUTTER_BIN:-}"
if [[ -z "$flutter_bin" ]]; then
  flutter_bin="$(command -v flutter || true)"
fi
[[ -n "$flutter_bin" && -x "$flutter_bin" ]] \
  || fail "找不到 Flutter；请将 flutter 加入 PATH，或通过 FLUTTER_BIN 指定可执行文件"
[[ -d "$developer_dir" ]] || fail "找不到 Xcode Developer 目录：${developer_dir}"
[[ "$installed_app" == "/Applications/Yundo.app" ]] \
  || fail "拒绝覆盖非预期安装路径：${installed_app}"

export DEVELOPER_DIR="$developer_dir"

cd "$repo_root"
"$flutter_bin" build macos --release \
  --target=lib/main_prod.dart \
  "--dart-define=NIMBUS_API_BASE_URL=${api_base_url}"

[[ -d "$built_app" ]] || fail "找不到 macOS Release 产物：${built_app}"

codesign_identity="${MACOS_CODESIGN_IDENTITY:-}"
if [[ -z "$codesign_identity" ]]; then
  codesign_identity="$(security find-identity -v -p codesigning \
    | awk '/"Apple Development:/ { print $2; exit }')"
fi
if [[ -z "$codesign_identity" ]]; then
  codesign_identity="-"
  echo "警告：未找到 Apple Development 签名身份，正式版本机验收使用 ad hoc 签名。" >&2
fi

plist_buddy="/usr/libexec/PlistBuddy"
info_plist="${built_app}/Contents/Info.plist"
bundle_id="$($plist_buddy -c 'Print :CFBundleIdentifier' "$info_plist")"
executable_name="$($plist_buddy -c 'Print :CFBundleExecutable' "$info_plist")"
[[ "$bundle_id" == "$expected_bundle_id" ]] \
  || fail "正式版 Bundle ID 不正确：${bundle_id}"
[[ "$executable_name" == "Yundo" ]] \
  || fail "正式版可执行文件名称不正确：${executable_name}"

helper_service="${expected_bundle_id}.privileged-helper"
helper_path="${built_app}/Contents/Library/HelperTools/YundoPrivilegedHelper"
login_item="${built_app}/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
[[ -x "$helper_path" ]] || fail "找不到 macOS 正式版特权辅助进程：${helper_path}"

app_entitlements="$(mktemp "${TMPDIR:-/tmp}/yundo-prod-entitlements.XXXXXX.plist")"
backup_root=""
backup_app=""
replacement_started=false

cleanup() {
  local status=$?
  local preserve_backup=false
  trap - EXIT
  rm -f "$app_entitlements"

  if (( status != 0 )) && [[ "$replacement_started" == true ]]; then
    echo "正式版安装失败，正在恢复原有 /Applications/Yundo.app。" >&2
    rm -rf "$installed_app"
    if [[ -n "$backup_app" && -d "$backup_app" ]]; then
      if ! ditto "$backup_app" "$installed_app"; then
        echo "错误：原有 Yundo.app 自动恢复失败，备份仍位于 ${backup_app}" >&2
        preserve_backup=true
      fi
    fi
  fi

  if [[ "$preserve_backup" == false && -n "$backup_root" && -d "$backup_root" ]]; then
    rm -rf "$backup_root"
  fi
  exit "$status"
}
trap cleanup EXIT

codesign -d --entitlements :- "$built_app" >"$app_entitlements" 2>/dev/null \
  || fail "无法读取正式版 App entitlement"
plutil -lint "$app_entitlements" >/dev/null \
  || fail "正式版 App entitlement 格式无效"

helper_sign_args=(--force --sign "$codesign_identity" --identifier "$helper_service")
if [[ "$codesign_identity" != "-" ]]; then
  helper_sign_args+=(--options runtime)
fi
codesign "${helper_sign_args[@]}" "$helper_path"
if [[ -d "$login_item" ]]; then
  codesign --force --sign "$codesign_identity" \
    --preserve-metadata=identifier,entitlements,requirements,runtime \
    "$login_item"
fi
codesign --force --sign "$codesign_identity" \
  --identifier "$expected_bundle_id" \
  --entitlements "$app_entitlements" \
  "$built_app"
codesign --verify --deep --strict "$built_app"
"${script_dir}/verify_macos_privileged_helper.sh" "$built_app"

installed_executable="${installed_app}/Contents/MacOS/${executable_name}"
if pgrep -f "$installed_executable" >/dev/null 2>&1; then
  osascript -e "tell application id \"${bundle_id}\" to quit" >/dev/null 2>&1 &
  quit_request_pid=$!
  for _ in {1..20}; do
    kill -0 "$quit_request_pid" >/dev/null 2>&1 || break
    sleep 0.25
  done
  if kill -0 "$quit_request_pid" >/dev/null 2>&1; then
    kill -TERM "$quit_request_pid" >/dev/null 2>&1 || true
  fi
  wait "$quit_request_pid" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -f "$installed_executable" >/dev/null 2>&1 || break
    sleep 0.25
  done
fi

if pgrep -f "$installed_executable" >/dev/null 2>&1; then
  pkill -TERM -f "$installed_executable" || true
  for _ in {1..20}; do
    pgrep -f "$installed_executable" >/dev/null 2>&1 || break
    sleep 0.25
  done
fi

pgrep -f "$installed_executable" >/dev/null 2>&1 \
  && fail "无法退出已安装的 Yundo，未执行覆盖复制"

backup_root="$(mktemp -d "${TMPDIR:-/tmp}/yundo-prod-install-backup.XXXXXX")"
backup_app="${backup_root}/Yundo.app"
if [[ -d "$installed_app" ]]; then
  ditto "$installed_app" "$backup_app"
fi

replacement_started=true
rm -rf "$installed_app"
ditto "$built_app" "$installed_app"
[[ -x "$installed_executable" ]] || fail "安装后找不到正式版可执行文件：${installed_executable}"

installed_info_plist="${installed_app}/Contents/Info.plist"
installed_bundle_id="$($plist_buddy -c 'Print :CFBundleIdentifier' "$installed_info_plist")"
[[ "$installed_bundle_id" == "$expected_bundle_id" ]] \
  || fail "安装后的正式版 Bundle ID 不正确：${installed_bundle_id}"

built_hash="$(shasum -a 256 "${built_app}/Contents/MacOS/${executable_name}" | awk '{print $1}')"
installed_hash="$(shasum -a 256 "$installed_executable" | awk '{print $1}')"
[[ "$built_hash" == "$installed_hash" ]] \
  || fail "安装后的正式版 App 与构建产物不一致"

codesign --verify --deep --strict "$installed_app"
"${script_dir}/verify_macos_privileged_helper.sh" "$installed_app"
pgrep -f "$installed_executable" >/dev/null 2>&1 \
  && fail "正式版覆盖安装后意外启动"

cat <<EOF
Yundo 正式版已完成本机构建、备份式覆盖安装和校验，未启动。

构建产物：${built_app}
安装位置：${installed_app}
Bundle ID：${installed_bundle_id}
生产 API：${api_base_url}
可执行文件 SHA-256：${installed_hash}
EOF
