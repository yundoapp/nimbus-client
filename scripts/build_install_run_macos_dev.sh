#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
built_app="${repo_root}/build/macos/Build/Products/Debug/Yundo Dev.app"
installed_app="/Applications/Yundo Dev.app"
expected_bundle_id="app.yundo.client.dev"
api_base_url="${NIMBUS_API_BASE_URL:-http://127.0.0.1:4000/api/v1}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

fail() {
  echo "错误：$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少必要命令：$1"
}

for command_name in codesign ditto mktemp open osascript pgrep pkill plutil rm security shasum; do
  require_command "$command_name"
done

flutter_bin="${FLUTTER_BIN:-}"
if [[ -z "$flutter_bin" ]]; then
  flutter_bin="$(command -v flutter || true)"
fi
[[ -n "$flutter_bin" && -x "$flutter_bin" ]] \
  || fail "找不到 Flutter；请将 flutter 加入 PATH，或通过 FLUTTER_BIN 指定可执行文件"
[[ -d "$developer_dir" ]] || fail "找不到 Xcode Developer 目录：${developer_dir}"

export DEVELOPER_DIR="$developer_dir"

cd "$repo_root"
"$flutter_bin" build macos --debug \
  "--dart-define=NIMBUS_API_BASE_URL=${api_base_url}"

[[ -d "$built_app" ]] || fail "找不到 macOS Debug 产物：${built_app}"
codesign_identity="${MACOS_CODESIGN_IDENTITY:-}"
if [[ -z "$codesign_identity" ]]; then
  codesign_identity="$(security find-identity -v -p codesigning \
    | awk '/"Apple Development:/ { print $2; exit }')"
fi
if [[ -z "$codesign_identity" ]]; then
  codesign_identity="-"
  echo "警告：未找到 Apple Development 签名身份，使用 ad hoc 签名；helper 更新后可能需要重新授权。" >&2
fi

helper_service="${expected_bundle_id}.privileged-helper"
helper_path="${built_app}/Contents/Library/HelperTools/YundoPrivilegedHelper"
login_item="${built_app}/Contents/Library/LoginItems/LaunchAtLoginHelper.app"
[[ -x "$helper_path" ]] || fail "找不到 macOS 特权辅助进程：${helper_path}"

app_entitlements="$(mktemp "${TMPDIR:-/tmp}/yundo-dev-entitlements.XXXXXX.plist")"
trap 'rm -f "$app_entitlements"' EXIT
codesign -d --entitlements :- "$built_app" >"$app_entitlements" 2>/dev/null \
  || fail "无法读取原始 App entitlement"
plutil -lint "$app_entitlements" >/dev/null \
  || fail "原始 App entitlement 格式无效"

# Helper 和登录启动组件会在 Xcode 的 App 签名阶段后写入或调整，按包层级从内向外重签。
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

plist_buddy="/usr/libexec/PlistBuddy"
info_plist="${built_app}/Contents/Info.plist"
bundle_id="$($plist_buddy -c 'Print :CFBundleIdentifier' "$info_plist")"
executable_name="$($plist_buddy -c 'Print :CFBundleExecutable' "$info_plist")"
[[ "$bundle_id" == "$expected_bundle_id" ]] \
  || fail "Bundle ID 不正确：${bundle_id}"

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
  && fail "无法退出已安装的 Yundo Dev，未执行覆盖复制"

# ditto 默认合并目录；先移除固定目标 App，避免已删除的资源残留在安装包中。
[[ "$installed_app" == "/Applications/Yundo Dev.app" ]] \
  || fail "拒绝移除非预期安装路径：${installed_app}"
rm -rf "$installed_app"
ditto "$built_app" "$installed_app"
[[ -x "$installed_executable" ]] || fail "安装后找不到 App 可执行文件：${installed_executable}"

built_hash="$(shasum -a 256 "${built_app}/Contents/MacOS/${executable_name}" | awk '{print $1}')"
installed_hash="$(shasum -a 256 "$installed_executable" | awk '{print $1}')"
[[ "$built_hash" == "$installed_hash" ]] \
  || fail "安装后的 App 与构建产物不一致"

"${script_dir}/verify_macos_privileged_helper.sh" "$installed_app"
open "$installed_app"

for _ in {1..30}; do
  if pgrep -f "$installed_executable" >/dev/null 2>&1; then
    cat <<EOF
Yundo Dev 已完成构建、安装并启动。

构建产物：${built_app}
安装位置：${installed_app}
Bundle ID：${bundle_id}
可执行文件 SHA-256：${installed_hash}
EOF
    exit 0
  fi
  sleep 0.5
done

fail "Yundo Dev 已复制到 /Applications，但启动后未检测到进程"
