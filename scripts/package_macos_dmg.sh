#!/usr/bin/env bash
set -euo pipefail

app_path="build/macos/Build/Products/Release/Yundo.app"
output_dir=""
notarize=false
profile="${YUNDO_NOTARY_PROFILE:-}"

fail() { echo "错误：$*" >&2; exit 1; }

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --app) app_path="${2:?--app 需要路径}"; shift 2 ;;
    --output-dir) output_dir="${2:?--output-dir 需要路径}"; shift 2 ;;
    --notarize) notarize=true; shift ;;
    --profile) profile="${2:?--profile 需要名称}"; shift 2 ;;
    *) fail "不支持的参数：$1" ;;
  esac
done

[[ -d "${app_path}" ]] || fail "找不到 macOS App：${app_path}"
command -v hdiutil >/dev/null 2>&1 || fail "缺少 hdiutil"
command -v ditto >/dev/null 2>&1 || fail "缺少 ditto"
codesign --verify --deep --strict "${app_path}" || fail "App 签名校验失败"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_path}/Contents/Info.plist")"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
short_sha="$(git -C "${repo_root}" rev-parse --short=12 HEAD 2>/dev/null || echo local)"
output_dir="${output_dir:-${repo_root}/client-builds/${version}-build${build}-${short_sha}}"
mkdir -p "${output_dir}"

stage_root="$(mktemp -d "${TMPDIR:-/tmp}/yundo-dmg-stage.XXXXXX")"
cleanup() { rm -rf "${stage_root}"; }
trap cleanup EXIT
ditto "${app_path}" "${stage_root}/Yundo.app"
ln -s /Applications "${stage_root}/Applications"

dmg_path="${output_dir}/Yundo-macOS-${version}-build${build}.dmg"
rm -f "${dmg_path}"
hdiutil create -volname "云渡" -srcfolder "${stage_root}" -ov -format UDZO "${dmg_path}" >/dev/null

if [[ "${notarize}" == true ]]; then
  [[ -n "${profile}" ]] || fail "公证需要 --profile 或 YUNDO_NOTARY_PROFILE"
  xcrun notarytool submit "${dmg_path}" --keychain-profile "${profile}" --wait
  xcrun stapler staple "${dmg_path}"
  xcrun stapler validate "${dmg_path}"
else
  echo "未执行公证；这是本地签名 DMG，不建议直接发给朋友。"
fi

hash_file="${output_dir}/SHA256SUMS"
shasum -a 256 "${dmg_path}" | tee "${hash_file}"
echo "DMG：${dmg_path}"
