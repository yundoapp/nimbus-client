#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
core_dir="${repo_root}/hiddify-core"
output_dir="${1:-${repo_root}/out/yundo-windows-core}"
if [[ "${output_dir}" != /* ]]; then
  output_dir="${repo_root}/${output_dir}"
fi
makefile="${core_dir}/Makefile"
icon_file="${repo_root}/windows/runner/resources/app_icon.ico"
patch_file="${repo_root}/patches/hiddify-core/0001-managed-route-options.patch"
go_bin="${GO_BIN:-$(command -v go || true)}"
backup_dir=""
strings_file=""

fail() {
  echo "Yundo Windows Core 构建失败：$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${strings_file}" || ! -f "${strings_file}" ]] || rm -f "${strings_file}"
  if [[ -n "${backup_dir}" && -d "${backup_dir}" ]]; then
    cp "${backup_dir}/Makefile" "${makefile}"
    cp "${backup_dir}/hiddify-cli.ico" "${core_dir}/assets/hiddify-cli.ico"
    rm -rf "${backup_dir}"
  fi
  if git -C "${core_dir}" apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}" apply --reverse "${patch_file}"
  fi
}

for command_name in git make perl sha256sum strings x86_64-w64-mingw32-objdump; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "缺少 ${command_name}"
done
[[ -x "${go_bin}" ]] || fail "缺少 Go"
[[ -f "${icon_file}" ]] || fail "缺少云渡 Windows 图标"

"${script_dir}/apply_yundo_core_patches.sh"
trap cleanup EXIT
git -C "${core_dir}" submodule update --init --recursive

# 上游目标会执行 go mod tidy，并尝试停止本机 Windows 服务；交叉编译时都不应执行。
backup_dir="$(mktemp -d)"
cp "${makefile}" "${backup_dir}/Makefile"
cp "${core_dir}/assets/hiddify-cli.ico" "${backup_dir}/hiddify-cli.ico"
if grep -Fq 'windows-amd64: prepare' "${makefile}"; then
  perl -0pi -e 's/windows-amd64: prepare/windows-amd64:/' "${makefile}"
fi
if grep -Fq $'\tgo run ./cli tunnel exit' "${makefile}"; then
  perl -0pi -e 's/\tgo run \.\/cli tunnel exit/\ttrue # cross build does not own a Windows process/' "${makefile}"
fi
cp "${icon_file}" "${core_dir}/assets/hiddify-cli.ico"

export GOTOOLCHAIN=go1.25.6
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"
export PATH="$(${go_bin} env GOPATH)/bin:${PATH}"

make -C "${core_dir}" LIBNAME=YundoCore CLINAME=YundoCore windows-amd64

core_dll="${core_dir}/bin/YundoCore.dll"
core_exe="${core_dir}/bin/YundoCore.exe"
cronet_dll="${core_dir}/bin/libcronet.dll"
[[ -f "${core_dll}" ]] || fail "未生成 YundoCore.dll"
[[ -f "${core_exe}" ]] || fail "未生成 YundoCore.exe"
[[ -f "${cronet_dll}" ]] || fail "未生成 libcronet.dll"

imports="$(x86_64-w64-mingw32-objdump -p "${core_exe}")"
grep -Fq 'DLL Name: YundoCore.dll' <<<"${imports}" || fail "YundoCore.exe 未链接 YundoCore.dll"
if grep -Fiq 'hiddify-core.dll' <<<"${imports}"; then
  fail "YundoCore.exe 仍链接上游文件名"
fi
strings_file="$(mktemp)"
strings "${core_dll}" >"${strings_file}"
grep -F 'managed-route-rules' "${strings_file}" >/dev/null \
  || fail "Core 不包含受控规则入口"

mkdir -p "${output_dir}"
cp "${core_dll}" "${core_exe}" "${cronet_dll}" "${output_dir}/"
printf 'coreCommit=%s\n' "$(git -C "${core_dir}" rev-parse HEAD)" >"${output_dir}/build-metadata.txt"
printf 'patchSha256=%s\n' "$(sha256sum "${repo_root}/patches/hiddify-core/0001-managed-route-options.patch" | awk '{print $1}')" >>"${output_dir}/build-metadata.txt"
sha256sum "${output_dir}/YundoCore.dll" "${output_dir}/YundoCore.exe" "${output_dir}/libcronet.dll"
