#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
app_path="${1:-${repo_root}/build/macos/Build/Products/Debug/Yundo Dev.app}"
fixture_path="${repo_root}/test/fixtures/macos_minimal_tunnel_config.json"
rejected_fixture_path="${repo_root}/test/fixtures/macos_rejected_privileged_config.json"

fail() {
  echo "错误：$*" >&2
  exit 1
}

plist_buddy="/usr/libexec/PlistBuddy"
info_plist="${app_path}/Contents/Info.plist"
[[ -f "$info_plist" ]] || fail "找不到 App Info.plist：${info_plist}"

bundle_id="$($plist_buddy -c 'Print :CFBundleIdentifier' "$info_plist")"
executable_name="$($plist_buddy -c 'Print :CFBundleExecutable' "$info_plist")"
service_name="$($plist_buddy -c 'Print :YundoPrivilegedHelperService' "$info_plist" 2>/dev/null || true)"
if [[ -z "$service_name" ]]; then
  service_name="${bundle_id}.privileged-helper"
fi
helper_path="${app_path}/Contents/Library/HelperTools/YundoPrivilegedHelper"
daemon_plist="${app_path}/Contents/Library/LaunchDaemons/${service_name}.plist"
validation_fixture="$(mktemp "${TMPDIR:-/tmp}/yundo-helper-config.XXXXXX")"
cleanup() {
  rm -f "$validation_fixture"
}
trap cleanup EXIT
sed \
  -e "s/\"Yundo Dev\"/\"${executable_name}\"/" \
  -e "s|__APP_CONTENTS_PATH__|${app_path}/Contents|g" \
  "$fixture_path" >"$validation_fixture"

[[ -x "$helper_path" ]] || fail "缺少特权辅助进程：${helper_path}"
[[ -f "${app_path}/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/rules/geoip-cn.srs" ]] \
  || fail "缺少 macOS 国内地址直连规则快照"
[[ -f "$daemon_plist" ]] || fail "缺少 LaunchDaemon 配置：${daemon_plist}"
codesign --verify --deep --strict "$app_path" \
  || fail "App 完整签名校验失败：${app_path}"
app_team_identifier="$(codesign -dvv "$app_path" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
helper_signing_info="$(codesign -dvv "$helper_path" 2>&1)"
helper_team_identifier="$(sed -n 's/^TeamIdentifier=//p' <<<"$helper_signing_info")"
helper_identifier="$(sed -n 's/^Identifier=//p' <<<"$helper_signing_info")"
[[ -n "$app_team_identifier" && "$app_team_identifier" == "$helper_team_identifier" ]] \
  || fail "App 与特权辅助进程签名团队不一致"
[[ "$helper_identifier" == "$service_name" ]] \
  || fail "特权辅助进程签名标识与服务名不一致"
[[ "$($plist_buddy -c 'Print :Label' "$daemon_plist")" == "$service_name" ]] \
  || fail "LaunchDaemon Label 与 App Bundle ID 不匹配"
[[ "$($plist_buddy -c 'Print :BundleProgram' "$daemon_plist")" == 'Contents/Library/HelperTools/YundoPrivilegedHelper' ]] \
  || fail "LaunchDaemon BundleProgram 不正确"
$plist_buddy -c "Print :MachServices:${service_name}" "$daemon_plist" >/dev/null \
  || fail "LaunchDaemon 缺少预期 Mach service"

plutil -lint "$daemon_plist" >/dev/null
codesign --verify --strict "$helper_path"
"$helper_path" --self-check | grep -q '^privileged-helper-self-check-ok$' \
  || fail "辅助进程无法加载包内 core"
"$helper_path" --validate-config "$validation_fixture" | grep -q '^privileged-helper-config-ok$' \
  || fail "辅助进程拒绝最小 TUN 配置基线"
if "$helper_path" --validate-config "$rejected_fixture_path" >/dev/null 2>&1; then
  fail "辅助进程错误接受了包含远端出站的特权配置"
fi

reject_mutated_config() {
  local description="$1"
  local filter="$2"
  local rejected_config
  rejected_config="$(mktemp "${TMPDIR:-/tmp}/yundo-helper-rejected.XXXXXX")"
  jq "$filter" "$validation_fixture" >"$rejected_config"
  if "$helper_path" --validate-config "$rejected_config" >/dev/null 2>&1; then
    rm -f "$rejected_config"
    fail "辅助进程错误接受了${description}"
  fi
  rm -f "$rejected_config"
}

reject_mutated_config "系统级 GeoIP 路由排除" \
  '.inbounds[0].route_exclude_address_set = ["geoip-cn"]'
reject_mutated_config "非 HTTPS 远程规则" \
  '.route.rule_set[0].url = "http://rules.example/geosite-gfw.srs"'
reject_mutated_config "App 包外本地规则路径" \
  '.route.rule_set[1].path = "/tmp/geoip-cn.srs"'
reject_mutated_config "任意特权出站标签" \
  '.route.rules[2].outbound = "arbitrary-outbound"'

cat <<EOF
macOS 特权辅助进程校验通过。

App：${app_path}
服务：${service_name}
Helper：${helper_path}
EOF

