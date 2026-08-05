#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
identity="${YUNDO_DEVELOPER_ID_APPLICATION:-}"

fail() { echo "错误：$*" >&2; exit 1; }

if [[ -z "${identity}" ]]; then
  identity="$(security find-identity -v -p codesigning | awk '/Developer ID Application/ { print $2; exit }')"
fi
[[ -n "${identity}" ]] || fail "找不到 Developer ID Application；请设置 YUNDO_DEVELOPER_ID_APPLICATION"

export MACOS_CODESIGN_IDENTITY="${identity}"
export YUNDO_DISTRIBUTION=1
FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}" \
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  YUNDO_LOCAL_BUILD_NUMBER="${YUNDO_LOCAL_BUILD_NUMBER:-}" \
  "${script_dir}/build_install_macos_local_prod.sh"

package_args=(--app "${repo_root}/build/macos/Build/Products/Release/Yundo.app")
if [[ "${YUNDO_NOTARIZE:-0}" == 1 ]]; then
  package_args+=(--notarize)
  [[ -n "${YUNDO_NOTARY_PROFILE:-}" ]] || fail "YUNDO_NOTARIZE=1 时必须设置 YUNDO_NOTARY_PROFILE"
fi
"${script_dir}/package_macos_dmg.sh" "${package_args[@]}"
