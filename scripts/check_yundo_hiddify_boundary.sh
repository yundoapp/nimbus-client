#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-main}"

if ! git rev-parse --verify "${base_ref}^{commit}" >/dev/null 2>&1; then
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

changed_files="$({
  git diff --name-only "${base_ref}...HEAD"
  git diff --name-only
  git diff --cached --name-only
} | sort -u)"

violations=()
if [[ -n "$changed_files" ]]; then
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    for prefix in "${protected_prefixes[@]}"; do
      if [[ "$file" == "$prefix"* ]]; then
        violations+=("$file")
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

