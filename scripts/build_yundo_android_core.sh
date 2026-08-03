#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
core_dir="${repo_root}/hiddify-core"
output_aar="${1:-${repo_root}/android/app/libs/hiddify-core.aar}"
if [[ "${output_aar}" != /* ]]; then
  output_aar="${repo_root}/${output_aar}"
fi
patch_file="${repo_root}/patches/hiddify-core/0001-managed-route-options.patch"
go_bin="${GO_BIN:-$(command -v go || true)}"
work_dir=""

fail() {
  echo "Yundo Android Core 构建失败：$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${work_dir}" || ! -d "${work_dir}" ]] || rm -rf "${work_dir}"
  if git -C "${core_dir}" apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}" apply --reverse "${patch_file}"
  fi
}

for command_name in git perl strings unzip zip; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "缺少 ${command_name}"
done
[[ -x "${go_bin}" ]] || fail "缺少 Go"
[[ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]] || fail "缺少 Android SDK 环境变量"

"${script_dir}/apply_yundo_core_patches.sh"
trap cleanup EXIT
git -C "${core_dir}" submodule update --init --recursive

export GOTOOLCHAIN=go1.25.6
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"
export PATH="$(${go_bin} env GOPATH)/bin:${PATH}"

(cd "${core_dir}" && "${go_bin}" install github.com/sagernet/gomobile/cmd/gomobile@v0.1.11)
(cd "${core_dir}" && "${go_bin}" install github.com/sagernet/gomobile/cmd/gobind@v0.1.11)

mkdir -p "${core_dir}/bin"
(cd "${core_dir}" && \
  CGO_LDFLAGS='-O2 -g -s -w -Wl,-z,max-page-size=16384' \
  gomobile bind -v -androidapi=21 -javapkg=com.hiddify.core -libname=hiddify-core \
    -tags=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_naive_outbound,with_conntrack \
    -trimpath '-ldflags=-w -s -checklinkname=0 -buildid=' -target=android \
    -o bin/hiddify-core.aar github.com/sagernet/sing-box/experimental/libbox ./platform/mobile)

work_dir="$(mktemp -d)"
mkdir -p "${work_dir}/aar" "${work_dir}/classes"
unzip -q "${core_dir}/bin/hiddify-core.aar" -d "${work_dir}/aar"
unzip -q "${work_dir}/aar/classes.jar" -d "${work_dir}/classes"
LC_ALL=C perl -pi -e 's/hiddify-core/YundoCoreLib/g' "${work_dir}/classes/go/Seq.class"
(cd "${work_dir}/classes" && zip -q -r "${work_dir}/classes.jar" .)
mv "${work_dir}/classes.jar" "${work_dir}/aar/classes.jar"
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  mv "${work_dir}/aar/jni/${abi}/libhiddify-core.so" "${work_dir}/aar/jni/${abi}/libYundoCoreLib.so"
done
if unzip -p "${work_dir}/aar/classes.jar" go/Seq.class | strings | grep -F 'hiddify-core' >/dev/null; then
  fail "Android 加载器仍包含上游动态库文件名"
fi
strings_file="${work_dir}/core-strings.txt"
strings "${work_dir}/aar/jni/arm64-v8a/libYundoCoreLib.so" >"${strings_file}"
grep -F 'managed-route-rules' "${strings_file}" >/dev/null \
  || fail "Android Core 不包含受控规则入口"

mkdir -p "$(dirname "${output_aar}")"
(cd "${work_dir}/aar" && zip -q -r "${output_aar}" .)
[[ -f "${output_aar}" ]] || fail "未生成 Android AAR"
