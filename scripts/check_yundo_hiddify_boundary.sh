#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-main}"

resolved_base_ref=""
for candidate in "${base_ref}" "refs/remotes/origin/${base_ref}" "refs/heads/${base_ref}"; do
  if git rev-parse --verify "${candidate}^{commit}" >/dev/null 2>&1; then
    resolved_base_ref="${candidate}"
    break
  fi
done

if [[ -z "${resolved_base_ref}" ]]; then
  printf '无法解析基线提交: %s\n' "$base_ref" >&2
  exit 2
fi

protected_prefixes=(
  'lib/hiddifycore/'
  'lib/singbox/'
  'macos/PrivilegedHelper/'
  'macos/Runner/PrivilegedHelperBridge.swift'
  'windows/runner/'
  'ios/Runner/VPN/'
  'ios/HiddifyPacketTunnel/'
  'android/app/src/main/kotlin/com/hiddify/hiddify/bg/'
)

# 这些文件位于上游保护目录，但只承载品牌、生命周期隔离或受控的产品规则入口。
# 规则入口只能传入 route.rules/rule_set，不能接管 DNS、TUN、系统代理和最终路由。
allowed_boundary_files=(
  'lib/hiddifycore/core_port.dart'
  'lib/hiddifycore/core_interface/core_interface.dart'
  'lib/hiddifycore/core_interface/core_interface_desktop.dart'
  'lib/hiddifycore/core_interface/core_interface_mobile.dart'
  'lib/hiddifycore/hiddify_core_service.dart'
  'lib/singbox/model/singbox_config_option.dart'
  'windows/runner/main.cpp'
  'windows/runner/Runner.rc'
  'windows/runner/resources/app_icon.ico'
  'ios/Runner/VPN/VPNManager.swift'
  'ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift'
  'android/app/src/main/kotlin/com/hiddify/hiddify/bg/ServiceNotification.kt'
  'android/app/src/main/kotlin/com/hiddify/hiddify/bg/VPNService.kt'
)

# 网络核心文件只有在内容与已审阅 Git blob 完全一致时才允许通过。
# 后续任何改动都会改变 blob ID，并重新触发边界门禁。
reviewed_boundary_blobs=(
  '3535de4515c20b88c6f1ab4c977ab7693519444f ios/HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements'
  'f1a72f0a6e4522625d6ac5c4bdc36eebe8dbd526 lib/hiddifycore/core_interface/macos_network_capability_probe.dart'
  '4d1ab7aafaf6954ff8445984b16d263c43ca6e49 lib/hiddifycore/core_interface/macos_tunnel_config.dart'
  '1ace7512f90bed3e90d24d68e182174772708739 macos/PrivilegedHelper/YundoPrivilegedHelper.swift'
)

changed_files="$({
  git diff --name-only "${resolved_base_ref}...HEAD"
  git diff --name-only
  git diff --cached --name-only
} | sort -u)"

violations=()
if [[ -n "$changed_files" ]]; then
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    for prefix in "${protected_prefixes[@]}"; do
      if [[ "$file" == "$prefix"* ]]; then
        branding_only=false
        for allowed_file in "${allowed_boundary_files[@]}"; do
          if [[ "$file" == "$allowed_file" ]]; then
            branding_only=true
            break
          fi
        done
        if [[ "$branding_only" == false && -f "$file" ]]; then
          current_blob="$(git hash-object -- "$file")"
          for reviewed_entry in "${reviewed_boundary_blobs[@]}"; do
            reviewed_blob="${reviewed_entry%% *}"
            reviewed_file="${reviewed_entry#* }"
            if [[ "$file" == "$reviewed_file" && "$current_blob" == "$reviewed_blob" ]]; then
              branding_only=true
              break
            fi
          done
        fi
        if [[ "$branding_only" == false ]]; then
          violations+=("$file")
        fi
        break
      fi
    done
  done <<< "$changed_files"
fi

if (( ${#violations[@]} > 0 )); then
  printf 'YUNDO_HIDDIFY_BOUNDARY_VIOLATION\n' >&2
  printf '以下文件属于 Hiddify 网络核心保护区域，默认禁止由云渡迁移提交修改：\n' >&2
  printf '  %s\n' "${violations[@]}" >&2
  exit 1
fi

printf 'Yundo/Hiddify boundary check passed: no protected network-core changes.\n'
