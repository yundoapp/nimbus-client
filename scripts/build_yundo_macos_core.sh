#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
core_dir="${repo_root}/hiddify-core"
core_bin="${core_dir}/bin"
core_library="${core_bin}/hiddify-core.dylib"
patch_file="${repo_root}/patches/hiddify-core/0001-managed-route-options.patch"
rule_set_patch_file="${repo_root}/patches/hiddify-core/0002-rule-set-observability-and-root-domain.patch"
stamp_file="${core_bin}/.yundo-managed-route-core"
go_bin="${GO_BIN:-$(command -v go || true)}"

fail() {
  echo "Yundo macOS Core build failed: $*" >&2
  exit 1
}

restore_core_source() {
  if git -C "${core_dir}/hiddify-sing-box" apply --reverse --check "${rule_set_patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}/hiddify-sing-box" apply --reverse "${rule_set_patch_file}"
  fi
  if git -C "${core_dir}" apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
    git -C "${core_dir}" apply --reverse "${patch_file}"
  fi
}

[[ -x "${go_bin}" ]] || fail "Go is not installed"
command -v git >/dev/null || fail "git is required"
command -v lipo >/dev/null || fail "lipo is required"
command -v shasum >/dev/null || fail "shasum is required"

"${script_dir}/apply_yundo_core_patches.sh"
trap restore_core_source EXIT
git -C "${core_dir}" submodule update --init --recursive

core_commit="$(git -C "${core_dir}" rev-parse HEAD)"
patch_hash="$(cat "${patch_file}" "${rule_set_patch_file}" | shasum -a 256 | awk '{print $1}')"
build_key="${core_commit}:${patch_hash}:go1.25.6"
if [[ -f "${core_library}" && -f "${stamp_file}" ]] \
  && [[ "$(cat "${stamp_file}")" == "${build_key}" ]]; then
  exit 0
fi

mkdir -p "${core_bin}"
tags="with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_naive_outbound,with_conntrack,with_dhcp"
ldflags="-w -s -checklinkname=0 -buildid="
common_env=(
  "GOTOOLCHAIN=go1.25.6"
  "GOPROXY=${GOPROXY:-https://goproxy.cn,direct}"
  "GOSUMDB=${GOSUMDB:-sum.golang.google.cn}"
  "CGO_ENABLED=1"
  "CGO_CFLAGS=-mmacosx-version-min=10.11 -O2"
  "CGO_LDFLAGS=-mmacosx-version-min=10.11 -O2 -lpthread"
)

(
  cd "${core_dir}"
  env "${common_env[@]}" GOOS=darwin GOARCH=amd64 "${go_bin}" build \
    -trimpath -tags "${tags}" -ldflags "${ldflags}" -buildmode=c-shared \
    -o "${core_bin}/hiddify-core-amd64.dylib" ./platform/desktop
  env "${common_env[@]}" GOOS=darwin GOARCH=arm64 "${go_bin}" build \
    -trimpath -tags "${tags}" -ldflags "${ldflags}" -buildmode=c-shared \
    -o "${core_bin}/hiddify-core-arm64.dylib" ./platform/desktop
)

lipo -create \
  "${core_bin}/hiddify-core-amd64.dylib" \
  "${core_bin}/hiddify-core-arm64.dylib" \
  -output "${core_library}"
mv "${core_bin}/hiddify-core-arm64.h" "${core_bin}/desktop.h"

strings "${core_library}" | grep -F 'managed-route-rules' >/dev/null \
  || fail "built Core does not contain the managed route option"
printf '%s\n' "${build_key}" >"${stamp_file}"
