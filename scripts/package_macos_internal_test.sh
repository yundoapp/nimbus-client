#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source_app="${1:-${repo_root}/build/macos/Build/Products/Debug/Yundo Dev.app}"
output_dir="${2:-${repo_root}/build/internal-test}"
expected_display_name="${YUNDO_EXPECTED_DISPLAY_NAME:-Yundo Dev}"
expected_bundle_id="${YUNDO_EXPECTED_BUNDLE_ID:-app.yundo.client.dev}"
forbidden_brand_marker="${YUNDO_FORBIDDEN_BRAND_MARKER:-win""tion}"

fail() {
  echo "错误：$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少必要命令：$1"
}

for command_name in codesign ditto file git rg shasum unzip; do
  require_command "$command_name"
done

plist_buddy="/usr/libexec/PlistBuddy"
[[ -x "$plist_buddy" ]] || fail "缺少必要命令：${plist_buddy}"
[[ -d "$source_app" ]] || fail "找不到 App：${source_app}"

info_plist="${source_app}/Contents/Info.plist"
[[ -f "$info_plist" ]] || fail "找不到 Info.plist：${info_plist}"

read_plist() {
  "$plist_buddy" -c "Print :$1" "$info_plist"
}

assert_no_forbidden_branding() {
  local target="$1"
  local matches
  matches="$(rg -a -i -l -- "$forbidden_brand_marker" "$target" || true)"
  [[ -z "$matches" ]] || fail "构建产物包含禁用品牌标识：${matches}"
}

display_name="$(read_plist CFBundleDisplayName)"
bundle_name="$(read_plist CFBundleName)"
bundle_id="$(read_plist CFBundleIdentifier)"
version="$(read_plist CFBundleShortVersionString)"
build_number="$(read_plist CFBundleVersion)"
executable_name="$(read_plist CFBundleExecutable)"
executable_path="${source_app}/Contents/MacOS/${executable_name}"

[[ "$display_name" == "$expected_display_name" ]] || fail "显示名不正确：${display_name}"
[[ "$bundle_name" == "$expected_display_name" ]] || fail "Bundle 名称不正确：${bundle_name}"
[[ "$bundle_id" == "$expected_bundle_id" ]] || fail "Bundle ID 不正确：${bundle_id}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版本号格式不正确：${version}"
[[ "$build_number" =~ ^[0-9]+$ ]] || fail "构建号格式不正确：${build_number}"
(( build_number >= 10000 )) || fail "构建号不能小于 10000"
[[ -x "$executable_path" ]] || fail "找不到 App 可执行文件：${executable_path}"
assert_no_forbidden_branding "$source_app"

architecture_output="$(file "$executable_path")"
if [[ "$architecture_output" != *"arm64"* && "$architecture_output" != *"x86_64"* ]]; then
  fail "不支持的可执行文件架构：${architecture_output}"
fi

timestamp="${YUNDO_PACKAGE_TIMESTAMP:-$(date '+%Y%m%d%H%M%S')}"
[[ "$timestamp" =~ ^[0-9]{14}$ ]] || fail "YUNDO_PACKAGE_TIMESTAMP 必须使用 YYYYMMDDHHMMSS 格式"

artifact_name="yundo-macos-dev-${version}+${build_number}-${timestamp}.zip"
artifact_path="${output_dir}/${artifact_name}"
checksum_path="${artifact_path}.sha256"
manifest_path="${artifact_path}.manifest.txt"

mkdir -p "$output_dir"
[[ ! -e "$artifact_path" ]] || fail "产物已存在：${artifact_path}"

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/yundo-internal-test.XXXXXX")"
cleanup() {
  rm -rf "$staging_root"
}
trap cleanup EXIT

staged_app="${staging_root}/${expected_display_name}.app"
ditto "$source_app" "$staged_app"

# Debug 构建可能残留不完整的嵌套 ad hoc 签名。这里只重签临时副本，
# 并在压缩后重新解包，验证最终归档中的实际内容。
codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"

ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$artifact_path"
unzip -tq "$artifact_path" >/dev/null

verification_dir="${staging_root}/verified"
mkdir -p "$verification_dir"
ditto -x -k "$artifact_path" "$verification_dir"
codesign --verify --deep --strict "${verification_dir}/${expected_display_name}.app"
assert_no_forbidden_branding "${verification_dir}/${expected_display_name}.app"

(
  cd "$output_dir"
  shasum -a 256 "$artifact_name" >"${artifact_name}.sha256"
)

source_commit="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
source_state="clean"
if [[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null || true)" ]]; then
  source_state="dirty"
fi
sha256="$(awk '{print $1}' "$checksum_path")"

cat >"$manifest_path" <<EOF
artifact=${artifact_name}
sha256=${sha256}
display_name=${display_name}
bundle_id=${bundle_id}
version=${version}
build_number=${build_number}
signature=adhoc
source_commit=${source_commit}
source_state=${source_state}
forbidden_branding_scan=passed
architecture=${architecture_output#*: }
created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

cat <<EOF
macOS 内测包已生成并完成校验。

产物：${artifact_path}
校验：${checksum_path}
清单：${manifest_path}
Bundle：${bundle_id} ${version}+${build_number}
源码：${source_commit} (${source_state})
EOF
