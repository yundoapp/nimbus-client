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

# These files are inside inherited platform folders but only change product
# identity, native library loading names, or app lifecycle isolation. They
# must not alter networking behavior, so the boundary check permits them
# explicitly.
allowed_boundary_files=(
  'lib/hiddifycore/core_port.dart'
  'lib/hiddifycore/core_interface/core_interface_desktop.dart'
  'lib/hiddifycore/core_interface/core_interface_mobile.dart'
  'lib/hiddifycore/hiddify_core_service.dart'
  'windows/runner/main.cpp'
  'windows/runner/Runner.rc'
  'windows/runner/resources/app_icon.ico'
  'ios/Runner/VPN/VPNManager.swift'
  'ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift'
  'android/app/src/main/kotlin/com/hiddify/hiddify/bg/ServiceNotification.kt'
  'android/app/src/main/kotlin/com/hiddify/hiddify/bg/VPNService.kt'
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
