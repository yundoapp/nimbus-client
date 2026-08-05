#!/usr/bin/env bash
set -euo pipefail

strict=false
app_path=""
for argument in "$@"; do
  case "${argument}" in
    --strict) strict=true ;;
    -*) echo "错误：不支持的参数：${argument}" >&2; exit 2 ;;
    *) [[ -z "${app_path}" ]] || { echo "错误：只能指定一个 App 路径" >&2; exit 2; }; app_path="${argument}" ;;
  esac
done

app_path="${app_path:-build/macos/Build/Products/Release/Yundo.app}"
identity="${YUNDO_DEVELOPER_ID_APPLICATION:-}"
profile="${YUNDO_NOTARY_PROFILE:-}"
blocking=0

pass() { printf '通过：%s\n' "$*"; }
warn() { printf '待处理：%s\n' "$*"; blocking=1; }
fail() { printf '错误：%s\n' "$*"; blocking=1; }

if [[ ! -d "${app_path}" ]]; then
  fail "找不到 macOS App：${app_path}"
else
  pass "找到 App：${app_path}"
  info="$(codesign -dvvv "${app_path}" 2>&1 || true)"
  if grep -F 'Authority=Developer ID Application:' <<<"${info}" >/dev/null; then
    pass "使用 Developer ID Application 签名"
  else
    fail "不是 Developer ID Application 签名"
  fi
  if grep -Eq 'flags=.*runtime' <<<"${info}"; then
    pass "已启用 hardened runtime"
  else
    fail "未启用 hardened runtime"
  fi
  if codesign --verify --deep --strict "${app_path}"; then
    pass "深度签名校验通过"
  else
    fail "深度签名校验失败"
  fi
  entitlements="$(mktemp "${TMPDIR:-/tmp}/yundo-readiness-entitlements.XXXXXX")"
  trap 'rm -f "${entitlements}"' EXIT
  codesign -d --entitlements :- "${app_path}" >"${entitlements}" 2>/dev/null || true
  if grep -F 'com.apple.security.get-task-allow' "${entitlements}" >/dev/null; then
    fail "仍包含 get-task-allow entitlement"
  else
    pass "未包含 get-task-allow entitlement"
  fi
  if find "${app_path}" -iname '*hiddify*' -print -quit | grep -q .; then
    fail "包内仍有 Hiddify 可见文件名"
  else
    pass "包内没有 Hiddify 可见文件名"
  fi
  helper_path="${app_path}/Contents/Library/HelperTools/YundoPrivilegedHelper"
  if [[ -x "${helper_path}" ]]; then
    helper_info="$(codesign -dvv "${helper_path}" 2>&1 || true)"
    app_team="$(sed -n 's/^TeamIdentifier=//p' <<<"${info}")"
    helper_team="$(sed -n 's/^TeamIdentifier=//p' <<<"${helper_info}")"
    if [[ -n "${app_team}" && "${app_team}" == "${helper_team}" ]]; then
      pass "App 与 Helper 使用同一签名团队"
    else
      fail "App 与 Helper 签名团队不一致"
    fi
  else
    fail "缺少特权辅助进程"
  fi
fi

if [[ -n "${identity}" ]]; then
  if security find-identity -v -p codesigning | grep -F "\"${identity}\"" >/dev/null; then
    pass "本机钥匙串存在指定 Developer ID 身份"
  else
    fail "本机钥匙串不存在指定 Developer ID 身份"
  fi
else
  warn "未设置 YUNDO_DEVELOPER_ID_APPLICATION，无法绑定预期证书"
fi

if [[ -n "${profile}" ]]; then
  if xcrun notarytool history --keychain-profile "${profile}" >/dev/null 2>&1; then
    pass "notarytool 凭据可用：${profile}"
  else
    fail "notarytool 凭据不可用：${profile}"
  fi
else
  warn "未设置 YUNDO_NOTARY_PROFILE，尚未配置公证凭据"
fi

if [[ "${strict}" == true && "${blocking}" -ne 0 ]]; then
  echo "发行就绪检查未通过。"
  exit 1
fi
if [[ "${blocking}" -ne 0 ]]; then
  echo "发行就绪检查存在待处理项。"
else
  echo "发行就绪检查通过。"
fi
