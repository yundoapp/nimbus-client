#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-}"
identity="${2:-${YUNDO_DEVELOPER_ID_APPLICATION:-}}"

fail() {
  echo "错误：$*" >&2
  exit 1
}

[[ -n "${app_path}" && -d "${app_path}" ]] || fail "找不到 macOS App：${app_path}"
[[ -n "${identity}" ]] || fail "需要 Developer ID Application 签名身份"
[[ "${identity}" == Developer\ ID\ Application:* ]] || fail "签名身份必须是 Developer ID Application：${identity}"

app_info="${app_path}/Contents/Info.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_info}")"
helper_path="${app_path}/Contents/Library/HelperTools/YundoPrivilegedHelper"
helper_service="${bundle_id}.privileged-helper"
entitlements="$(mktemp "${TMPDIR:-/tmp}/yundo-distribution-entitlements.XXXXXX")"
cleanup() {
  rm -f "${entitlements}"
}
trap cleanup EXIT

codesign -d --entitlements :- "${app_path}" >"${entitlements}" 2>/dev/null || fail "无法读取 App entitlement：${app_path}"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "${entitlements}" 2>/dev/null || true
plutil -lint "${entitlements}" >/dev/null || fail "App entitlement 格式无效"

sign_code() {
  local path="$1"
  codesign --force --options runtime --timestamp --sign "${identity}" "${path}"
}

# 先签所有 Mach-O 文件，再按由内到外的顺序签 Framework/App 包，最后签主 App。
while IFS= read -r -d '' path; do
  [[ "${path}" == "${app_path}/Contents/MacOS/"* ]] && continue
  description="$(file -b "${path}")"
  case "${description}" in
    Mach-O*) sign_code "${path}" ;;
  esac
done < <(find "${app_path}/Contents" -type f \( -perm -111 -o -name '*.dylib' \) -print0)

while IFS= read -r -d '' bundle; do
  [[ "${bundle}" == "${app_path}" ]] && continue
  sign_code "${bundle}"
done < <(find "${app_path}/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0)

[[ -x "${helper_path}" ]] || fail "构建产物缺少特权辅助进程：${helper_path}"
codesign --force --options runtime --timestamp --sign "${identity}" --identifier "${helper_service}" "${helper_path}"
codesign --force --options runtime --timestamp --sign "${identity}" --identifier "${bundle_id}" --entitlements "${entitlements}" "${app_path}"

codesign --verify --deep --strict "${app_path}"
signature_info="$(codesign -dvvv "${app_path}" 2>&1)"
grep -Eq 'flags=.*runtime' <<<"${signature_info}" || fail "App 未启用 hardened runtime"
grep -F 'Authority=Developer ID Application:' <<<"${signature_info}" >/dev/null || fail "App 未使用 Developer ID Application 签名"
if codesign -d --entitlements :- "${app_path}" 2>/dev/null | grep -F 'com.apple.security.get-task-allow' >/dev/null; then
  fail "分发 App 仍包含 get-task-allow entitlement"
fi

echo "Developer ID 签名完成：${app_path}"
