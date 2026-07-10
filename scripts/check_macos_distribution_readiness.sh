#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
app_path="${1:-${repo_root}/build/macos/Build/Products/Release/Yundo.app}"
strict="${2:-}"
expected_bundle_id="${YUNDO_EXPECTED_RELEASE_BUNDLE_ID:-app.yundo.client}"
expected_identity="${YUNDO_DEVELOPER_ID_APPLICATION:-}"
notary_profile="${YUNDO_NOTARY_PROFILE:-}"
plist_buddy="/usr/libexec/PlistBuddy"
blockers=()

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    blockers+=("缺少命令：$1")
  fi
}

for command_name in codesign security spctl xcrun; do
  require_command "$command_name"
done
[[ -x "$plist_buddy" ]] || blockers+=("缺少命令：${plist_buddy}")

identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "$expected_identity" ]]; then
  [[ "$identities" == *"$expected_identity"* ]] || blockers+=("钥匙串中没有指定的 Developer ID Application identity")
elif [[ "$identities" != *"Developer ID Application:"* ]]; then
  blockers+=("钥匙串中没有 Developer ID Application identity")
fi

if [[ -z "$notary_profile" ]]; then
  blockers+=("未设置 YUNDO_NOTARY_PROFILE")
elif ! xcrun notarytool history --keychain-profile "$notary_profile" --output-format json >/dev/null 2>&1; then
  blockers+=("notarytool 凭据配置不可用，或当前无法连接 Apple 公证服务")
fi

app_team=""
helper_team=""
if [[ ! -d "$app_path" ]]; then
  blockers+=("找不到待验收 App：${app_path}")
else
  info_plist="${app_path}/Contents/Info.plist"
  if [[ ! -f "$info_plist" ]]; then
    blockers+=("App 缺少 Info.plist")
  else
    bundle_id="$($plist_buddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
    [[ "$bundle_id" == "$expected_bundle_id" ]] || blockers+=("正式版 Bundle ID 不正确：${bundle_id:-unknown}")
    helper_path="${app_path}/Contents/Library/HelperTools/YundoPrivilegedHelper"
    daemon_plist="${app_path}/Contents/Library/LaunchDaemons/${bundle_id}.privileged-helper.plist"
    [[ -x "$helper_path" ]] || blockers+=("App 缺少特权辅助进程")
    [[ -f "$daemon_plist" ]] || blockers+=("App 缺少匹配 Bundle ID 的 LaunchDaemon plist")

    app_signature="$(codesign -d --verbose=4 "$app_path" 2>&1 || true)"
    app_team="$(printf '%s\n' "$app_signature" | sed -n 's/^TeamIdentifier=//p' | head -1)"
    [[ "$app_signature" == *"Authority=Developer ID Application:"* ]] || blockers+=("App 不是 Developer ID Application 签名")
    [[ "$app_signature" == *"flags="*"runtime"* ]] || blockers+=("App 未启用 hardened runtime")
    [[ -n "$app_team" && "$app_team" != "not set" ]] || blockers+=("App 签名缺少 TeamIdentifier")
    codesign --verify --deep --strict "$app_path" >/dev/null 2>&1 || blockers+=("App 深度签名校验失败")

    if [[ -x "$helper_path" ]]; then
      helper_signature="$(codesign -d --verbose=4 "$helper_path" 2>&1 || true)"
      helper_team="$(printf '%s\n' "$helper_signature" | sed -n 's/^TeamIdentifier=//p' | head -1)"
      [[ "$helper_signature" == *"Authority=Developer ID Application:"* ]] || blockers+=("helper 不是 Developer ID Application 签名")
      [[ "$helper_signature" == *"flags="*"runtime"* ]] || blockers+=("helper 未启用 hardened runtime")
      [[ -n "$app_team" && "$helper_team" == "$app_team" ]] || blockers+=("App 与 helper 的 TeamIdentifier 不一致")
      codesign --verify --strict "$helper_path" >/dev/null 2>&1 || blockers+=("helper 签名校验失败")
    fi

    spctl --assess --type execute --verbose=2 "$app_path" >/dev/null 2>&1 || blockers+=("Gatekeeper 验收未通过")
    xcrun stapler validate "$app_path" >/dev/null 2>&1 || blockers+=("App 没有可验证的公证 stapling ticket")
  fi
fi

if (( ${#blockers[@]} )); then
  echo "macOS 正式分发就绪检查：blocked"
  printf '阻塞：%s\n' "${blockers[@]}"
  echo "说明：本检查只读，不执行签名、公证提交、helper 注册或系统网络变更。"
  [[ "$strict" == "--strict" ]] && exit 1
  exit 0
fi

cat <<EOF
macOS 正式分发就绪检查：ready
App：${app_path}
TeamIdentifier：${app_team}
公证凭据配置名：${notary_profile}
说明：签名、Gatekeeper 和 stapling 均通过；仍需按 #47/#5 完成管理员批准和 TUN 真机采证。
EOF
