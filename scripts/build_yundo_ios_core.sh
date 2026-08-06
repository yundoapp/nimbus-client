#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
core_dir="${repo_root}/hiddify-core"
output_framework="${1:-${repo_root}/ios/Frameworks/HiddifyCore.xcframework}"
if [[ "${output_framework}" != /* ]]; then
  output_framework="${repo_root}/${output_framework}"
fi
patch_file="${repo_root}/patches/hiddify-core/0001-managed-route-options.patch"
rule_set_patch_file="${repo_root}/patches/hiddify-core/0002-rule-set-observability-and-root-domain.patch"
observability_patch_file="${repo_root}/patches/hiddify-core/0003-connection-observability-and-actual-outbound.patch"
exact_history_patch_file="${repo_root}/patches/hiddify-core/0004-exact-route-decision-history.patch"
bundled_rule_set_patch_file="${repo_root}/patches/hiddify-core/0005-bundled-rule-set-fallback.patch"
go_bin="${GO_BIN:-$(command -v go || true)}"

fail() {
  echo "Yundo iOS Core 构建失败：$*" >&2
  exit 1
}

restore_core_source() {
  if git -C "${core_dir}/hiddify-sing-box" apply --reverse --check "${bundled_rule_set_patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}/hiddify-sing-box" apply --reverse "${bundled_rule_set_patch_file}"
  fi
  if git -C "${core_dir}/hiddify-sing-box" apply --reverse --check "${exact_history_patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}/hiddify-sing-box" apply --reverse "${exact_history_patch_file}"
  fi
  if git -C "${core_dir}/hiddify-sing-box" apply --reverse --check "${observability_patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}/hiddify-sing-box" apply --reverse "${observability_patch_file}"
  fi
  if git -C "${core_dir}/hiddify-sing-box" apply --reverse --check "${rule_set_patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}/hiddify-sing-box" apply --reverse "${rule_set_patch_file}"
  fi
  if git -C "${core_dir}" apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}" apply --reverse "${patch_file}"
  fi
}

for command_name in ditto find git strings xcodebuild; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "缺少 ${command_name}"
done
[[ -x "${go_bin}" ]] || fail "缺少 Go"

"${script_dir}/apply_yundo_core_patches.sh"
trap restore_core_source EXIT
git -C "${core_dir}" submodule update --init --recursive

export GOTOOLCHAIN=go1.25.6
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"
export PATH="$(${go_bin} env GOPATH)/bin:${PATH}"
go_path="$(${go_bin} env GOPATH)"

if [[ ! -x "${go_path}/bin/gomobile" || ! -x "${go_path}/bin/gobind" ]]; then
  (cd "${core_dir}" && "${go_bin}" install github.com/sagernet/gomobile/cmd/gomobile@v0.1.11)
  (cd "${core_dir}" && "${go_bin}" install github.com/sagernet/gomobile/cmd/gobind@v0.1.11)
fi

rm -rf "${core_dir}/bin/HiddifyCore.xcframework" "${output_framework}"
mkdir -p "${core_dir}/bin" "$(dirname "${output_framework}")"
(cd "${core_dir}" && \
  gomobile bind -v -target=ios -libname=hiddify-core \
    -tags=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_naive_outbound,with_conntrack,with_dhcp,with_low_memory,with_purego \
    -trimpath '-ldflags=-w -s -checklinkname=0 -buildid=' \
    -o bin/HiddifyCore.xcframework github.com/sagernet/sing-box/experimental/libbox ./platform/mobile)
cp "${core_dir}/Info.plist" "${core_dir}/bin/HiddifyCore.xcframework/"
ditto "${core_dir}/bin/HiddifyCore.xcframework" "${output_framework}"

binary_path="$(find "${output_framework}" -type f -name HiddifyCore -print -quit)"
[[ -n "${binary_path}" ]] || fail "未找到 iOS Core 二进制"
strings_file="$(mktemp)"
trap 'rm -f "${strings_file}"; restore_core_source' EXIT
strings "${binary_path}" >"${strings_file}"
grep -F 'managed-route-rules' "${strings_file}" >/dev/null \
  || fail "iOS Core 不包含受控规则入口"
grep -F 'yundo_exact_history' "${strings_file}" >/dev/null \
  || fail "iOS Core 不包含精确路由记录"
xcodebuild -create-xcframework -help >/dev/null
