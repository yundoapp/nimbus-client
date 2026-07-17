#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
app_path="${repo_root}/build/macos/Build/Products/Release/Yundo.app"
strict=""
pre_notarization=""
expected_bundle_id="${YUNDO_EXPECTED_RELEASE_BUNDLE_ID:-app.yundo.client}"
expected_identity="${YUNDO_DEVELOPER_ID_APPLICATION:-}"
notary_profile="${YUNDO_NOTARY_PROFILE:-}"
plist_buddy="/usr/libexec/PlistBuddy"
blockers=()

for argument in "$@"; do
  case "$argument" in
    --strict)
      strict="--strict"
      ;;
    --pre-notarization)
      pre_notarization="--pre-notarization"
      ;;
    --help|-h)
      cat <<EOF
用法：$(basename "$0") [--strict] [--pre-notarization] [App 路径]

默认 App 路径：${app_path}
说明：本检查只读，不执行签名、公证提交、helper 注册或系统网络变更。
      --pre-notarization 只跳过 Gatekeeper 与 stapling 检查，用于公证提交前验证签名包。
EOF
      exit 0
      ;;
    *)
      app_path="$argument"
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    blockers+=("缺少命令：$1")
  fi
}

require_flutter_asset() {
  local flutter_assets="$1"
  local relative_path="$2"
  [[ -f "${flutter_assets}/${relative_path}" ]] || blockers+=("App 缺少合规文档：${relative_path}")
}

for command_name in codesign plutil rg security spctl xcrun; do
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
    if [[ -f "$daemon_plist" ]]; then
      service_name="${bundle_id}.privileged-helper"
      daemon_label="$($plist_buddy -c 'Print :Label' "$daemon_plist" 2>/dev/null || true)"
      daemon_program="$($plist_buddy -c 'Print :BundleProgram' "$daemon_plist" 2>/dev/null || true)"
      [[ "$daemon_label" == "$service_name" ]] || blockers+=("LaunchDaemon Label 与正式 Bundle ID 不匹配")
      [[ "$daemon_program" == "Contents/Library/HelperTools/YundoPrivilegedHelper" ]] || blockers+=("LaunchDaemon BundleProgram 不正确")
      $plist_buddy -c "Print :MachServices:${service_name}" "$daemon_plist" >/dev/null 2>&1 \
        || blockers+=("LaunchDaemon 缺少正式 Mach service")
      plutil -lint "$daemon_plist" >/dev/null 2>&1 || blockers+=("LaunchDaemon plist 格式无效")
    fi
    flutter_assets="${app_path}/Contents/Frameworks/App.framework/Resources/flutter_assets"
    require_flutter_asset "$flutter_assets" "LICENSE.md"
    require_flutter_asset "$flutter_assets" "docs/legal/privacy-policy.md"
    require_flutter_asset "$flutter_assets" "docs/legal/terms-of-service.md"
    if [[ -f "${flutter_assets}/LICENSE.md" ]] \
      && ! rg -q "Hiddify Extended GNU General Public License v3" "${flutter_assets}/LICENSE.md"; then
      blockers+=("App 内许可证不是预期的 Hiddify Extended GPLv3")
    fi

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

    if [[ "$pre_notarization" != "--pre-notarization" ]]; then
      spctl --assess --type execute --verbose=2 "$app_path" >/dev/null 2>&1 || blockers+=("Gatekeeper 验收未通过")
      xcrun stapler validate "$app_path" >/dev/null 2>&1 || blockers+=("App 没有可验证的公证 stapling ticket")
    fi
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
说明：$([[ "$pre_notarization" == "--pre-notarization" ]] && echo "公证前签名检查通过" || echo "签名、Gatekeeper 和 stapling 均通过")；仍需按 #47/#5 完成管理员批准和 TUN 真机采证。
EOF
